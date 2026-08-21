"""Manuel story üretimi için üst seviye içerik kategorileri.

Bu modül, dashboard ile üretim hattının aynı kategori sözleşmesini kullanmasını
sağlar. Editöryel ``kategori`` alanı daha ayrıntılı bir AI etiketi olmaya devam
eder; buradaki kategori ise üretim kaynağını seçen kullanıcı kararını temsil
eder.
"""
from __future__ import annotations

from typing import Any


CATEGORY_ORDER = (
    "guncel_haberler",
    "seyahat_hazirligi",
    "animeler",
    "teknoloji",
)

CATEGORY_SPECS: dict[str, dict[str, Any]] = {
    "guncel_haberler": {
        "slug": "guncel_haberler",
        "label": "Güncel Haberler",
        "description": "RSS akışlarını tara, turist için değerli olan haberi AI ile seç.",
        "mode": "rss",
    },
    "seyahat_hazirligi": {
        "slug": "seyahat_hazirligi",
        "label": "Japonya Yolculuğu",
        "description": "Uçuş, hazırlık, ulaşım ve Japonya'ya gitme sürecine odaklan.",
        "mode": "topic",
        "topic_hints": (
            "pass", "suica", "ic kart", "otobüs", "havalimanı", "metro",
            "shinkansen", "bavul", "feribot", "bisiklet", "wifi", "esim",
            "uçuş", "kabin", "yanına", "jet lag", "konaklama", "otel",
            "onsen girişi",
        ),
        "topic_seeds": (
            ("Japonya'ya İlk Kez Giderken Yanına Alınacaklar", "japan travel packing suitcase"),
            ("Japonya Uçuşunda Kabin Bagajı Düzeni", "airplane cabin luggage travel"),
            ("Japonya'ya Varınca İlk Gün Nasıl Planlanır", "tokyo airport arrival travel"),
            ("Japonya'da İnternet için eSIM mi Pocket Wi-Fi mı", "traveler smartphone japan street"),
            ("Uçuş Sonrası Jet Lag ile İlk Gün", "airplane arrival city travel"),
        ),
    },
    "animeler": {
        "slug": "animeler",
        "label": "Animeler",
        "description": "Anime kültürü, mekanları, etkinlikleri ve Japonya deneyimini üret.",
        "mode": "topic",
        "topic_hints": ("anime", "manga", "akihabara"),
        "topic_seeds": (
            ("Anime Severler için Akihabara Gezisi", "akihabara tokyo neon street"),
            ("Japonya'da Anime Ürünleri Alışverişi", "anime figure shopping tokyo"),
            ("Anime Sergisi ve Etkinliği Ziyaretinde Bilinmesi Gerekenler", "anime exhibition gallery japan"),
            ("Japonya'da Manga ve Anime Mağazalarını Gezerken", "manga bookstore japan"),
        ),
    },
    "teknoloji": {
        "slug": "teknoloji",
        "label": "Teknolojik Ürünler",
        "description": "Japonya'da teknoloji alışverişi, ürünler ve gezginin işine yarayan cihazlar.",
        "mode": "topic",
        "topic_hints": ("teknoloji", "kamera", "elektronik", "wifi", "esim"),
        "topic_seeds": (
            ("Japonya'da Kamera ve Lens Alışverişi", "camera lens shopping tokyo"),
            ("Japonya'da İkinci El Teknoloji Mağazaları", "used electronics shopping japan"),
            ("Japonya'da Oyun Konsolu ve Aksesuar Alışverişi", "gaming console electronics store japan"),
            ("Japonya'da Elektronik Alışverişinde Tax-Free", "electronics shopping district japan"),
            ("Japonya'da Seyahat için İşe Yarayan Teknolojik Ürünler", "travel gadgets smartphone japan"),
        ),
    },
}

_ALIASES = {
    "guncel": "guncel_haberler",
    "haber": "guncel_haberler",
    "news": "guncel_haberler",
    "current_news": "guncel_haberler",
    "seyahat": "seyahat_hazirligi",
    "yolculuk": "seyahat_hazirligi",
    "travel": "seyahat_hazirligi",
    "travel_prep": "seyahat_hazirligi",
    "anime": "animeler",
    "technology": "teknoloji",
    "tech": "teknoloji",
}


def normalize_category(value: str | None) -> str:
    """Kullanıcı/API değerini bilinen bir kategori slug'ına çevir."""
    key = str(value or "").strip().lower().replace("-", "_").replace(" ", "_")
    key = _ALIASES.get(key, key)
    return key if key in CATEGORY_SPECS else "guncel_haberler"


def category_list() -> list[dict[str, Any]]:
    """Dashboard'ın kullanacağı sabit ve sıralı kategori tanımları."""
    return [
        {
            "slug": spec["slug"],
            "label": spec["label"],
            "description": spec["description"],
            "mode": spec["mode"],
        }
        for slug in CATEGORY_ORDER
        for spec in [CATEGORY_SPECS[slug]]
    ]


def category_label(value: str | None) -> str:
    return CATEGORY_SPECS[normalize_category(value)]["label"]


def _topic_key(title: str) -> str:
    return " ".join(str(title or "").lower().split())


def _entry_matches(entry: dict[str, Any], hints: tuple[str, ...]) -> bool:
    haystack = " ".join(
        str(entry.get(key) or "").lower()
        for key in ("title", "query", "category")
    )
    return any(hint in haystack for hint in hints)


def topics_for_category(
    category: str,
    base_pool: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Kategoriye ait evergreen konu havuzunu üret.

    Mevcut 57 konuluk havuz geriye dönük korunur. Yeni kategoriye özel seed'ler
    yalnızca eksik başlıkları tamamlar; böylece eski state/dedup kayıtları
    geçersizleşmez.
    """
    slug = normalize_category(category)
    spec = CATEGORY_SPECS[slug]
    if spec["mode"] != "topic":
        return []

    hints = tuple(spec.get("topic_hints", ()))
    selected = [entry for entry in base_pool if _entry_matches(entry, hints)]
    seen = {_topic_key(entry.get("title", "")) for entry in selected}
    for title, query in spec.get("topic_seeds", ()):
        if _topic_key(title) not in seen:
            selected.append({"title": title, "query": query, "category": slug})
            seen.add(_topic_key(title))
    return selected
