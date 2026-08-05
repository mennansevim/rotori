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

# (aranan alt-dizeler, mekan_etiketi, kategori, sehir) — SPESİFİKTEN GENELE sıralı.
# Kural sırası kritik: bir dosya/prompt birden fazla anahtara uyabilir, ilk match kazanır.
# Bu yüzden SPESİFİK (todai-ji, kinkaku-ji, fushimi) mutlaka GENEL (tapinak, kyoto, nara)
# kurallarından ÖNCE gelmeli.
_KURALLAR: list[tuple[list[str], str, str, str]] = [
    # ---- Nara: spesifik tapınak/mekan ----
    (["todai", "todaiji", "todai-ji", "buddha", "budist", "buda heykel", "dev buda"],
                                       "Nara Todai-ji",         "Tapınak",     "Nara"),
    (["kasuga", "taisha"],             "Kasuga Taisha",         "Tapınak",     "Nara"),
    (["nara park", "nara-park"],       "Nara Parkı",            "Park",        "Nara"),
    (["nara", "geyik", "deer"],        "Nara Geyikleri",        "Nara",        "Nara"),

    # ---- Kyoto: spesifik tapınak/bölge ----
    (["fushimi", "fusimi", "inari", "torii", "kırmızı kapı"],
                                       "Kyoto Fushimi Inari",   "Fushimi Inari", "Kyoto"),
    (["kinkaku", "kinkakuji", "altın", "altin pavilion"],
                                       "Kyoto Kinkaku-ji",      "Tapınak",     "Kyoto"),
    (["ginkaku", "ginkakuji", "gümüş", "gumus pavilion"],
                                       "Kyoto Ginkaku-ji",      "Tapınak",     "Kyoto"),
    (["kiyomizu", "kiyomizudera"],     "Kyoto Kiyomizu-dera",   "Tapınak",     "Kyoto"),
    (["ryoan", "ryoanji", "kaya bahce", "zen bahce"],
                                       "Kyoto Ryoan-ji",        "Tapınak",     "Kyoto"),
    (["yasaka", "gion"],               "Kyoto Gion / Yasaka",   "Tarihi Sokak", "Kyoto"),
    (["arashiyama", "bambu"],          "Kyoto Arashiyama Bambu", "Doğa",       "Kyoto"),
    (["nishiki", "nishiki market"],    "Kyoto Nishiki Market",  "Yemek",       "Kyoto"),
    (["kyoto tapinak"],                "Kyoto Tapınakları",     "Tapınak",     "Kyoto"),
    (["kyoto"],                        "Kyoto",                 "Kyoto",       "Kyoto"),

    # ---- Osaka: park + kültür ----
    (["dotonbori", "glico"],           "Dotonbori",             "Dotonbori",   "Osaka"),
    (["osaka castle", "castle", "osaka kale"],
                                       "Osaka Kalesi",          "Osaka Kalesi", "Osaka"),
    (["umeda"],                        "Umeda Sky",             "Umeda",       "Osaka"),
    (["shinsekai", "tsutenkaku"],      "Shinsekai",             "Shinsekai",   "Osaka"),
    (["kuromon"],                      "Kuromon Market",        "Yemek",       "Osaka"),
    (["abeno", "harukas"],             "Abeno Harukas",         "Manzara",     "Osaka"),
    (["namba"],                        "Namba",                 "Osaka",       "Osaka"),
    (["kobe beef", "kobe biftek"],     "Kobe Beef",             "Yemek",       "Osaka"),
    (["takoyaki"],                     "Osaka Takoyaki",        "Yemek",       "Osaka"),
    (["okonomiyaki"],                  "Osaka Okonomiyaki",     "Yemek",       "Osaka"),

    # ---- Tema parkları ----
    (["nintendo", "mario", "yoshi", "super nintendo world"],
                                       "Universal - Nintendo World", "Universal", "Osaka"),
    (["harry potter", "hogwarts", "butterbeer"],
                                       "Universal - Harry Potter",   "Universal", "Osaka"),
    (["waterworld", "universal", "usj"],
                                       "Universal Studios Japan",    "Universal", "Osaka"),
    (["disneyland", "disney", "prenses", "cinderella", "space mountain", "electrical parade"],
                                       "Tokyo Disneyland",      "Disneyland",  "Tokyo"),
    (["disneysea", "disney sea"],      "Tokyo DisneySea",       "DisneySea",   "Tokyo"),

    # ---- Tokyo: spesifik tapınak/bölge ----
    (["asakusa", "senso", "kaminarimon", "nakamise"],
                                       "Asakusa Senso-ji",      "Tapınak",     "Tokyo"),
    (["meiji jingu", "meiji shrine", "meiji ormani"],
                                       "Meiji Jingu",           "Tapınak",     "Tokyo"),
    (["yasukuni"],                     "Yasukuni",              "Tapınak",     "Tokyo"),
    (["shibuya crossing", "shibuya", "hachiko", "shibuya sky"],
                                       "Shibuya Meydanı",       "Shibuya",     "Tokyo"),
    (["shinjuku gyoen"],               "Shinjuku Gyoen",        "Park",        "Tokyo"),
    (["shinjuku", "yodobashi", "bic camera"],
                                       "Shinjuku",              "Shinjuku",    "Tokyo"),
    (["akihabara", "elektronik"],      "Akihabara",             "Alışveriş",   "Tokyo"),
    (["ginza"],                        "Ginza",                 "Alışveriş",   "Tokyo"),
    (["tokyo tower"],                  "Tokyo Tower",           "Tokyo Tower", "Tokyo"),
    (["skytree"],                      "Tokyo Skytree",         "Skytree",     "Tokyo"),
    (["teamlab"],                      "teamLab Planets",       "teamLab",     "Tokyo"),
    (["odaiba", "gundam", "rainbow bridge"],
                                       "Odaiba",                "Odaiba",      "Tokyo"),
    (["ueno", "spinosaurus", "t-rex", "doga bilim", "muze"],
                                       "Ueno Doğa Bilimleri",   "Müze",        "Tokyo"),
    (["harajuku", "takeshita"],        "Harajuku",              "Alışveriş",   "Tokyo"),
    (["roppongi"],                     "Roppongi",              "Tokyo",       "Tokyo"),
    (["tsukiji"],                      "Tsukiji",               "Yemek",       "Tokyo"),

    # ---- Ulaşım & lojistik ----
    (["shinkansen", "fuji", "nozomi", "hikari"],
                                       "Shinkansen & Fuji",     "Shinkansen",  ""),
    (["takkyubin", "yamato", "valiz kargo"],
                                       "Takkyubin (bavul kargo)", "Ulaşım",    ""),
    (["jr pass", "ic card", "suica", "pasmo", "icoca"],
                                       "JR & IC Card",          "Ulaşım",      ""),
    (["metro", "istasyon"],            "Metro & İstasyon",      "Ulaşım",      ""),

    # ---- Kültür / gündelik ----
    (["ryokan", "tatami"],             "Ryokan Deneyimi",       "Kültür",      ""),
    (["onsen", "kaplica"],             "Onsen",                 "Kültür",      ""),
    (["sushi"],                        "Sushi",                 "Yemek",       ""),
    (["ramen"],                        "Ramen",                 "Yemek",       ""),
    (["pokemon"],                      "Pokemon Center",        "Pokemon",     ""),
    (["7 eleven", "7eleven", "konbini", "seven eleven", "familymart", "lawson"],
                                       "Konbini (7-Eleven)",    "Konbini",     ""),
    (["uniqlo"],                       "Uniqlo Alışveriş",      "Alışveriş",   ""),
    (["lavabo", "tuvalet", "wc", "washlet"],
                                       "Japon Tuvaletleri",     "Kültür",      ""),
    (["sumo"],                         "Sumo",                  "Kültür",      ""),
    (["kimono", "yukata"],             "Kimono / Yukata",       "Kültür",      ""),
    (["sakura", "cherry blossom", "kiraz cicek"],
                                       "Sakura",                "Doğa",        ""),
    (["sake"],                         "Sake",                  "Yemek",       ""),
    (["matcha"],                       "Matcha",                "Yemek",       ""),

    # ---- Genel şehir fallback'leri (spesifikler yakalanmadıysa) ----
    (["nara"],                         "Nara Havadan",          "Havadan",     "Nara"),
    (["osaka"],                        "Osaka Havadan",         "Havadan",     "Osaka"),
    (["tokyo"],                        "Tokyo Havadan",         "Havadan",     "Tokyo"),

    # ---- En genel: tapınak/shrine ----
    (["jinja", "shrine", "temple", "tapinak"],
                                       "Genel Tapınak",         "Tapınak",     ""),
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
