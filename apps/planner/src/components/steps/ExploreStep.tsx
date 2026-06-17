import { useMemo, useState } from 'react';
import {
  addPlaceToDay,
  pickBestDayForDestination,
  getDestinationProfile,
  getDestinationForDate,
  getGuideDefaultsForCountry,
  recommendedFoods,
  placeRating,
  isKidFriendly,
  googleReviewsUrl,
  ratingStars,
  WALKING_TARGET_STEPS,
  type Trip,
  type PlaceSuggestion,
  type InterestTag,
  type WalkingTarget,
  type TransportPreference,
  type PaymentPreference,
  type ChildProfile,
} from '@japan-trip/shared';

const INTEREST_OPTIONS: { id: InterestTag; label: string; emoji: string }[] = [
  { id: 'anime', label: 'Anime / Manga', emoji: '🎴' },
  { id: 'pokemon', label: 'Pokémon', emoji: '⚡' },
  { id: 'shopping', label: 'Alışveriş', emoji: '🛍️' },
  { id: 'temples', label: 'Tapınaklar', emoji: '⛩️' },
  { id: 'traditional', label: 'Geleneksel Japonya', emoji: '🎎' },
  { id: 'tech', label: 'Teknoloji mağazaları', emoji: '🖥️' },
  { id: 'kids', label: 'Çocuk aktiviteleri', emoji: '🧸' },
  { id: 'theme_parks', label: 'Tema parkları', emoji: '🎢' },
  { id: 'photography', label: 'Fotoğraf noktaları', emoji: '📸' },
  { id: 'food', label: 'Yemek keşfi', emoji: '🍜' },
];

const WALKING_OPTIONS: { id: WalkingTarget; label: string; range: string }[] = [
  { id: 'light', label: 'Az yürüyüş', range: '5.000–8.000 adım' },
  { id: 'moderate', label: 'Orta tempo', range: '8.000–13.000 adım' },
  { id: 'intense', label: 'Yoğun tempo', range: '13.000+ adım' },
];

const TRANSPORT_OPTIONS: { id: TransportPreference; label: string; emoji: string }[] = [
  { id: 'transit', label: 'Metro / tren', emoji: '🚇' },
  { id: 'taxi_assisted', label: 'Taksi destekli', emoji: '🚕' },
  { id: 'walking', label: 'Yürüyüş ağırlıklı', emoji: '🚶' },
  { id: 'mixed', label: 'Karışık', emoji: '🔀' },
];

const PAYMENT_OPTIONS: { id: PaymentPreference; label: string; emoji: string }[] = [
  { id: 'credit_card', label: 'Kredi kartı', emoji: '💳' },
  { id: 'cash', label: 'Nakit', emoji: '💴' },
  { id: 'credit_and_cash', label: 'Kart + nakit', emoji: '🔄' },
  { id: 'ic_card', label: 'IC kart (Suica/Pasmo)', emoji: '🎫' },
];

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

export function ExploreStep({ trip, onChange }: Props) {
  const [added, setAdded] = useState<Record<string, string>>({});

  const planPlaceNames = useMemo(() => {
    const set = new Set<string>();
    for (const day of trip.days) {
      for (const item of day.items) {
        const t = item.title.replace(/^[^\p{L}\p{N}]+\s*/u, '').toLowerCase().trim();
        if (t) set.add(t);
      }
    }
    return set;
  }, [trip.days]);

  const destinations = useMemo(
    () => [...(trip.preferences.destinations ?? [])].sort((a, b) => a.order - b.order),
    [trip.preferences.destinations],
  );

  const prefs = trip.preferences;
  const childProfiles = prefs.childProfiles ?? [];
  const childrenCount = childProfiles.length || prefs.childrenCount || 0;
  const kidsMode = childrenCount > 0;
  const walkingTarget: WalkingTarget = prefs.walkingTarget ?? 'moderate';
  const transportPreference: TransportPreference = prefs.transportPreference ?? 'mixed';
  const paymentPreference: PaymentPreference = prefs.paymentPreference ?? 'credit_and_cash';
  const interests: InterestTag[] = prefs.interests ?? [];

  const setWalkingTarget = (target: WalkingTarget) =>
    onChange((t) => ({
      ...t,
      preferences: {
        ...t.preferences,
        walkingTarget: target,
        maxStepsPerDay: WALKING_TARGET_STEPS[target],
      },
    }));

  const setTransportPreference = (mode: TransportPreference) =>
    onChange((t) => ({
      ...t,
      preferences: { ...t.preferences, transportPreference: mode },
    }));

  const setPaymentPreference = (mode: PaymentPreference) =>
    onChange((t) => ({
      ...t,
      preferences: { ...t.preferences, paymentPreference: mode },
    }));

  const toggleInterest = (tag: InterestTag) =>
    onChange((t) => {
      const cur = new Set(t.preferences.interests ?? []);
      if (cur.has(tag)) cur.delete(tag);
      else cur.add(tag);
      return {
        ...t,
        preferences: { ...t.preferences, interests: Array.from(cur) },
      };
    });

  const setChildrenCount = (count: number) =>
    onChange((t) => {
      const cur = t.preferences.childProfiles ?? [];
      const next: ChildProfile[] = [];
      for (let i = 0; i < count; i++) {
        next.push(cur[i] ?? { id: `child-${Date.now().toString(36)}-${i}`, age: 6 });
      }
      return {
        ...t,
        preferences: {
          ...t.preferences,
          childProfiles: next,
          childrenCount: count,
        },
      };
    });

  const setChildAge = (id: string, age: number) =>
    onChange((t) => ({
      ...t,
      preferences: {
        ...t.preferences,
        childProfiles: (t.preferences.childProfiles ?? []).map((c) =>
          c.id === id ? { ...c, age } : c,
        ),
      },
    }));

  const markAdded = (key: string, label: string) => {
    setAdded((cur) => ({ ...cur, [key]: label }));
    window.setTimeout(() => setAdded((cur) => {
      if (cur[key] !== label) return cur;
      const next = { ...cur };
      delete next[key];
      return next;
    }), 2200);
  };

  const addPlace = (dest: { id: string }, place: PlaceSuggestion) => {
    if (planPlaceNames.has(place.name.toLowerCase().trim())) {
      markAdded(`${dest.id}:${place.id}`, '✓ Zaten planda');
      return;
    }
    const dests = (trip.preferences.destinations ?? []).slice().sort((a, b) => a.order - b.order);
    const destDayNumbers = trip.days
      .filter((day) => getDestinationForDate(dests, day.date)?.id === dest.id)
      .map((d) => d.dayNumber);
    const chosenDay =
      pickBestDayForDestination(trip.days, destDayNumbers) ?? trip.days[0]?.dayNumber ?? 1;
    onChange((t) => ({
      ...t,
      days: addPlaceToDay(t.days, chosenDay, {
        name: place.name,
        emoji: place.emoji,
        steps: place.typicalSteps,
        city: place.city,
      }),
    }));
    if (chosenDay > 0) {
      markAdded(`${dest.id}:${place.id}`, `✓ Gün ${chosenDay}'e eklendi`);
    }
  };

  const suggestKidRoute = (dest: { id: string; countryCode: string }) => {
    const profile = getDestinationProfile(dest.countryCode);
    if (!profile) return;
    const kidPlaces = profile.popularPlaces.filter(isKidFriendly);
    const countryDays = trip.days.filter(
      (d) => getDestinationForDate(destinations, d.date)?.id === dest.id,
    );
    if (!kidPlaces.length || !countryDays.length) return;
    onChange((t) => {
      let days = t.days;
      kidPlaces.forEach((p, i) => {
        const dn = countryDays[i % countryDays.length]?.dayNumber;
        if (dn) days = addPlaceToDay(days, dn, { name: p.name, emoji: p.emoji, steps: p.typicalSteps });
      });
      return { ...t, days };
    });
    markAdded(`kidroute:${dest.id}`, `✓ ${kidPlaces.length} yer ${countryDays.length} güne dağıtıldı`);
  };

  if (!destinations.length) {
    return (
      <>
        <h2 className="page-headline">Keşfet</h2>
        <p className="page-sub">Önce Rota adımında varış havaalanlarını seçin.</p>
      </>
    );
  }

  return (
    <div className="explore-wide">
      <h2 className="page-headline">Keşfet</h2>
      <p className="page-sub">
        Uçuş güzergahınıza göre popüler yerler, önerilen yemekler ve varışta yapılacaklar. Beğendiğinizi
        tek dokunuşla plana ekleyin.
      </p>

      <section className="prefs-panel">
        <div className="prefs-block">
          <div className="prefs-block-title">🚶 Günlük yürüyüş hedefi</div>
          <div className="chip-group" role="radiogroup">
            {WALKING_OPTIONS.map((opt) => (
              <button
                type="button"
                key={opt.id}
                role="radio"
                aria-checked={walkingTarget === opt.id}
                className={`chip${walkingTarget === opt.id ? ' chip-active' : ''}`}
                onClick={() => setWalkingTarget(opt.id)}
              >
                <strong>{opt.label}</strong>
                <span>{opt.range}</span>
              </button>
            ))}
          </div>
        </div>

        <div className="prefs-block">
          <div className="prefs-block-title">🚇 Ulaşım tercihi</div>
          <div className="chip-group" role="radiogroup">
            {TRANSPORT_OPTIONS.map((opt) => (
              <button
                type="button"
                key={opt.id}
                role="radio"
                aria-checked={transportPreference === opt.id}
                className={`chip${transportPreference === opt.id ? ' chip-active' : ''}`}
                onClick={() => setTransportPreference(opt.id)}
              >
                <span>{opt.emoji}</span> {opt.label}
              </button>
            ))}
          </div>
        </div>

        <div className="prefs-block">
          <div className="prefs-block-title">💴 Ödeme yöntemi</div>
          <div className="chip-group" role="radiogroup">
            {PAYMENT_OPTIONS.map((opt) => (
              <button
                type="button"
                key={opt.id}
                role="radio"
                aria-checked={paymentPreference === opt.id}
                className={`chip${paymentPreference === opt.id ? ' chip-active' : ''}`}
                onClick={() => setPaymentPreference(opt.id)}
              >
                <span>{opt.emoji}</span> {opt.label}
              </button>
            ))}
          </div>
        </div>

        <div className="prefs-block">
          <div className="prefs-block-title">👶 Çocuk profili</div>
          <div className="prefs-row">
            <label className="prefs-row-label">Kaç çocuk?</label>
            <select
              value={childrenCount}
              onChange={(e) => setChildrenCount(Number(e.target.value))}
            >
              {[0, 1, 2, 3, 4].map((n) => (
                <option key={n} value={n}>
                  {n === 0 ? 'Çocuk yok' : `${n} çocuk`}
                </option>
              ))}
            </select>
          </div>
          {childProfiles.length > 0 && (
            <div className="prefs-row prefs-row-ages">
              <label className="prefs-row-label">Yaşları</label>
              <div className="child-ages">
                {childProfiles.map((c, i) => (
                  <label key={c.id} className="child-age-input">
                    <span>#{i + 1}</span>
                    <input
                      type="number"
                      min={0}
                      max={18}
                      value={c.age}
                      onChange={(e) => setChildAge(c.id, Number(e.target.value))}
                    />
                  </label>
                ))}
              </div>
            </div>
          )}
          {kidsMode && (
            <p className="explore-kids-note">
              {childrenCount} çocuk seçili — çocuk dostu yerler öne çıkarılıyor, molalar artırılıyor.
            </p>
          )}
        </div>

        <div className="prefs-block">
          <div className="prefs-block-title">🎯 İlgi alanların</div>
          <p className="prefs-hint">Birden fazla seç. Plan bunlara göre yönlendirilir.</p>
          <div className="chip-group">
            {INTEREST_OPTIONS.map((opt) => (
              <button
                type="button"
                key={opt.id}
                aria-pressed={interests.includes(opt.id)}
                className={`chip${interests.includes(opt.id) ? ' chip-active' : ''}`}
                onClick={() => toggleInterest(opt.id)}
              >
                <span>{opt.emoji}</span> {opt.label}
              </button>
            ))}
          </div>
        </div>
      </section>

      {destinations.map((dest) => {
        const profile = getDestinationProfile(dest.countryCode);
        const guide = getGuideDefaultsForCountry(dest.countryCode);
        const foods = recommendedFoods(dest.countryCode);
        const arrivalTips = guide?.practicalTips ?? [];
        let places = profile?.popularPlaces ?? [];
        if (kidsMode) {
          places = [...places].sort(
            (a, b) => Number(isKidFriendly(b)) - Number(isKidFriendly(a)),
          );
        }

        return (
          <section key={dest.id} className="explore-country">
            <div className="explore-country-head">
              <h3>
                {profile?.flag} {dest.countryName || dest.city}
              </h3>
              {dest.city && <span className="explore-city">{dest.city}</span>}
            </div>

            {arrivalTips.length > 0 && (
              <div className="explore-block">
                <div className="explore-block-title">🛬 İlk gün yapılacaklar</div>
                <div className="explore-tips">
                  {arrivalTips.map((tip) => (
                    <div key={tip.id} className="explore-tip">
                      <span className="explore-tip-icon">{tip.icon}</span>
                      <div>
                        <strong>{tip.title}</strong>
                        <p>{tip.body}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {places.length > 0 && (
              <div className="explore-block">
                <div className="explore-block-title">
                  ⭐ Popüler gezilecek yerler
                  {kidsMode && (
                    <button
                      type="button"
                      className="btn btn-secondary btn-sm explore-kidroute-btn"
                      onClick={() => suggestKidRoute(dest)}
                    >
                      {added[`kidroute:${dest.id}`] ?? '🧸 Çocuk dostu rota öner'}
                    </button>
                  )}
                </div>
                <div className="explore-places">
                  {places.map((place) => {
                    const rating = placeRating(place);
                    const kid = isKidFriendly(place);
                    const key = `${dest.id}:${place.id}`;
                    const inPlan = planPlaceNames.has(place.name.toLowerCase().trim());
                    return (
                      <article
                        key={place.id}
                        className={`explore-place${kidsMode && kid ? ' kid' : ''}${inPlan ? ' added' : ''}`}
                      >
                        <div className="explore-place-top">
                          <span className="explore-place-emoji">{place.emoji}</span>
                          <span className="explore-rating" title={`${rating} / 5`}>
                            {ratingStars(rating)} <em>{rating.toFixed(1)}</em>
                          </span>
                        </div>
                        <div className="explore-place-name">{place.name}</div>
                        <div className="explore-place-city">{place.city}</div>
                        {kid && <span className="explore-kid-badge">👶 Çocuk dostu</span>}
                        <div className="explore-place-actions">
                          <a
                            className="explore-link"
                            href={googleReviewsUrl(`${place.name} ${place.city}`)}
                            target="_blank"
                            rel="noreferrer"
                          >
                            Google yorumları →
                          </a>
                          <button
                            type="button"
                            className={`btn btn-sm ${inPlan ? 'btn-secondary' : 'btn-primary'}`}
                            onClick={() => addPlace(dest, place)}
                            disabled={inPlan}
                          >
                            {added[key] ?? (inPlan ? '✓ Planda' : '+ Plana ekle')}
                          </button>
                        </div>
                      </article>
                    );
                  })}
                </div>
              </div>
            )}

            {foods.length > 0 && (
              <div className="explore-block">
                <div className="explore-block-title">🍽️ Önerilen yemekler</div>
                <div className="explore-foods">
                  {foods.map((food) => (
                    <a
                      key={food.label}
                      className="explore-food-chip"
                      href={googleReviewsUrl(`${food.label} ${dest.city || dest.countryName}`)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {food.emoji && <span>{food.emoji}</span>}
                      {food.label}
                    </a>
                  ))}
                </div>
              </div>
            )}
          </section>
        );
      })}
    </div>
  );
}
