import { useMemo, useState } from 'react';
import type { Trip, UserStats } from '@japan-trip/shared';

interface Props {
  trip: Trip;
  community: UserStats['community'] | undefined;
  onJoin: (community: { month: string; cityRoom: string }) => void;
}

const MONTHS = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

const ROOM_CITIES = ['Tokyo', 'Osaka', 'Kyoto', 'Nara', 'Kobe', 'Hiroşima', 'Fukuoka'];

function monthFromIso(iso: string | undefined): string | null {
  if (!iso) return null;
  const m = iso.match(/^\d{4}-(\d{2})/);
  if (!m) return null;
  const idx = Number(m[1]) - 1;
  return MONTHS[idx] ?? null;
}

export function CommunityBeta({ trip, community, onJoin }: Props) {
  const initialMonth = useMemo(
    () =>
      community?.month ||
      monthFromIso(trip.preferences.travelDates.start) ||
      MONTHS[new Date().getMonth()],
    [community, trip],
  );
  const initialCity = useMemo(() => {
    if (community?.cityRoom) return community.cityRoom;
    const dests = trip.preferences.destinations ?? [];
    for (const cand of ROOM_CITIES) {
      if (dests.some((d) => (d.city || '').toLowerCase().includes(cand.toLowerCase()))) {
        return cand;
      }
    }
    return ROOM_CITIES[0];
  }, [community, trip]);

  const [month, setMonth] = useState(initialMonth);
  const [cityRoom, setCityRoom] = useState(initialCity);
  const joined = !!community?.cityRoom;

  return (
    <section className="community-beta" id="topluluk">
      <div className="section-header">
        <div
          className="section-icon"
          style={{ background: 'linear-gradient(135deg, #38bdf8, #6366f1)' }}
        >
          👥
        </div>
        <div>
          <h2 className="section-title">
            Beta Topluluk{' '}
            <span className="community-beta-badge">BETA</span>
          </h2>
          <div className="section-subtitle">
            Aynı dönemde Japonya'da olacak Türklerle anonim sohbet
          </div>
        </div>
      </div>

      <div className="community-beta-body">
        <p className="community-beta-intro">
          Topluluk sohbeti yakında açılıyor. Şimdiden ay ve şehir tercihini kaydedersen, oda
          açıldığında sana bildirim gönderilir. Konum ve kişisel bilgiler asla paylaşılmaz —
          sadece kullanıcı adın görünür.
        </p>

        <div className="community-beta-form">
          <div className="field">
            <label>Seyahat ayı</label>
            <select value={month} onChange={(e) => setMonth(e.target.value)}>
              {MONTHS.map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </select>
          </div>

          <div className="field">
            <label>Şehir odası</label>
            <select value={cityRoom} onChange={(e) => setCityRoom(e.target.value)}>
              {ROOM_CITIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </div>

          <button
            type="button"
            className="btn-primary"
            onClick={() => onJoin({ month, cityRoom })}
          >
            {joined ? '✓ Tercih güncellendi' : `🎯 ${cityRoom} ${month} odası tercihim`}
          </button>
        </div>

        <div className="community-beta-rules">
          <strong>Topluluk kuralları (taslak)</strong>
          <ul>
            <li>Gerçek isim zorunlu değildir.</li>
            <li>Konum paylaşımı varsayılan kapalıdır.</li>
            <li>Plan paylaşımı isteğe bağlı — sadece sen seçtiğin günleri görünür kıl.</li>
            <li>Taksi paylaşımı + ortak rota önerisi için ayrı odalar açılacak.</li>
            <li>Spam / reklam / kötü amaçlı mesajlar moderasyon ile silinir.</li>
          </ul>
        </div>

        {joined && (
          <div className="community-beta-status">
            🎉 Tercihin kaydedildi: <strong>{community?.cityRoom}</strong> ·{' '}
            <strong>{community?.month}</strong>. Oda açıldığında haberdar edileceksin.
          </div>
        )}
      </div>
    </section>
  );
}
