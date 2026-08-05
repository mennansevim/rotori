"""Mevcut videolarına bakıp otomatik "Reels Fikri" önerileri üretir.

Kullanıcı prompt yazmasın: elde ne varsa ona uygun 8-12 hazır fikir sun.
Tıklandığında UI formunu doldurur, kullanıcı edit edip "Reels Üret"e basar.

Eşleme algoritması:
  1. Şablonun `match` listesindeki anahtarları metadata satırlarında ara
     (dosya_adi + mekan_etiketi + kategori + sehir + sahne_ozeti +
      sahne_ogeleri + sahne_mekan_tahmini).
  2. Match eden klip sayısına göre sırala; en az 1 klip yakalayan şablonları döndür.

Şablonlar burada sabit — LLM ile üretmiyoruz çünkü:
  - Hızlı (her sayfa yüklemesinde saniyeler içinde)
  - Deterministik (aynı arşivde her seferinde aynı fikirler)
  - Editörden geçmiş, tutarlı Türkçe
Kullanıcı fikri değiştirmek isterse form textarea'sında zaten düzeltebiliyor.
"""
from __future__ import annotations

import csv
import unicodedata
from pathlib import Path
from typing import Any
from urllib.parse import quote

from src.config import Config


def _norm(text: str) -> str:
    text = (text or "").lower()
    for a, b in {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "İ": "i"}.items():
        text = text.replace(a, b)
    text = "".join(c for c in unicodedata.normalize("NFKD", text)
                   if not unicodedata.combining(c))
    return text


# --- Şablon tanımları -------------------------------------------------------
# Her şablon: id, ikon, başlık, prompt, hook, süre modu, match anahtarları.
# `match` içindeki kelimelerden en az biri metadata'da geçen satır varsa
# şablon aktif olur.
_TEMPLATES: list[dict[str, Any]] = [
    # === Nara ===
    {
        "id": "nara_todaiji",
        "icon": "🏯",
        "baslik": "Japonya'nın en büyük Budist heykeli",
        "prompt": "Nara Todai-ji'deki dev Buda heykelini ve tapınağın büyüklüğünü anlatan bir Reels",
        "hook": "Bunu görmeden Japonya'dan dönme",
        "sure_modu": "orta",
        "match": ["todai", "todaiji", "buddha", "buda heykeli", "nara todai", "temple interior"],
    },
    {
        "id": "nara_geyik",
        "icon": "🦌",
        "baslik": "Nara'daki geyikler nasıl?",
        "prompt": "Nara Parkı'nda geyiklerle karşılaşma — beslerken bilinmesi gerekenler",
        "hook": "Nara geyiklerine bunu bilmeden yaklaşma",
        "sure_modu": "kisa",
        "match": ["nara", "geyik", "deer"],
    },
    {
        "id": "nara_gun",
        "icon": "☀️",
        "baslik": "Nara'da 1 gün nasıl geçti",
        "prompt": "Nara'da günübirlik gezi — Todai-ji, geyikler, park",
        "hook": "Nara için 1 gün yetiyor mu?",
        "sure_modu": "uzun",
        "match": ["nara", "geyik", "deer", "todai"],
    },

    # === Kyoto ===
    {
        "id": "fushimi_torii",
        "icon": "⛩",
        "baslik": "10.000 kırmızı torii kapısı",
        "prompt": "Kyoto Fushimi Inari'nin kırmızı torii tünellerinde yürüyüş",
        "hook": "Fushimi Inari'nin gerçek sırrı",
        "sure_modu": "orta",
        "match": ["torii", "fushimi", "inari"],
    },
    {
        "id": "kyoto_tapinak",
        "icon": "🏮",
        "baslik": "Kyoto'nun eski ruhu",
        "prompt": "Kyoto'nun tarihi sokakları ve tapınakları — geleneksel Japon estetiği",
        "hook": "Kyoto sokakları anlatılmaz, yaşanır",
        "sure_modu": "orta",
        "match": ["kyoto", "temple", "shrine", "tapinak", "gion", "kinkaku", "kiyomizu"],
    },

    # === Osaka ===
    {
        "id": "dotonbori",
        "icon": "🍜",
        "baslik": "Dotonbori gece hayatı",
        "prompt": "Osaka Dotonbori'nin neon ışıkları, Glico koşan adam ve sokak yemekleri",
        "hook": "Bu neonları görmeden Osaka'dan gitme",
        "sure_modu": "kisa",
        "match": ["dotonbori", "glico", "neon"],
    },
    {
        "id": "osaka_castle",
        "icon": "🏰",
        "baslik": "Osaka Kalesi ve sırları",
        "prompt": "Osaka Kalesi'nin tarihi ve etrafındaki park",
        "hook": "Osaka Kalesi hakkında bilmediklerin",
        "sure_modu": "orta",
        "match": ["osaka castle", "osaka kale"],
    },

    # === Tokyo ===
    {
        "id": "tokyo_tower",
        "icon": "🗼",
        "baslik": "Tokyo Tower vs Skytree",
        "prompt": "Tokyo Tower gece manzarası — Eiffel benzeri kırmızı kule",
        "hook": "Turistlerin %90'ı yanlış kuleye çıkıyor",
        "sure_modu": "kisa",
        "match": ["tokyo tower", "space needle", "eiffel", "tower lights"],
    },
    {
        "id": "shibuya_crossing",
        "icon": "🚦",
        "baslik": "Dünyanın en kalabalık kavşağı",
        "prompt": "Shibuya Crossing'i tepeden ve karşıdan çekilmiş görüntülerle anlat",
        "hook": "Bunu ilk gördüğünde dilin tutulur",
        "sure_modu": "kisa",
        "match": ["shibuya", "crossing", "hachiko"],
    },
    {
        "id": "asakusa_senso",
        "icon": "🎎",
        "baslik": "Tokyo'nun en eski tapınağı",
        "prompt": "Asakusa Senso-ji'nin Kaminarimon kapısı ve Nakamise sokağı",
        "hook": "1400 yıllık tapınak, kalbinde bir sokak",
        "sure_modu": "orta",
        "match": ["asakusa", "senso", "kaminarimon", "nakamise"],
    },
    {
        "id": "meiji_jingu",
        "icon": "🌲",
        "baslik": "Tokyo'nun ortasındaki orman",
        "prompt": "Meiji Jingu — Shibuya'nın hemen yanındaki sessiz orman tapınağı",
        "hook": "Metrodan çıkınca kendini ormanda bulacaksın",
        "sure_modu": "orta",
        "match": ["meiji", "jingu", "shrine forest"],
    },

    # === Tema parkları ===
    {
        "id": "disney_tokyo",
        "icon": "🏰",
        "baslik": "Tokyo Disneyland — tam gün özet",
        "prompt": "Tokyo Disneyland'de sabahtan gece havai fişeklerine kadar bir gün",
        "hook": "Disneyland'de bu ipucunu bilmeyen sıraya yandı",
        "sure_modu": "uzun",
        "match": ["disneyland", "disney", "cinderella", "space mountain",
                  "carousel", "ferris wheel", "castle"],
    },
    {
        "id": "usj_nintendo",
        "icon": "🍄",
        "baslik": "Nintendo World Osaka",
        "prompt": "Universal Studios Japan'daki Super Nintendo World'de Mario Kart deneyimi",
        "hook": "Mario Kart Türkiye'de böyle değil",
        "sure_modu": "orta",
        "match": ["nintendo", "mario", "super mario", "yoshi"],
    },
    {
        "id": "usj_harry",
        "icon": "⚡",
        "baslik": "USJ Harry Potter köyü",
        "prompt": "Osaka Universal Studios'un Harry Potter dünyası, Butterbeer",
        "hook": "Butterbeer'in tadı neye benziyor?",
        "sure_modu": "kisa",
        "match": ["harry potter", "hogwarts", "butterbeer"],
    },
    {
        "id": "usj_genel",
        "icon": "🎢",
        "baslik": "Universal Studios Japan bir günde",
        "prompt": "Osaka Universal Studios'ta bir tam gün — hangi bölge önce",
        "hook": "Turistlerin çoğunun kaçırdığı sıra",
        "sure_modu": "uzun",
        "match": ["universal", "usj", "theme park", "roller coaster"],
    },

    # === Kültür / lojistik ===
    {
        "id": "konbini",
        "icon": "🏪",
        "baslik": "Konbini'de bulacağın 5 harika şey",
        "prompt": "7-Eleven, FamilyMart, Lawson — Türklerin bilmediği ürünler",
        "hook": "Japon konbinileri Türkiye'dekiyle karışmasın",
        "sure_modu": "orta",
        "match": ["konbini", "7 eleven", "7-eleven", "seven eleven",
                  "familymart", "lawson"],
    },
    {
        "id": "shinkansen",
        "icon": "🚄",
        "baslik": "Shinkansen Tokyo → Osaka",
        "prompt": "NOZOMI Shinkansen ile geçiş — Fuji Dağı manzarası hangi taraftan",
        "hook": "Fuji Dağı'nı görmek için hangi koltuk?",
        "sure_modu": "kisa",
        "match": ["shinkansen", "fuji", "nozomi", "hikari", "bullet train"],
    },
    {
        "id": "ryokan_otel",
        "icon": "🛏",
        "baslik": "Japon otel odası ilk izlenim",
        "prompt": "Japon otel/ryokan odasında ilk gece — küçük ama akıllı tasarım",
        "hook": "Bu kadar küçük oda nasıl bu kadar iyi?",
        "sure_modu": "kisa",
        "match": ["hotel room", "hotel", "otel", "ryokan", "tatami",
                  "hotel hallway", "bed door", "bed carpet"],
    },
    {
        "id": "onsen",
        "icon": "♨️",
        "baslik": "Onsen — Türklerin bilmediği kurallar",
        "prompt": "Onsen (Japon kaplıcası) etiketi — bilinmesi gereken kurallar",
        "hook": "Onsen'e girmeden önce bunları oku",
        "sure_modu": "kisa",
        "match": ["onsen", "kaplica", "hot spring"],
    },
    {
        "id": "japan_havadan",
        "icon": "🚁",
        "baslik": "Japonya'nın kuşbakışı hali",
        "prompt": "Drone kamerayla Japonya şehirleri havadan — Tokyo/Osaka silüetleri",
        "hook": "Yukarıdan görmedikçe Tokyo'nun büyüklüğü anlaşılmaz",
        "sure_modu": "orta",
        "match": ["aerial", "havadan", "drone", "kuşbakışı", "skyscrapers",
                  "city lights", "cityscape"],
    },
    {
        "id": "japon_yemek",
        "icon": "🍣",
        "baslik": "Japon yemek deneyimi",
        "prompt": "Sokak yemekleri — takoyaki, okonomiyaki, ramen, sushi",
        "hook": "Bunları Türkiye'deki gibi düşünme",
        "sure_modu": "orta",
        "match": ["takoyaki", "okonomiyaki", "sushi", "ramen", "yemek",
                  "food market", "kuromon"],
    },
    {
        "id": "toy_store",
        "icon": "🧸",
        "baslik": "Japon oyuncak dükkanında bir çocuk",
        "prompt": "Japonya'nın oyuncak dünyasında çocuk gözünden gezinti",
        "hook": "Türkiye'de bulamayacağın 3 oyuncak",
        "sure_modu": "kisa",
        "match": ["toy store", "oyuncak", "toys", "kiz oyuncak"],
    },
    {
        "id": "golf_sim",
        "icon": "⛳",
        "baslik": "Japonya'nın kapalı golf tesisleri",
        "prompt": "Indoor golf simulator — Tokyo/Osaka'da kapalı alan sporları",
        "hook": "Bu golfü Türkiye'de hiç görmedin",
        "sure_modu": "kisa",
        "match": ["golf", "indoor golf", "golf simulator"],
    },
    {
        "id": "teamlab",
        "icon": "✨",
        "baslik": "teamLab — su içinde ışık",
        "prompt": "Tokyo teamLab Planets — su dolu odalar ve ışık tünelleri",
        "hook": "Bu müze değil, başka bir boyut",
        "sure_modu": "orta",
        "match": ["teamlab", "light installation", "immersive"],
    },
    {
        "id": "gundam_odaiba",
        "icon": "🤖",
        "baslik": "Odaiba Gundam heykeli",
        "prompt": "Odaiba'daki dev Gundam heykeli — gece animasyon showu",
        "hook": "Anime bunu değil, gerçeğini gördün mü?",
        "sure_modu": "kisa",
        "match": ["gundam", "odaiba", "robot statue"],
    },
]


def _first_frame_url(row: dict[str, Any]) -> str | None:
    dosya = row.get("dosya_adi", "")
    if not dosya:
        return None
    stem = Path(dosya).stem
    return f"/media/frames/{quote(stem)}.jpg"


def _score_row(row: dict[str, Any], match_keys: list[str]) -> int:
    hay = _norm(" ".join([
        row.get("dosya_adi", ""),
        row.get("mekan_etiketi", ""),
        row.get("kategori", ""),
        row.get("sehir", ""),
        row.get("sahne_ozeti", ""),
        row.get("sahne_ogeleri", ""),
        row.get("sahne_mekan_tahmini", ""),
    ]))
    return sum(1 for k in match_keys if _norm(k) in hay)


def build_suggestions(cfg: Config, limit: int = 12) -> list[dict[str, Any]]:
    """metadata.csv'de var olan mekan/konulara göre öneri kartları döndür."""
    if not cfg.paths.metadata_csv.exists():
        return []

    with cfg.paths.metadata_csv.open("r", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        return []

    out: list[dict[str, Any]] = []
    for tmpl in _TEMPLATES:
        keys = tmpl["match"]
        matched = [(r, _score_row(r, keys)) for r in rows]
        matched = [(r, s) for r, s in matched if s > 0]
        if not matched:
            continue
        matched.sort(key=lambda x: -x[1])
        best = matched[0][0]

        out.append({
            "id": tmpl["id"],
            "icon": tmpl["icon"],
            "baslik": tmpl["baslik"],
            "prompt": tmpl["prompt"],
            "hook": tmpl["hook"],
            "sure_modu": tmpl["sure_modu"],
            "thumb": _first_frame_url(best),
            "klip_sayisi": len(matched),
            "toplam_puan": sum(s for _, s in matched),
        })

    # sırala: klip sayısı çok olan başa
    out.sort(key=lambda s: (-s["klip_sayisi"], -s["toplam_puan"]))
    return out[:limit]
