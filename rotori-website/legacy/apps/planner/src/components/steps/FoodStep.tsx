import {
  dietaryForCountry,
  getDestinationProfile,
  getDestinationForDate,
  dietaryTagsFromSensitivities,
} from '@japan-trip/shared';
import type {
  DestinationFoodPrefs,
  FoodSensitivity,
  Trip,
} from '@japan-trip/shared';

const SENSITIVITY_OPTIONS: { id: FoodSensitivity; label: string; emoji: string }[] = [
  { id: 'no_pork', label: 'Domuz eti istemiyorum', emoji: '🚫🐖' },
  { id: 'no_pork_derivatives', label: 'Domuz yağı / jelatin yok', emoji: '🚫🥓' },
  { id: 'no_seafood', label: 'Deniz ürünü istemiyorum', emoji: '🚫🐟' },
  { id: 'halal_only', label: 'Helal seçenek istiyorum', emoji: '🕌' },
  { id: 'vegetarian', label: 'Vejetaryen', emoji: '🥗' },
  { id: 'chicken_focus', label: 'Tavuk ağırlıklı', emoji: '🍗' },
  { id: 'no_fatty_meat', label: 'Yağlı et sevmiyorum', emoji: '🚫🥩' },
  { id: 'kid_friendly', label: 'Çocuk dostu restoran', emoji: '🧒' },
  { id: 'turkish_palate', label: 'Türk damak tadına yakın', emoji: '🇹🇷' },
];

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

function getFoodPrefs(trip: Trip, destId: string): DestinationFoodPrefs {
  const found = trip.preferences.destinationFood?.find((f) => f.destinationId === destId);
  if (found) return found;
  return {
    destinationId: destId,
    dietaryTags: [],
    foodLikes: [],
    foodDislikes: [],
  };
}

function patchFood(
  trip: Trip,
  destId: string,
  patch: Partial<DestinationFoodPrefs>,
): Trip['preferences']['destinationFood'] {
  const list = [...(trip.preferences.destinationFood ?? [])];
  const idx = list.findIndex((f) => f.destinationId === destId);
  const base = idx >= 0 ? list[idx] : getFoodPrefs(trip, destId);
  const next = { ...base, ...patch, destinationId: destId };
  if (idx >= 0) list[idx] = next;
  else list.push(next);
  return list;
}

export function FoodStep({ trip, onChange }: Props) {
  const destinations = [...(trip.preferences.destinations ?? [])].sort(
    (a, b) => a.order - b.order,
  );

  if (!destinations.length) {
    return (
      <>
        <h2 className="page-headline">Yemek</h2>
        <p className="page-sub">Önce Seyahat adımında durak ekleyin.</p>
      </>
    );
  }

  const sensitivities = new Set(trip.preferences.foodSensitivities ?? []);

  const toggleSensitivity = (id: FoodSensitivity) => {
    onChange((t) => {
      const cur = new Set(t.preferences.foodSensitivities ?? []);
      if (cur.has(id)) cur.delete(id);
      else cur.add(id);
      const next = Array.from(cur);
      const derivedTags = dietaryTagsFromSensitivities(next);
      const existingTags = (t.preferences.dietaryTags ?? []).filter(
        // foodSensitivity'den türeyen tag'leri her seferinde yeniden hesapla;
        // kullanıcının elle eklediği başka tag'leri koru.
        (tag) =>
          !['no_pork', 'no_seafood', 'halal', 'vegetarian', 'kid_friendly', 'chicken_focus', 'turkish_palate', 'no_fatty_meat'].includes(
            tag,
          ),
      );
      return {
        ...t,
        preferences: {
          ...t.preferences,
          foodSensitivities: next,
          dietaryTags: Array.from(new Set([...existingTags, ...derivedTags])),
        },
      };
    });
  };

  return (
    <>
      <h2 className="page-headline">Yemek tercihleri</h2>
      <p className="page-sub">
        Hassasiyetlerini seç — plan ve restoran önerileri buna göre filtrelenir.
      </p>

      <section className="card sensitivity-card">
        <div className="card-title">🍽️ Yemek hassasiyetleri</div>
        <div className="chip-group">
          {SENSITIVITY_OPTIONS.map((opt) => (
            <button
              type="button"
              key={opt.id}
              aria-pressed={sensitivities.has(opt.id)}
              className={`chip${sensitivities.has(opt.id) ? ' chip-active' : ''}`}
              onClick={() => toggleSensitivity(opt.id)}
            >
              <span>{opt.emoji}</span> {opt.label}
            </button>
          ))}
        </div>
        <p className="sensitivity-note">
          Bu seçimler tüm gezi için geçerlidir; viewer'da hap bilgi ve fraz kartlarına yansır.
        </p>
      </section>

      {destinations.map((dest) => {
        const profile = getDestinationProfile(dest.countryCode);
        const food = getFoodPrefs(trip, dest.id);
        const tags = new Set(food.dietaryTags);
        const dayCount = trip.days.filter(
          (d) => getDestinationForDate(destinations, d.date)?.id === dest.id,
        ).length;

        const updateFood = (patch: Partial<DestinationFoodPrefs>) => {
          onChange((t) => ({
            ...t,
            preferences: {
              ...t.preferences,
              destinationFood: patchFood(t, dest.id, patch),
            },
          }));
        };

        const toggleTag = (id: string) => {
          const next = new Set(tags);
          if (next.has(id)) next.delete(id);
          else next.add(id);
          updateFood({ dietaryTags: [...next] });
        };

        const toggleCuisine = (label: string) => {
          const likes = food.foodLikes;
          updateFood({
            foodLikes: likes.includes(label)
              ? likes.filter((x) => x !== label)
              : [...likes, label],
          });
        };

        const cuisines = profile?.cuisines ?? [];
        const dishes = profile?.dishRecommendations ?? [];
        const dietaryOpts = dietaryForCountry(dest.countryCode);

        return (
          <div key={dest.id} className="card dest-food-card">
            <div className="card-title">
              {profile?.flag} {dest.countryName}
              {dest.city ? ` · ${dest.city}` : ''}
              <span style={{ fontWeight: 400, color: 'var(--text-tertiary)' }}>
                {' '}
                · ~{dayCount} gün
              </span>
            </div>

            {dishes.length > 0 && (
              <div className="dish-suggestions">
                <p style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>
                  Önerilen lezzetler ({dest.countryName})
                </p>
                <ul className="dish-list">
                  {dishes.map((dish) => (
                    <li key={dish}>
                      <button
                        type="button"
                        className={`dish-pill${food.foodLikes.includes(dish) ? ' selected' : ''}`}
                        onClick={() => toggleCuisine(dish)}
                      >
                        {food.foodLikes.includes(dish) ? '✓ ' : '+ '}
                        {dish}
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <p style={{ fontSize: 13, color: 'var(--text-secondary)', margin: '16px 0 8px' }}>
              Beslenme tercihleri
            </p>
            <div className="diet-grid">
              {dietaryOpts.map((opt) => (
                <label
                  key={opt.id}
                  className={`diet-card${tags.has(opt.id) ? ' selected' : ''}`}
                >
                  <input
                    type="checkbox"
                    checked={tags.has(opt.id)}
                    onChange={() => toggleTag(opt.id)}
                  />
                  <div className="diet-emoji">{opt.emoji}</div>
                  <div className="diet-label">{opt.label}</div>
                  <div className="diet-desc">{opt.description}</div>
                </label>
              ))}
            </div>

            {cuisines.length > 0 && (
              <>
                <p style={{ fontSize: 13, color: 'var(--text-secondary)', margin: '16px 0 8px' }}>
                  Mutfak türleri
                </p>
                <div className="diet-grid">
                  {cuisines.map((c) => (
                    <label
                      key={c.id}
                      className={`diet-card${food.foodLikes.includes(c.label) ? ' selected' : ''}`}
                    >
                      <input
                        type="checkbox"
                        checked={food.foodLikes.includes(c.label)}
                        onChange={() => toggleCuisine(c.label)}
                      />
                      <div className="diet-emoji">{c.emoji}</div>
                      <div className="diet-label">{c.label}</div>
                    </label>
                  ))}
                </div>
              </>
            )}

            <div className="grid-2" style={{ marginTop: 16 }}>
              <div className="field">
                <label>Kişi başı öğün ({profile?.defaultCurrency ?? 'EUR'})</label>
                <input
                  type="number"
                  value={food.mealBudgetPerPerson ?? 50}
                  onChange={(e) =>
                    updateFood({ mealBudgetPerPerson: Number(e.target.value) })
                  }
                />
              </div>
              <div className="field">
                <label>Para birimi</label>
                <input
                  value={food.mealBudgetCurrency ?? profile?.defaultCurrency ?? 'EUR'}
                  onChange={(e) => updateFood({ mealBudgetCurrency: e.target.value })}
                />
              </div>
            </div>
          </div>
        );
      })}
    </>
  );
}
