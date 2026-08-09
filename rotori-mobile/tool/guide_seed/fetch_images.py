#!/usr/bin/env python3
"""Yeni şehir noktaları için Wikimedia Commons'tan DOĞRULANMIŞ görsel çeker.

URL uydurmuyoruz: her URL API'den geliyor ve HTTP 200 ile doğrulanıyor.
Çıktı: scratchpad/images.json  ->  {place_id: [url, ...]}
"""
import json
import sys
import time
import urllib.parse
import urllib.error
import urllib.request

API = "https://commons.wikimedia.org/w/api.php"
UA = "RotoriTripPlanner/1.0 (data curation; contact via app repo)"

# place_id -> Commons arama sorgusu (spesifik olsun diye şehir adı eklendi)
QUERIES = {
    # Yokohama
    "yk-minato": "Minato Mirai 21 Yokohama skyline",
    "yk-chinatown": "Yokohama Chinatown gate",
    "yk-sankeien": "Sankeien Garden Yokohama",
    "yk-cupnoodle": "Cup Noodles Museum Yokohama",
    "yk-akarenga": "Yokohama Red Brick Warehouse",
    # Hakone
    "hk-shrine": "Hakone Shrine torii lake Ashi",
    "hk-owakudani": "Owakudani Hakone",
    "hk-ashi": "Lake Ashi Hakone",
    "hk-openair": "Hakone Open-Air Museum",
    "hk-gora": "Gora Hakone",
    # Kamakura
    "km-daibutsu": "Kamakura Daibutsu Kotoku-in",
    "km-hasedera": "Hasedera Kamakura",
    "km-hachimangu": "Tsurugaoka Hachimangu",
    "km-enoshima": "Enoshima island",
    "km-hokokuji": "Hokokuji bamboo Kamakura",
    # Fuji
    "fj-kawaguchi": "Lake Kawaguchi Mount Fuji",
    "fj-chureito": "Chureito Pagoda Fuji",
    "fj-oshino": "Oshino Hakkai",
    "fj-fujiq": "Fuji-Q Highland",
    "fj-5th": "Mount Fuji fifth station Subaru",
    # Nikko
    "nk-toshogu": "Nikko Toshogu shrine",
    "nk-kegon": "Kegon Falls Nikko",
    "nk-chuzenji": "Lake Chuzenji",
    "nk-shinkyo": "Shinkyo bridge Nikko",
    "nk-rinnoji": "Rinnoji Nikko",
    # Nagoya
    "ng-castle": "Nagoya Castle",
    "ng-atsuta": "Atsuta Shrine Nagoya",
    "ng-osu": "Osu Kannon Nagoya",
    "ng-toyota": "Toyota Commemorative Museum Industry Technology",
    "ng-ghibli": "Ghibli Park Aichi",
    # Kobe
    "kb-harborland": "Kobe Harborland port tower",
    "kb-kitano": "Kitano Ijinkan Kobe",
    "kb-rokko": "Mount Rokko Kobe night view",
    "kb-nunobiki": "Nunobiki Falls Kobe",
    "kb-nankinmachi": "Nankinmachi Kobe Chinatown",
    # Himeji
    "hm-castle": "Himeji Castle",
    "hm-kokoen": "Koko-en Garden Himeji",
    "hm-engyoji": "Engyoji Mount Shosha",
    "hm-otemae": "Otemae street Himeji",
    "hm-nadagikkenn": "Himeji Central Park",
    # Takayama
    "tk-sanmachi": "Sanmachi Takayama old town",
    "tk-jinya": "Takayama Jinya",
    "tk-folk": "Hida Folk Village Takayama",
    "tk-market": "Miyagawa morning market Takayama",
    "tk-shirakawa": "Shirakawa-go gassho village",
    # Matsumoto
    "mt-castle": "Matsumoto Castle",
    "mt-nakamachi": "Nakamachi street Matsumoto",
    "mt-kamikochi": "Kamikochi Kappa bridge",
    "mt-wasabi": "Daio Wasabi Farm Azumino",
    "mt-art": "Matsumoto City Museum of Art",
    # Fukuoka
    "fk-ohori": "Ohori Park Fukuoka",
    "fk-dazaifu": "Dazaifu Tenmangu",
    "fk-canal": "Canal City Hakata",
    "fk-kushida": "Kushida Shrine Fukuoka",
    "fk-yatai": "Nakasu yatai Fukuoka",
    # Nagasaki
    "ns-peace": "Nagasaki Peace Park statue",
    "ns-glover": "Glover Garden Nagasaki",
    "ns-inasa": "Mount Inasa Nagasaki night view",
    "ns-dejima": "Dejima Nagasaki",
    "ns-oura": "Oura Church Nagasaki",
    # Hakodate
    "hd-yama": "Mount Hakodate night view",
    "hd-market": "Hakodate morning market",
    "hd-kanemori": "Kanemori Red Brick Warehouse Hakodate",
    "hd-goryokaku": "Goryokaku Hakodate",
    "hd-motomachi": "Motomachi Hakodate church",
    # Okinawa
    "ok-shuri": "Shuri Castle Okinawa",
    "ok-kokusai": "Kokusai dori Naha",
    "ok-churaumi": "Churaumi Aquarium",
    "ok-manzamo": "Cape Manzamo Okinawa",
    "ok-naminoue": "Naminoue Beach Naha",
}

ALLOWED_WIDTH = "960px-"


def _get(url, method="GET", tries=5):
    """429'a saygılı istek — üstel geri çekilme."""
    delay = 5
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA}, method=method)
            return urllib.request.urlopen(req, timeout=30)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < tries - 1:
                time.sleep(delay)
                delay *= 2
                continue
            raise
    raise RuntimeError("unreachable")


def search(query, limit=4):
    params = {
        "action": "query",
        "generator": "search",
        "gsrsearch": query,
        "gsrnamespace": "6",
        "gsrlimit": str(limit),
        "prop": "imageinfo",
        "iiprop": "url|mime",
        "iiurlwidth": "960",
        "format": "json",
    }
    url = API + "?" + urllib.parse.urlencode(params)
    with _get(url) as r:
        data = json.load(r)
    pages = (data.get("query") or {}).get("pages") or {}
    out = []
    # search sırasını koru
    for p in sorted(pages.values(), key=lambda x: x.get("index", 99)):
        ii = (p.get("imageinfo") or [{}])[0]
        mime = ii.get("mime", "")
        thumb = ii.get("thumburl")
        if not thumb or not mime.startswith("image/"):
            continue
        if mime in ("image/svg+xml", "image/gif"):
            continue
        thumb = thumb.split("?")[0]  # utm parametrelerini at
        if ALLOWED_WIDTH not in thumb:
            continue
        out.append(thumb)
    return out


def verify(url):
    try:
        with _get(url, method="HEAD") as r:
            return r.status == 200
    except Exception:
        return False


def main():
    out = "/private/tmp/claude-514253398/-Users-sevimm-Documents-Projects-rotori-app/63d4ace7-3ebd-49c3-a8cf-8a0e4e1c8559/scratchpad/images.json"
    # Sürdürülebilir: önceki turda dolan kayıtları tekrar çekme.
    try:
        with open(out) as f:
            result = {k: v for k, v in json.load(f).items() if v}
    except Exception:
        result = {}
    for pid, q in QUERIES.items():
        if result.get(pid):
            continue
        urls = []
        try:
            for u in search(q):
                if verify(u):
                    urls.append(u)
                if len(urls) >= 2:
                    break
        except Exception as e:
            print(f"HATA {pid}: {e}", file=sys.stderr)
        result[pid] = urls
        print(f"{pid}: {len(urls)}", flush=True)
        with open(out, "w") as f:   # her adımda kaydet (kesilirse kayıp olmasın)
            json.dump(result, f, indent=1, ensure_ascii=False)
        time.sleep(2.0)

    with open(out, "w") as f:
        json.dump(result, f, indent=1, ensure_ascii=False)
    missing = [k for k, v in result.items() if not v]
    print(f"\nTOPLAM {len(result)} | GÖRSELSİZ {len(missing)}: {missing}")


if __name__ == "__main__":
    main()
