"""Dosya adı + çekim tarihi + klasör bilgisinden akıllı mekân/kategori çıkarımı.

Arşivdeki dosya adları çok açıklayıcı olduğu için (Disneyland, Universal, Nara,
fushimi inari, osaka castle, dotonbori, shibuya, tokyo tower, 7 eleven, uniqlo...)
llava'nın jenerik etiketleri yerine bunları birincil sinyal olarak kullanıyoruz.
Vision analizi yalnızca dosya adı belirsiz olduğunda (DJI drone çekimleri) devreye
girer.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field


@dataclass
class Etiket:
    mekan_etiketi: str          # gruplama anahtarı + görünen ad ("Nara Geyikleri")
    kategori: str               # tematik ("Nara", "Disneyland", "Havadan"...)
    sehir: str                  # "Tokyo" | "Osaka" | "Kyoto" | "Nara" | ""
    cekim_tipi: str = "normal"  # normal | intro | gecis | yuruyus | yavas | yakin
    kaynak: str = "dosya_adi"   # dosya_adi | tarih | vision
    guven: float = 1.0          # 0..1


def _norm(s: str) -> str:
    """Küçük harf + Türkçe/aksan sadeleştirme (arama için)."""
    s = s.lower()
    repl = {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "İ": "i"}
    for a, b in repl.items():
        s = s.replace(a, b)
    s = "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))
    return s


# Aile üyeleri + çekim betimleyicileri (mekân DEĞİL — temizlenir / çekim tipi verir)
_KISILER = {"miray", "mennan", "gizem", "miay"}
_CEKIM_TIPLERI = [
    (["intro", "into", "giris"], "intro"),
    (["gecis"], "gecis"),
    (["yuruyus", "selfie", "zipla"], "yuruyus"),
    (["slow motion", "slow", "agi cekim", "agir", "pervane", "yavas"], "yavas"),
    (["yakin cekim", "yakin", "dipten"], "yakin"),
]

# (aranan alt-dizeler, mekan_etiketi, kategori, sehir) — SPESİFİKTEN GENELE sıralı
_KURALLAR: list[tuple[list[str], str, str, str]] = [
    (["fushimi", "fusimi", "inari"], "Kyoto Fushimi Inari", "Fushimi Inari", "Kyoto"),
    (["kyoto tapinak", "tapinak"], "Kyoto Tapınakları", "Tapınak", "Kyoto"),
    (["kyoto"], "Kyoto", "Kyoto", "Kyoto"),
    (["nara", "geyik"], "Nara Geyikleri", "Nara", "Nara"),
    (["disneyland", "disney", "prenses"], "Tokyo Disneyland", "Disneyland", "Tokyo"),
    (["nintendo", "mario", "yoshi"], "Universal - Nintendo World", "Universal", "Osaka"),
    (["waterworld", "universal"], "Universal Studios Japan", "Universal", "Osaka"),
    (["dotonbori"], "Dotonbori", "Dotonbori", "Osaka"),
    (["osaka castle", "castle", "osaka kale"], "Osaka Kalesi", "Osaka Kalesi", "Osaka"),
    (["umeda"], "Umeda Sky", "Umeda", "Osaka"),
    (["shinsekai"], "Shinsekai", "Shinsekai", "Osaka"),
    (["kuromon"], "Kuromon Market", "Yemek", "Osaka"),
    (["osaka"], "Osaka Havadan", "Havadan", "Osaka"),
    (["shibuya"], "Shibuya Meydanı", "Shibuya", "Tokyo"),
    (["shinjuku", "yodobashi"], "Shinjuku", "Shinjuku", "Tokyo"),
    (["tokyo tower"], "Tokyo Tower", "Tokyo Tower", "Tokyo"),
    (["skytree"], "Tokyo Skytree", "Skytree", "Tokyo"),
    (["asakusa", "senso"], "Asakusa Senso-ji", "Tapınak", "Tokyo"),
    (["teamlab"], "teamLab Planets", "teamLab", "Tokyo"),
    (["odaiba", "gundam"], "Odaiba", "Odaiba", "Tokyo"),
    (["ueno"], "Ueno", "Müze", "Tokyo"),
    (["shinkansen", "fuji"], "Shinkansen & Fuji", "Shinkansen", ""),
    (["pokemon"], "Pokemon Center", "Pokemon", ""),
    (["7 eleven", "7eleven", "konbini", "seven eleven"], "Konbini (7-Eleven)", "Konbini", ""),
    (["uniqlo"], "Uniqlo Alışveriş", "Alışveriş", ""),
    (["lavabo", "tuvalet", "wc"], "Japon Tuvaletleri", "Kültür", ""),
    (["tokyo"], "Tokyo Havadan", "Havadan", "Tokyo"),
]

# DJI drone dosya tarihinden şehir tahmini (Mayıs 2026 rotası):
# ~14-20 May Tokyo (6 gece Ikebukuro), 21-26 May Osaka (Kyoto/Nara günübirlik).
def _sehir_tarihten(yyyymmdd: str) -> str:
    try:
        d = int(yyyymmdd)
    except ValueError:
        return ""
    if d <= 20260520:
        return "Tokyo"
    return "Osaka"


_DJI_RE = re.compile(r"dji[_-]?(\d{8})\d*", re.IGNORECASE)


def cekim_tarihi(filename: str) -> str:
    m = _DJI_RE.search(filename)
    if m:
        return m.group(1)  # YYYYMMDD
    return ""


def _cekim_tipi(nname: str) -> str:
    for keys, tip in _CEKIM_TIPLERI:
        if any(k in nname for k in keys):
            return tip
    return "normal"


def parse_filename(filename: str, subdir: str = "") -> Etiket | None:
    """Dosya adı + üst klasörden mekân/kategori çıkar. Belirsizse None döner
    (o zaman vision devreye girer)."""
    hay = _norm(f"{subdir} {filename}")
    tip = _cekim_tipi(hay)

    for keys, mekan, kategori, sehir in _KURALLAR:
        if any(k in hay for k in keys):
            return Etiket(mekan_etiketi=mekan, kategori=kategori, sehir=sehir,
                          cekim_tipi=tip, kaynak="dosya_adi", guven=0.95)

    # DJI drone: tarihten şehir + havadan
    tarih = cekim_tarihi(filename)
    if tarih:
        sehir = _sehir_tarihten(tarih)
        if sehir:
            return Etiket(mekan_etiketi=f"{sehir} Havadan", kategori="Havadan",
                          sehir=sehir, cekim_tipi="yavas", kaynak="tarih", guven=0.6)

    return None


# Vision etiketini (İngilizce sahne) kabaca kategoriye eşle (fallback)
_VISION_MAP = [
    (["temple", "shrine", "torii", "pagoda"], "Tapınak", ""),
    (["street", "neon", "night", "city", "crossing"], "Sokak", ""),
    (["food", "ramen", "sushi", "restaurant", "market"], "Yemek", ""),
    (["park", "garden", "blossom", "forest", "deer"], "Doğa", ""),
    (["castle", "tower", "building", "aerial", "skyline"], "Manzara", ""),
    (["train", "station", "shinkansen"], "Ulaşım", ""),
    (["theme park", "ride", "roller"], "Tema Parkı", ""),
]


def etiket_from_vision(vision_label: str, sehir_hint: str = "") -> Etiket:
    n = _norm(vision_label)
    for keys, kategori, _ in _VISION_MAP:
        if any(k in n for k in keys):
            mekan = f"{sehir_hint} {kategori}".strip() if sehir_hint else kategori
            return Etiket(mekan_etiketi=mekan, kategori=kategori, sehir=sehir_hint,
                          cekim_tipi="normal", kaynak="vision", guven=0.4)
    base = vision_label.strip().title() or "Genel"
    mekan = f"{sehir_hint} {base}".strip() if sehir_hint else base
    return Etiket(mekan_etiketi=mekan, kategori=base, sehir=sehir_hint,
                  cekim_tipi="normal", kaynak="vision", guven=0.3)


# Çekim tipine göre sıralama önceliği (intro başa, geçişler arada, yavaş sona)
_TIP_SIRA = {"intro": 0, "normal": 1, "yakin": 2, "yuruyus": 3, "gecis": 4, "yavas": 5}


def tip_sira(cekim_tipi: str) -> int:
    return _TIP_SIRA.get(cekim_tipi, 1)
