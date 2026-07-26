"""Japonya Rüyası — paylaşımlı editöryel system prompt + yapılandırılmış üretim.

Bu modül TEK kaynaktır: hem "Haberden Üret" butonu hem de haber otomasyonu
(launchd) buradaki `JAPONYA_RUYASI_SYSTEM` prompt'unu ve `generate_editorial()`
fonksiyonunu kullanır. Böylece elle üretim ile otomatik üretim BİREBİR aynı
kaliteyi, aynı kalıbı, aynı puanlama kapısını uygular.

Akış:
  news (title + summary) → generate_editorial() → GPT(JAPONYA_RUYASI_SYSTEM)
  → yapılandırılmış JSON (başlık, açıklama, ana bilgi, neden, kaynak, kategori,
    puan) → puanlama kapısı (toplam < MIN_SCORE ise üretme) → (kart_ust_metni,
    caption) döner.
"""
from __future__ import annotations

import os
from typing import Any

# İçerik üretilmesi için gereken minimum toplam puan (5 kriter × 10 = 50 üzerinden).
# Kullanıcı kuralı: "Toplam puan 40'ın altındaysa içerik üretme."
# Ortam değişkeni EDITORIAL_MIN_SCORE ile kod değişmeden ayarlanabilir (ör. RSS
# feed'leri yumuşak haber ağırlıklıysa 30'a düşür; daha seçici istersen 45 yap).
try:
    MIN_SCORE = int(os.environ.get("EDITORIAL_MIN_SCORE", "30"))
except ValueError:
    MIN_SCORE = 30


# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM PROMPT — Japonya Rüyası araştırma editörü (kullanıcı tanımı, birebir)
# ─────────────────────────────────────────────────────────────────────────────
JAPONYA_RUYASI_SYSTEM = """Sen "Japonya Rüyası" isimli, Türkiye'nin en kaliteli Japonya seyahat bilgi platformunun araştırma editörüsün.

Misyonun;
Türkiye'den Japonya'ya gidecek kişilerin hiçbir yerde kolay kolay göremeyeceği,
gerçekten işine yarayacak, güncel, doğrulanmış, paylaşılmaya değer,
Instagram postları üretmektir.

Amacın viral olmak değildir.
Amacın insanların "İyi ki bunu önceden öğrenmişim." demesidir.

Her içerik gerçek bilgiye dayanmalıdır.
Asla uydurma bilgi üretme.
Eğer emin değilsen içerik üretme.

HEDEF KİTLE
- Japonya'ya ilk kez gidecek kişiler
- Japonya turu satın almayı düşünenler
- Kendi gezi planını yapanlar
- Tokyo, Kyoto, Osaka, Nara, Fuji görecek turistler
- Anime severler, Fotoğrafçılar, Teknoloji meraklıları
- Japon kültürüne ilgi duyanlar

İÇERİK FELSEFESİ
Bir bilgi şu şartlardan en az birini sağlamalıdır:
1) Para kazandırır. (JR Pass, Smart EX, Shinkansen erken rezervasyon,
   Duty Free limiti, vergi iadesi, Suica alternatifi.)
2) Zaman kazandırır. (En kısa aktarma, yanlış tren, metro çıkışı,
   asansör nerede, Google Maps'in bilmediği geçiş, valiz gönderme.)
3) Başı belaya sokmaz. (İlaç kuralları, drone yasağı, çöp kutusu olmaması,
   kimlik taşıma zorunluluğu, sigara alanları, trende konuşma, bisiklet cezaları.)
4) Gezi planına yardım eder. (Ne zaman gitmeli — sakura/momiji/kar zamanlaması,
   hangi festival ne zaman, hangi mekân/etkinlik görülmeli, mevsimlik açılış-
   kapanış, hava durumu penceresi, gizli fotoğraf noktaları, yemek deneyimi.)
Hedef kitle ilk kez Japonya'ya giden turistler olduğundan 4. madde de GERÇEK
fayda sayılır — "ne zaman git / ne var / nerede gör" bilgisi puan kazandırır.

İÇERİK KATEGORİLERİ (birini seç):
Ulaşım · Havaalanları · Turistik Noktalar · Teknoloji · Günlük Yaşam · Sağlık ·
Resmi Kurumlar · Kültür · Etkinlikler · Haber · Yeme İçme · Uyarı · Tasarruf

"BUNU GÖRÜNCE MUTLAKA İÇERİK ÜRET": yeni yasa, yeni tren, yeni uygulama, fiyat
değişikliği, turist uyarısı, dolandırıcılık yöntemi, deprem/hava/afet uyarısı,
yeni gezi rotası, ücretsiz etkinlik, indirim, yeni müze/restoran, Michelin listesi,
Sakura/sonbahar yaprak tahmini, Ghibli/Nintendo/Pokemon duyurusu.

PAYLAŞILABİLİR "BOOK FACT": Sadece haber paylaşma; turist tüyoları, az bilinen
noktalar, çok yapılan hatalar, yasak davranışlar, dolandırıcılıklar, gereksiz
harcamalar, ücretsiz aktiviteler, gizli teraslar, en iyi fotoğraf noktaları da üret.

GÜVENİLİRLİK KURALLARI
Her bilgi resmi kaynakla VEYA en az iki güvenilir kaynakla doğrulanmalı.
Şehir efsanesi / TikTok söylentisi / Reddit dedikodusu tek başına kaynak olamaz.
Emin değilsen üretme.

INSTAGRAM POST FORMATI (her içerik bu yapıda):
1. Dikkat çeken başlık — 8-15 kelime, merak uyandıran, clickbait DEĞİL.
2. Kısa açıklama — 2-3 cümle.
3. Ana bilgi — en fazla 80 kelime, kolay okunur.
4. "Bunu neden bilmelisin?" — gerçek faydayı açıkla.
5. Kaynak — resmi kaynak adı + (varsa) yayın tarihi.
6. Etiket — kategori.

PUANLAMA (içerik üretmeden ÖNCE kendi içinde 10 üzerinden puanla):
Şaşırtıcılık · Fayda · Güncellik · Doğruluk · Paylaşılabilirlik.
"Fayda" puanlanırken 4 fayda türünün HEPSİ geçerlidir: para, zaman, güvenlik VE
gezi planına yardım (mevsim/etkinlik zamanlaması, ne görülmeli, nerede). İlk kez
gidecek bir turist için "bunu bilmek işime yarar" diyeceği her bilgi fayda alır.
Toplam puan 30'un altındaysa içerik ÜRETME (uygun=false döndür).

ALTIN KURAL
Her postun sonunda kullanıcı şunu hissetmeli:
"Ben bunu başka hiçbir Japonya hesabında görmedim."
Kaliteyi niceliğin önünde tut. Az ama gerçekten değerli içerik üret.

DİL: Kusursuz Türkçe, 3. şahıs, klişesiz. Japonca özel terimleri çevirme
(Shinkansen, onsen, ryokan, Suica, sakura olduğu gibi). Emoji sadece caption'da."""


# ─────────────────────────────────────────────────────────────────────────────
# Ortak JSON şema açıklaması (haber + konu prompt'ları paylaşır)
# ─────────────────────────────────────────────────────────────────────────────
_JSON_SCHEMA_HINT = (
    "SADECE şu JSON şemasını döndür (başka metin yok):\n"
    "{\n"
    '  "uygun": true,\n'
    '  "puan": {"sasirticilik": 0, "fayda": 0, "guncellik": 0, '
    '"dogruluk": 0, "paylasilabilirlik": 0},\n'
    '  "toplam": 0,\n'
    '  "baslik": "8-15 kelime, merak uyandıran, clickbait olmayan başlık",\n'
    '  "kart_ust_metni": "Kart üstünde büyük görünecek TEK cümle, en fazla '
    '14 kelime — merak uyandırır, detay vermez",\n'
    '  "kisa_aciklama": "2-3 cümle giriş",\n'
    '  "ana_bilgi": "En fazla 80 kelime somut bilgi (kural/ipucu/nasıl)",\n'
    '  "neden_bilmelisin": "Gerçek fayda: para mı, zaman mı, güvenlik mi, gezi '
    'planı mı?",\n'
    '  "kaynak": "Resmi/güvenilir kaynak adı (biliniyorsa)",\n'
    '  "kategori": "Ulaşım|Havaalanları|Turistik Noktalar|Teknoloji|Günlük '
    'Yaşam|Sağlık|Kültür|Etkinlikler|Haber|Yeme İçme|Uyarı|Tasarruf",\n'
    '  "hashtagler": ["#japonya", "#tokyo", "..."]\n'
    "}\n"
    "Türkçe, klişesiz, uydurma YOK."
)


# ─────────────────────────────────────────────────────────────────────────────
# Kullanıcı prompt'u — haberi yapılandırılmış JSON'a çevir
# ─────────────────────────────────────────────────────────────────────────────
def build_user_prompt(title: str, summary: str, source: str = "",
                      published: str = "") -> str:
    kaynak_bilgi = f"KAYNAK: {source}" if source else ""
    tarih_bilgi = f"YAYIN TARİHİ: {published}" if published else ""
    meta = "\n".join(x for x in (kaynak_bilgi, tarih_bilgi) if x)
    return (
        "Aşağıdaki Japonya haberini/olgusunu, sistem talimatındaki İÇERİK "
        "FELSEFESİ ve PUANLAMA kurallarına göre değerlendir ve UYGUNSA bir "
        "Instagram postuna dönüştür.\n\n"
        f"HABER BAŞLIĞI: {title}\n"
        f"HABER ÖZETİ: {summary}\n"
        f"{meta}\n\n"
        "ÖNCE kendi içinde 10 üzerinden puanla: şaşırtıcılık, fayda, güncellik, "
        "doğruluk, paylaşılabilirlik. Toplam 30'un altındaysa 'uygun': false döndür "
        "ve boş alanlar bırak.\n\n"
        + _JSON_SCHEMA_HINT
    )


# ─────────────────────────────────────────────────────────────────────────────
# Caption montajı — yapılandırılmış alanlardan Instagram caption'ı kur
# ─────────────────────────────────────────────────────────────────────────────
def assemble_caption(data: dict[str, Any]) -> str:
    parcalar: list[str] = []
    kisa = (data.get("kisa_aciklama") or "").strip()
    ana = (data.get("ana_bilgi") or "").strip()
    neden = (data.get("neden_bilmelisin") or "").strip()
    kaynak = (data.get("kaynak") or "").strip()
    kategori = (data.get("kategori") or "").strip()
    tags = data.get("hashtagler") or []

    if kisa:
        parcalar.append(kisa)
    if ana:
        parcalar.append(ana)
    if neden:
        parcalar.append(f"📌 Neden bilmelisin: {neden}")
    if kaynak:
        parcalar.append(f"🔗 Kaynak: {kaynak}")

    body = "\n\n".join(parcalar)

    # Hashtag satırı — kategori + verilen etiketler (normalize: # ile başlasın)
    norm_tags: list[str] = []
    if kategori:
        norm_tags.append("#" + kategori.replace(" ", "").replace("İ", "I").lower())
    for t in tags:
        t = str(t).strip()
        if not t:
            continue
        norm_tags.append(t if t.startswith("#") else "#" + t.lstrip("#"))
    # tekrarları at, sırayı koru
    seen: set[str] = set()
    uniq = [t for t in norm_tags if not (t.lower() in seen or seen.add(t.lower()))]
    if uniq:
        body += "\n\n" + " ".join(uniq[:12])
    return body.strip()


# ─────────────────────────────────────────────────────────────────────────────
# Konu prompt'u — evergreen bir konuyu yapılandırılmış JSON'a çevir
# ─────────────────────────────────────────────────────────────────────────────
def build_topic_prompt(topic: str) -> str:
    return (
        "Aşağıdaki KONU, sistem talimatındaki İÇERİK FELSEFESİ ve PAYLAŞILABİLİR "
        "'BOOK FACT' kurallarına göre bir Instagram postuna dönüştürülecek. Bu bir "
        "haber değil, evergreen (her zaman geçerli) bir turist tüyosu/bilgisidir.\n\n"
        f"KONU: {topic}\n\n"
        "Bu konu hakkında ilk kez Japonya'ya gidecek bir turistin GERÇEKTEN işine "
        "yarayacak, çoğu Japonya hesabının vermediği somut bilgiyi ver (para/zaman/"
        "güvenlik/gezi planı faydası). Uydurma spesifik sayı/tarih verme; genel ama "
        "doğru bilgi ver. Emin olmadığın rakamı yazma.\n\n"
        "ÖNCE kendi içinde 10 üzerinden puanla: şaşırtıcılık, fayda, güncellik "
        "(evergreen konular için 'her zaman geçerli' = yüksek güncellik say), "
        "doğruluk, paylaşılabilirlik. Toplam 30'un altındaysa 'uygun': false.\n\n"
        + _JSON_SCHEMA_HINT
    )


# ─────────────────────────────────────────────────────────────────────────────
# Ana giriş — buton + otomasyon burayı çağırır
# ─────────────────────────────────────────────────────────────────────────────
def _finalize(data: Any) -> dict[str, Any]:
    """GPT JSON çıktısını puan kapısından geçir + caption montajla."""
    if not isinstance(data, dict):
        return {"uygun": False, "toplam": 0, "kart_ust_metni": "",
                "caption": "", "data": {}}

    toplam = data.get("toplam")
    if not isinstance(toplam, (int, float)):
        puan = data.get("puan") or {}
        toplam = sum(v for v in puan.values() if isinstance(v, (int, float)))
    toplam = int(toplam)

    uygun = bool(data.get("uygun", True)) and toplam >= MIN_SCORE
    if not uygun:
        return {"uygun": False, "toplam": toplam, "kart_ust_metni": "",
                "caption": "", "data": data}

    kart_ust = (data.get("kart_ust_metni") or data.get("baslik") or "").strip()
    kart_ust = kart_ust.strip('"').strip("'").strip()
    caption = assemble_caption(data)
    return {"uygun": True, "toplam": toplam, "kart_ust_metni": kart_ust,
            "caption": caption, "data": data}


def generate_editorial(oai, title: str, summary: str, source: str = "",
                       published: str = "") -> dict[str, Any]:
    """HABERDEN yapılandırılmış editöryel içerik üret.

    Dönüş:
      {"uygun": bool, "toplam": int, "kart_ust_metni": str, "caption": str,
       "data": <ham JSON>}
    uygun=False veya toplam<MIN_SCORE ise kart_ust_metni/caption boş döner.
    """
    user = build_user_prompt(title, summary, source, published)
    data = oai.chat_json(JAPONYA_RUYASI_SYSTEM, user, temperature=0.6,
                         max_tokens=1100)
    return _finalize(data)


def generate_editorial_topic(oai, topic: str) -> dict[str, Any]:
    """KONUDAN (evergreen tüyo) yapılandırılmış editöryel içerik üret.

    'Konudan Üret' butonu ve konu otomasyonu bunu kullanır. Aynı system
    prompt + puan kapısı; sadece kullanıcı prompt'u konu odaklı."""
    user = build_topic_prompt(topic)
    data = oai.chat_json(JAPONYA_RUYASI_SYSTEM, user, temperature=0.7,
                         max_tokens=1100)
    return _finalize(data)
