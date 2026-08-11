import { corsHeaders } from "../_shared/cors.ts";

type Location = {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
};

type GoogleMatrixItem = {
  originIndex?: number;
  destinationIndex?: number;
  distanceMeters?: number;
  duration?: string;
  condition?: string;
  status?: { code?: number };
};

const endpoint =
  "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix";
const fieldMask =
  "originIndex,destinationIndex,distanceMeters,duration,condition,status";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  try {
    const body = await request.json();
    const locations = validateLocations(body.locations);
    if (locations.length < 2 || locations.length > 10) {
      return json({ error: "locations must contain 2-10 points" }, 400);
    }
    const apiKey = Deno.env.get("GOOGLE_MAPS_ROUTES_API_KEY");
    if (!apiKey) return json({ error: "route provider is not configured" }, 503);

    const departureTime = safeDepartureTime(body.day);
    const [walking, transit, driving] = await Promise.all([
      computeMatrix(apiKey, locations, "WALK", departureTime),
      computeMatrix(apiKey, locations, "TRANSIT", departureTime),
      computeMatrix(apiKey, locations, "DRIVE", departureTime),
    ]);
    const entries = normalize(locations, walking, transit, driving);
    if (entries.length === 0) return json({ error: "no routes found" }, 422);

    return json({
      version: `google-routes-${new Date().toISOString().slice(0, 13)}`,
      entries,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown failure";
    return json({ error: message }, 502);
  }
});

function validateLocations(raw: unknown): Location[] {
  if (!Array.isArray(raw)) throw new Error("locations must be an array");
  return raw.map((value) => {
    if (!value || typeof value !== "object") throw new Error("invalid location");
    const row = value as Record<string, unknown>;
    const latitude = Number(row.latitude);
    const longitude = Number(row.longitude);
    if (
      typeof row.id !== "string" || row.id.length === 0 ||
      !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180
    ) throw new Error("invalid location fields");
    return {
      id: row.id,
      name: typeof row.name === "string" ? row.name : row.id,
      latitude,
      longitude,
    };
  });
}

async function computeMatrix(
  apiKey: string,
  locations: Location[],
  travelMode: "WALK" | "TRANSIT" | "DRIVE",
  departureTime: string,
): Promise<GoogleMatrixItem[]> {
  const waypoints = locations.map((location) => ({
    waypoint: {
      location: {
        latLng: {
          latitude: location.latitude,
          longitude: location.longitude,
        },
      },
    },
  }));
  const payload: Record<string, unknown> = {
    origins: waypoints,
    destinations: waypoints,
    travelMode,
    languageCode: "tr",
    units: "METRIC",
  };
  if (travelMode !== "WALK") payload.departureTime = departureTime;
  if (travelMode === "DRIVE") payload.routingPreference = "TRAFFIC_AWARE";

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": fieldMask,
    },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    throw new Error(`${travelMode} matrix failed (${response.status}): ${detail}`);
  }
  return await response.json() as GoogleMatrixItem[];
}

function normalize(
  locations: Location[],
  walking: GoogleMatrixItem[],
  transit: GoogleMatrixItem[],
  driving: GoogleMatrixItem[],
) {
  const maps = [indexByDirection(walking), indexByDirection(transit), indexByDirection(driving)];
  const entries = [];
  for (let from = 0; from < locations.length; from++) {
    for (let to = 0; to < locations.length; to++) {
      if (from === to) continue;
      const options = [];
      const walk = maps[0].get(`${from}:${to}`);
      const train = maps[1].get(`${from}:${to}`);
      const drive = maps[2].get(`${from}:${to}`);
      if (usable(walk)) {
        const minutes = durationMinutes(walk!.duration!);
        options.push(option("walking", minutes, minutes, 0, 0, 0, 0.9));
      }
      if (usable(train)) {
        const minutes = durationMinutes(train!.duration!);
        const distanceKm = (train!.distanceMeters ?? 0) / 1000;
        options.push(option(
          "train", minutes, 0, 0, 0,
          Math.max(180, Math.round(150 + distanceKm * 28)), 0.82, true,
        ));
      }
      if (usable(drive)) {
        const minutes = durationMinutes(drive!.duration!);
        const distanceKm = (drive!.distanceMeters ?? 0) / 1000;
        options.push({
          ...option(
            "taxi", minutes, 0, 0, 0,
            Math.max(500, Math.round(500 + distanceKm * 360)), 0.78, true,
          ),
          fareBasis: "perVehicle",
        });
      }
      if (options.length > 0) {
        entries.push({
          fromLocationId: locations[from].id,
          toLocationId: locations[to].id,
          options,
        });
      }
    }
  }
  return entries;
}

function option(
  mode: string,
  doorToDoorMinutes: number,
  walkingMinutes: number,
  waitingMinutes: number,
  transferCount: number,
  estimatedCostYen: number,
  reliabilityScore: number,
  isEstimated = false,
) {
  return {
    mode,
    doorToDoorMinutes,
    walkingMinutes,
    waitingMinutes,
    transferCount,
    estimatedCostYen,
    reliabilityScore,
    isEstimated,
    fareBasis: "perPerson",
    providerId: "google-routes",
  };
}

function indexByDirection(items: GoogleMatrixItem[]) {
  return new Map(items.map((item) => [
    `${item.originIndex}:${item.destinationIndex}`,
    item,
  ]));
}

function usable(item?: GoogleMatrixItem) {
  return item?.condition === "ROUTE_EXISTS" &&
    (item.status?.code ?? 0) === 0 &&
    typeof item.duration === "string";
}

function durationMinutes(value: string) {
  const seconds = Number(value.replace(/s$/, ""));
  return Math.max(0, Math.ceil(seconds / 60));
}

function safeDepartureTime(raw: unknown) {
  const requested = typeof raw === "string" ? new Date(raw) : new Date();
  const now = new Date();
  const earliest = new Date(now.getTime() + 5 * 60 * 1000);
  if (Number.isNaN(requested.getTime()) || requested < earliest) {
    return earliest.toISOString();
  }
  return requested.toISOString();
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
