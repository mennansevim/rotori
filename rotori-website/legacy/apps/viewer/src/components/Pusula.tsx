import { useState } from 'react';
import type { Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
}

interface PhraseCard {
  jp: string;
  romaji?: string;
  meaning: string;
}

interface PhraseCategory {
  id: string;
  title: string;
  emoji: string;
  phrases: PhraseCard[];
}

const PHRASE_CATEGORIES: PhraseCategory[] = [
  {
    id: 'basic',
    title: 'Temel',
    emoji: '🗣️',
    phrases: [
      { jp: 'すみません', romaji: 'Sumimasen', meaning: 'Affedersiniz / Pardon' },
      { jp: 'ありがとうございます', romaji: 'Arigatou gozaimasu', meaning: 'Çok teşekkürler' },
      { jp: '英語が話せますか？', romaji: 'Eigo ga hanasemasu ka?', meaning: 'İngilizce biliyor musunuz?' },
      { jp: 'いくらですか？', romaji: 'Ikura desu ka?', meaning: 'Kaç para?' },
      { jp: 'お手洗いはどこ？', romaji: 'Otearai wa doko?', meaning: 'Tuvalet nerede?' },
    ],
  },
  {
    id: 'food',
    title: 'Yemekte sor',
    emoji: '🍽️',
    phrases: [
      { jp: 'この料理に豚肉は入っていますか？', meaning: 'Bu yemekte domuz eti var mı?' },
      { jp: 'ラードは使われていますか？', meaning: 'Domuz yağı kullanılıyor mu?' },
      { jp: 'お酒は入っていますか？', meaning: 'Alkol içeriyor mu?' },
      { jp: '鶏肉のメニューはありますか？', meaning: 'Tavuklu seçenek var mı?' },
      { jp: '海鮮は入っていますか？', meaning: 'Deniz ürünü içeriyor mu?' },
      { jp: 'お子様用に辛くないものはありますか？', meaning: 'Çocuk için acısız bir seçenek var mı?' },
      { jp: 'ベジタリアンメニューはありますか？', meaning: 'Vejetaryen menü var mı?' },
    ],
  },
  {
    id: 'directions',
    title: 'Yol sor',
    emoji: '🗺️',
    phrases: [
      { jp: '駅はどこですか？', romaji: 'Eki wa doko desu ka?', meaning: 'İstasyon nerede?' },
      { jp: 'この電車は○○行きですか？', romaji: 'Kono densha wa __ iki desu ka?', meaning: 'Bu tren __ a gidiyor mu?' },
      { jp: '○○まで行ってください', romaji: '__ made itte kudasai', meaning: 'Lütfen __ a kadar' },
      { jp: '地図を見せてもらえますか？', meaning: 'Haritayı gösterir misiniz?' },
    ],
  },
  {
    id: 'emergency',
    title: 'Acil',
    emoji: '🚨',
    phrases: [
      { jp: '助けて！', romaji: 'Tasukete!', meaning: 'İmdat!' },
      { jp: '救急車を呼んでください', romaji: 'Kyuukyuusha o yonde kudasai', meaning: 'Ambulans çağırın' },
      { jp: '警察を呼んでください', romaji: 'Keisatsu o yonde kudasai', meaning: 'Polis çağırın' },
      { jp: '気分が悪いです', romaji: 'Kibun ga warui desu', meaning: 'Kendimi iyi hissetmiyorum' },
      { jp: 'パスポートをなくしました', meaning: 'Pasaportumu kaybettim' },
    ],
  },
];

const EMERGENCY_NUMBERS = [
  { num: '110', label: 'Polis' },
  { num: '119', label: 'Ambulans / İtfaiye' },
  { num: '03-3501-0110', label: 'Yabancı danışma (Tokyo)' },
  { num: '+81-3-3470-5131', label: 'TR Tokyo Büyükelçiliği' },
];

export function Pusula({ trip }: Props) {
  const [copied, setCopied] = useState<string | null>(null);
  const [activeCat, setActiveCat] = useState<string>('basic');

  const hotels = trip.hotels ?? [];
  const primaryHotel = hotels[0];

  const copyPhrase = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(text);
      window.setTimeout(() => setCopied((c) => (c === text ? null : c)), 1200);
    } catch {
      /* clipboard yok */
    }
  };

  const activeCategory =
    PHRASE_CATEGORIES.find((c) => c.id === activeCat) ?? PHRASE_CATEGORIES[0];

  return (
    <section className="section" id="pusula">
      <div className="section-header">
        <div
          className="section-icon"
          style={{ background: 'linear-gradient(135deg, #64b5f6, #5856d6)' }}
        >
          🧭
        </div>
        <div>
          <h2 className="section-title">Pusula</h2>
          <div className="section-subtitle">Cebinde taşı — acil, dil, kültür</div>
        </div>
      </div>

      <div className="info-grid">
        <div className="info-card">
          <div className="info-card-head">
            <div className="info-card-icon danger">🚨</div>
            <div>
              <div className="info-card-title">Acil Numaralar</div>
              <div className="info-card-sub">Japonya</div>
            </div>
          </div>
          <div className="info-list">
            {EMERGENCY_NUMBERS.map((e) => (
              <div key={e.num}>
                <strong>{e.num}</strong> — {e.label}
              </div>
            ))}
          </div>
        </div>

        {primaryHotel && (
          <div className="info-card">
            <div className="info-card-head">
              <div className="info-card-icon sky">🏨</div>
              <div>
                <div className="info-card-title">Otel adresi</div>
                <div className="info-card-sub">Taksiye göster</div>
              </div>
            </div>
            <div className="info-list">
              <strong>{primaryHotel.name}</strong>
              <br />
              {primaryHotel.address}
              {primaryHotel.addressLocal && (
                <>
                  <br />
                  <span style={{ fontSize: 16, fontWeight: 600 }}>
                    {primaryHotel.addressLocal}
                  </span>
                </>
              )}
              {primaryHotel.phone && (
                <>
                  <br />
                  📞 {primaryHotel.phone}
                </>
              )}
              {primaryHotel.mapsUrl && (
                <>
                  <br />
                  <a href={primaryHotel.mapsUrl} target="_blank" rel="noopener noreferrer">
                    📍 Google Maps
                  </a>
                </>
              )}
            </div>
          </div>
        )}

        <div className="info-card info-card-phrases">
          <div className="info-card-head">
            <div className="info-card-icon gold">🗣️</div>
            <div>
              <div className="info-card-title">Japonca fraz kartları</div>
              <div className="info-card-sub">Cümleye tıkla, kopyalansın</div>
            </div>
          </div>

          <div className="phrase-cat-tabs">
            {PHRASE_CATEGORIES.map((cat) => (
              <button
                key={cat.id}
                type="button"
                className={`phrase-cat-tab${activeCat === cat.id ? ' active' : ''}`}
                onClick={() => setActiveCat(cat.id)}
              >
                <span>{cat.emoji}</span> {cat.title}
              </button>
            ))}
          </div>

          <div className="phrase-cat-content">
            {activeCategory.phrases.map((p, i) => (
              <button
                key={i}
                type="button"
                className={`phrase-chip${copied === p.jp ? ' phrase-chip-copied' : ''}`}
                onClick={() => copyPhrase(p.jp)}
                title="Kopyala"
              >
                <span>
                  <strong>{p.jp}</strong>
                  {p.romaji && <small> · {p.romaji}</small>}
                  <br />
                  <small>{p.meaning}</small>
                </span>
              </button>
            ))}
          </div>
        </div>

        <div className="info-card">
          <div className="info-card-head">
            <div className="info-card-icon sunset">💴</div>
            <div>
              <div className="info-card-title">Para & Döviz</div>
              <div className="info-card-sub">JPY</div>
            </div>
          </div>
          <div className="info-list">
            1.000 ¥ ≈ kur değişir · 7-Eleven ATM yabancı kart kabul · Suica/Pasmo IC kart
            metro + konbini için pratik.
          </div>
        </div>

        <div className="info-card">
          <div className="info-card-head">
            <div className="info-card-icon sakura">🎌</div>
            <div>
              <div className="info-card-title">Kültür kuralları</div>
              <div className="info-card-sub">Yerel etiket</div>
            </div>
          </div>
          <div className="info-list">
            <strong>Metro:</strong> Sessiz ol, telefonda konuşma; önce inenlere yol ver.
            <br />
            <strong>Bahşiş:</strong> Verilmez — hakaret sayılabilir.
            <br />
            <strong>Tapınak:</strong> Bazı yerlerde ayakkabı çıkarılır; çekim yasaklarına dikkat.
            <br />
            <strong>Çöp:</strong> Sokakta çöp kutusu yok; yanında taşı, otele götür.
          </div>
        </div>
      </div>
    </section>
  );
}
