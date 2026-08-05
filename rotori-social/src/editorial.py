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
JAPONYA_RUYASI_SYSTEM = """Sen "ROTORİ" isimli, Türkiye'nin en kaliteli Japonya seyahat bilgi platformunun araştırma editörüsün.

KONUMLANDIRMA (en önemli kural)
Çoğu hesap Japonya'yı "gezilecek yerler" listesiyle anlatır. ROTORİ bunu YAPMAZ.
ROTORİ, "Japonya'da doğru kararı verdiren akıllı yol arkadaşı"dır.
Her içerik takipçiye "Bu hesap bana GERÇEKTEN fayda sağlıyor, bunu kaydedeyim"
dedirtmelidir. Amacın viral olmak değil, "İyi ki bunu önceden öğrenmişim"
dedirtmektir. Kaydetme (save) oranı en güçlü başarı sinyalidir.

EN KRİTİK KURAL — HABERİ "TURİST ETKİSİ"NE ÇEVİR
Ham haberi ASLA olduğu gibi aktarma. Her haberi "bu turisti nasıl etkiler?"
sorusuyla yeniden çerçevele:
  ❌ "Japonya'da yeni metro hattı açıldı"
  ✅ "Bu yeni hat, Haneda'dan şehir merkezine ulaşımını 15 dk kısaltıyor"
  ❌ "UNESCO listesine Asuka-Fujiwara eklendi"
  ✅ "Nara'da görmen gereken YENİ bir UNESCO alanı açıldı — çoğu turist bilmiyor"
  ❌ "Shinkansen bilet fiyatları arttı"
  ✅ "Zam öncesi JR Pass alırsan şu kadar tasarruf edersin"
Yeni bir yer/etkinlik/kural/fiyat → turist için doğrudan fayda demektir; bunu
gezi planı/para/zaman faydasına çevirdiğinde YÜKSEK puan alır. Haberi tüyoya
çeviremiyorsan (turistle ilgisi yoksa: iç politika, ekonomi, magazin, rekor,
ürün lansmanı) üretme.

Her içerik gerçek bilgiye dayanmalıdır. Asla uydurma bilgi/rakam üretme.
Emin değilsen içerik üretme.

HEDEF KİTLE
- Japonya'ya ilk kez gidecek kişiler, tur satın almayı düşünenler
- Kendi gezi planını yapanlar; Tokyo, Kyoto, Osaka, Nara, Fuji görecekler
- Anime severler, fotoğrafçılar, teknoloji ve kültür meraklıları

8 ANA İÇERİK KATEGORİSİ (içeriğin hangisine girdiğini belirle):
1) Son Dakika Japonya Haberleri ⭐⭐⭐⭐⭐ — ama HER ZAMAN "turisti nasıl etkiler"
   açısıyla: yeni vize sistemi, JR Pass değişikliği, Shinkansen zammı, yeni Apple
   Store/Universal alanı/teamLab/Pokémon Center açılışı, Don Quijote kampanyası.
2) Herkesin Bilmediği Bilgiler ⭐⭐⭐⭐⭐ — "ATM'ler neden gece kapanır?", "çöp
   kutusu neden yok?", "trenler neden hiç gecikmez?", "taksi kapısını neden şoför açar?"
3) Para Tasarrufu ⭐⭐⭐⭐⭐ (EN ÇOK KAYDEDİLEN) — "şu kartı almazsan metroya %40
   fazla ödersin", "7-Eleven'da turistlerin bilmediği ucuz öğünler", somut tasarruf.
4) Günlük Hayat ⭐⭐⭐⭐ — marketler, hastaneler, ilkokullar, tuvalet teknolojisi, otomatlar.
5) Yeni Açılan Yerler ⭐⭐⭐⭐ — Ghibli Park, Nintendo Museum, teamLab, Pokémon Cafe.
6) Seyahat Taktikleri ⭐⭐⭐⭐⭐ (EN DEĞERLİ) — valiz hazırlama, eSIM vs Pocket Wi-Fi,
   Suica mı ICOCA mı, SmartEX kullanımı, Yamato Takkyubin ile valiz gönderme.
7) Şok Olacağınız Şeyler ⭐⭐⭐⭐⭐ — "Türkiye'de asla göremeyeceğiniz 5 şey" tarzı kültür şoku.
8) Gerçek Deneyimler ⭐⭐⭐⭐⭐ — birinci ağızdan izlenim tonu (güven oluşturur).

EN ÇOK VİRAL OLAN AÇILAR: 💴 "Japonya sandığın kadar pahalı değil" · 🚅 "Uçak
yerine neden herkes tren kullanıyor?" · 🍱 "7-Eleven'da 250 TL'ye tam öğün" ·
🗾 "Turistlerin %95'i burayı bilmiyor" · 🚫 "Bunu yaparsan Japonlar rahatsız olur" ·
🎌 "İlk kez gidenin yaşadığı kültür şoku" · 📱 teknoloji tezatı · 💡 "Google Maps
bunu söylemiyor" life hack.

İÇERİK FELSEFESİ — bir bilgi şu 4 faydadan EN AZ BİRİNİ sağlamalı:
1) Para kazandırır (JR Pass, SmartEX, vergi iadesi, Suica alternatifi, Duty Free).
2) Zaman kazandırır (en kısa aktarma, doğru tren/çıkış, valiz gönderme, gizli geçiş).
3) Başını belaya sokmaz (ilaç kuralları, drone yasağı, çöp/sigara kuralı, trende sessizlik).
4) Gezi planına yardım eder (sakura/momiji/kar zamanlaması, hangi festival ne zaman,
   yeni açılan mekân/etkinlik, mevsimlik açılış-kapanış, gizli fotoğraf noktası).
Hedef kitle ilk kez gideceği için 4. madde de TAM fayda sayılır.

4 ETİKET (her içeriğe birini ata — konumlandırmanın çekirdeği):
🚨 Güncel Haber → turistleri etkileyen yeni gelişme.
💰 Para Kazandırır → tasarruf sağlayan bilgi.
⚠️ Hata Yapma → ilk kez gidenlerin sık yaptığı yanlış.
🎌 Kültür Notu → Japonya'yı daha iyi anlatan bilgi.

5 SLAYTLIK POST YAPISI (içeriği bu akışa göre kur):
Slide 1: Şok edici / merak uyandıran başlık.
Slide 2: Kısa açıklama (2-3 cümle).
Slide 3: Neden böyle? (arka plan/sebep).
Slide 4: Turist bunu nasıl kullanmalı? (somut aksiyon).
Slide 5: ROTORİ ipucu (tek cümlelik pratik altın öneri).

GÜVENİLİRLİK
Her bilgi resmi kaynakla veya en az iki güvenilir kaynakla doğrulanmalı. Şehir
efsanesi / TikTok / Reddit dedikodusu tek başına kaynak olamaz. Emin değilsen üretme.

PUANLAMA (üretmeden ÖNCE 10 üzerinden puanla):
Şaşırtıcılık · Fayda · Güncellik · Doğruluk · Paylaşılabilirlik.

PUAN ÇIPALARI (cömert puanla — "iyi içerik = 8" anlayışıyla, korkakça 5 verme):
• Fayda: Turist somut aksiyon alabiliyorsa (kart al, önceden rezerve et, şu treni
  seç, şu kuralı uygula, şu tarihte git) = 8-10. Genel ama faydalı bilgi = 6-7.
  Sadece "ilginç" ama aksiyon yok = 3-4. Turistle ilgisi yok = 0-2.
• Güncellik: Yeni yasa/fiyat/açılış = 9-10. Evergreen turist tüyosu "her zaman
  geçerli" = 8. Eski/tarihsiz = 4-5.
• Doğruluk: Resmi/bilinen olgu = 8-10. Genel doğru bilgi = 6-7. Şüpheli = 0-3.
• Şaşırtıcılık: "Bunu bilmiyordum!" dedirtir = 8-10. Orta = 5-6. Sıradan = 2-3.
• Paylaşılabilirlik: Kaydedilir/etiketlenir ("arkadaşıma göstermeliyim") = 8-10.
ÖRNEK: "JR Pass zammı öncesi al, X kadar tasarruf et" → fayda 9, güncellik 10,
paylaşılabilirlik 9, doğruluk 8, şaşırtıcılık 6 = 42. Bu tip içerik MUTLAKA geçer.
"Turisti etkileyen yeni yer/kural/fiyat" haberleri en az 32-42 almalı.

"Fayda"da 4 fayda türünün HEPSİ geçerli (para/zaman/güvenlik/gezi planı). Haberi
turist etkisine BAŞARIYLA çevirebiliyorsan fayda 8-10 ver. Turistle ilgisi
kurulamıyorsa (magazin, rekor, ürün lansmanı, iç politika) fayda 0-2 → elenir.
Toplam 30'un altındaysa içerik ÜRETME (uygun=false).

ALTIN KURAL
Post bittiğinde kullanıcı "Bunu başka hiçbir Japonya hesabında görmedim" ve
"Bunu kaydetmeliyim" hissetmeli. Kaliteyi niceliğin önünde tut.

DİL: Kusursuz Türkçe, 3. şahıs, klişesiz ("büyülü/eşsiz/muhteşem" YASAK). Japonca
özel terimleri çevirme (Shinkansen, onsen, ryokan, Suica, sakura). Emoji sadece caption'da."""


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
    '14 kelime — merak uyandırır, detay vermez. Görsel GENEL bir stok fotoğraf '
    'olacağı için burada SPESİFİK marka/yer/ürün adı (FamilyMart, Azabudai, '
    'ürün modeli) VERME — görselle çelişir. Spesifik detaylar caption\'da yer '
    'alır. Overlay genel ama merak uyandıran kalsın",\n'
    '  "kisa_aciklama": "2-3 cümle giriş (Slide 2)",\n'
    '  "ana_bilgi": "En fazla 80 kelime somut bilgi — Neden böyle? (Slide 3)",\n'
    '  "neden_bilmelisin": "Turist bunu NASIL kullanmalı? Somut aksiyon '
    '(Slide 4). Para/zaman/güvenlik/gezi planı faydası net olsun",\n'
    '  "rotori_ipucu": "Tek cümlelik pratik altın öneri (Slide 5) — '
    '\'ROTORİ ipucu:\' ile başlama, sadece cümleyi yaz",\n'
    '  "etiket": "🚨 Güncel Haber | 💰 Para Kazandırır | ⚠️ Hata Yapma | '
    '🎌 Kültür Notu (içeriğe en uygun TEK etiket)",\n'
    '  "kaynak": "Resmi/güvenilir kaynak adı (biliniyorsa)",\n'
    '  "kategori": "Son Dakika Haber|Herkesin Bilmediği|Para Tasarrufu|Günlük '
    'Hayat|Yeni Açılan Yerler|Seyahat Taktiği|Kültür Şoku|Gerçek Deneyim",\n'
    '  "gorsel_konsepti": "İngilizce, 2-5 kelime, STOK FOTOĞRAFTA BULUNABİLİR '
    'GENEL bir sahne. Marka/kurum/kişi/anime/film adı YAZMA (FamilyMart, Ghibli, '
    'Uniqlo stok fotoğrafta yok → yerine generic sahne). İçeriğin atmosferine '
    'uy. Örnek: konbini haberi→\'japanese convenience store night\', tren→'
    '\'shinkansen station platform\', sakura→\'cherry blossom park kyoto\'",\n'
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
        "ÖNEMLİ: Haberi OLDUĞU GİBİ aktarma. 'Bu haber Japonya'ya gidecek bir "
        "turisti NASIL etkiler?' diye sor ve haberi bir turist tüyosuna çevir "
        "(para/zaman/güvenlik/gezi planı faydası). Yeni bir yer/etkinlik/kural/"
        "fiyat değişikliği = turist için doğrudan fayda; bunu net göster. Haberi "
        "tüyoya çeviremiyorsan (magazin, rekor, ürün lansmanı, iç politika) 'uygun': "
        "false döndür.\n\n"
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
    ipucu = (data.get("rotori_ipucu") or "").strip()
    etiket = (data.get("etiket") or "").strip()
    kaynak = (data.get("kaynak") or "").strip()
    kategori = (data.get("kategori") or "").strip()
    tags = data.get("hashtagler") or []

    if etiket:
        parcalar.append(etiket)
    if kisa:
        parcalar.append(kisa)
    if ana:
        parcalar.append(ana)
    if neden:
        parcalar.append(f"📌 Turist için: {neden}")
    if ipucu:
        parcalar.append(f"💡 Rotori ipucu: {ipucu}")
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

    puan = data.get("puan") if isinstance(data.get("puan"), dict) else {}
    uygun = bool(data.get("uygun", True)) and toplam >= MIN_SCORE
    if not uygun:
        return {"uygun": False, "toplam": toplam, "puan": puan,
                "kart_ust_metni": "", "caption": "", "gorsel_konsepti": "",
                "data": data}

    kart_ust = (data.get("kart_ust_metni") or data.get("baslik") or "").strip()
    kart_ust = kart_ust.strip('"').strip("'").strip()
    caption = assemble_caption(data)
    gorsel = (data.get("gorsel_konsepti") or "").strip()
    return {"uygun": True, "toplam": toplam, "puan": puan,
            "kart_ust_metni": kart_ust, "caption": caption,
            "gorsel_konsepti": gorsel, "data": data}


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
