import { useMemo, useState } from 'react';
import { getPublishedGuide } from '@japan-trip/shared';
import type { HotelStay, Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
}

export function TripGuideSections({ trip }: Props) {
  const guide = useMemo(() => getPublishedGuide(trip), [trip]);
  const [checked, setChecked] = useState<Record<string, boolean>>({});

  const hasGuide =
    guide.practicalTips.length > 0 ||
    guide.shopping.length > 0 ||
    guide.foodSpots.length > 0 ||
    guide.compass.length > 0;
  const hasHotels = trip.hotels.some((h) => h.address?.trim() || h.name);

  if (!hasGuide && !hasHotels) return null;

  return (
    <div className="guide-footer">
      {trip.hotels.length > 0 && (
        <section className="guide-block" id="hotels">
          <h2>🏨 Konaklama adresleri</h2>
          <ul className="hotel-address-list">
            {trip.hotels.map((h) => (
              <HotelAddressCard key={h.id} hotel={h} />
            ))}
          </ul>
        </section>
      )}

      {guide.practicalTips.length > 0 && (
        <section className="guide-block" id="practical">
          <h2>Varış & pratik bilgiler</h2>
          <div className="tip-grid">
            {guide.practicalTips.map((tip) => (
              <article key={tip.id} className="tip-card">
                {tip.source === 'suggestion' && <span className="tag-suggestion">Öneri</span>}
                <h3>
                  {tip.icon ? `${tip.icon} ` : ''}
                  {tip.title}
                </h3>
                <p>{tip.body}</p>
              </article>
            ))}
          </div>
        </section>
      )}

      {guide.shopping.length > 0 && (
        <section className="guide-block" id="shopping">
          <h2>🛍️ Alışveriş listesi</h2>
          <ul className="shopping-list">
            {guide.shopping.map((item) => (
              <li key={item.id}>
                <label>
                  <input
                    type="checkbox"
                    checked={!!checked[item.id]}
                    onChange={() =>
                      setChecked((c) => ({ ...c, [item.id]: !c[item.id] }))
                    }
                  />
                  <span>
                    <strong>{item.category}</strong> — {item.text}
                    {item.source === 'suggestion' && (
                      <span className="tag-suggestion inline">Öneri</span>
                    )}
                  </span>
                </label>
              </li>
            ))}
          </ul>
        </section>
      )}

      {guide.foodSpots.length > 0 && (
        <section className="guide-block" id="food-guide">
          <h2>🍜 Yemek rehberi</h2>
          <div className="food-grid">
            {guide.foodSpots.map((spot) => (
              <article key={spot.id} className="food-card">
                {spot.source === 'suggestion' && <span className="tag-suggestion">Öneri</span>}
                <h3>{spot.name}</h3>
                {spot.area && <p className="food-meta">{spot.area}</p>}
                {spot.note && <p>{spot.note}</p>}
                {spot.mapsUrl && (
                  <a href={spot.mapsUrl} target="_blank" rel="noreferrer">
                    Haritada aç
                  </a>
                )}
              </article>
            ))}
          </div>
        </section>
      )}

      {guide.compass.length > 0 && (
        <section className="guide-block" id="pusula">
          <h2>🧭 Pusula</h2>
          {guide.compass.map((block) => (
            <div key={block.id} className="compass-card">
              {block.source === 'suggestion' && <span className="tag-suggestion">Öneri</span>}
              <h3>{block.title}</h3>
              <p>{block.content}</p>
            </div>
          ))}
        </section>
      )}
    </div>
  );
}

function HotelAddressCard({ hotel }: { hotel: HotelStay }) {
  const local = hotel.addressLocal ?? hotel.addressJa;
  return (
    <li className="hotel-address-card">
      <strong>
        {hotel.name} — {hotel.city}
      </strong>
      <p>{hotel.address || 'Adres girilmemiş'}</p>
      {local && <p className="hotel-local">{local}</p>}
      {hotel.phone && <p>📞 {hotel.phone}</p>}
      {hotel.mapsUrl && (
        <a href={hotel.mapsUrl} target="_blank" rel="noreferrer">
          Haritada aç
        </a>
      )}
    </li>
  );
}
