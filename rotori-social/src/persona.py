"""Persona + kategori bazlı GERÇEK, el yapımı içerik tohumları + kalite filtreleri.

Yerel model (qwen 3B) kusursuz Türkçe yazamadığı için içeriğin tamamını (hook,
overlay, açıklama, hashtag) gezinin gerçek detaylarına dayanan EL YAPIMI tohumlardan
üretiyoruz. Böylece çıktı her seferinde doğru, spesifik ve klişesiz oluyor; zayıf
modele bağımlı değil.
"""
from __future__ import annotations

import re
from typing import Any

SYSTEM_PROMPT = (
    "Sen ailenle birlikte 13 günlük Japonya turu yapmış (Mayıs 2026) bir Türk gezi "
    "blogger'ısın. Adın Mennan; eşin ve çocuklarınla gezdin. Tokyo (6 gece Ikebukuro), "
    "Osaka (üs Namba), Kyoto ve Nara'yı gezdin. Instagram'da 'biz gitmeden bilseydik "
    "keşke' tüyoları paylaşıyorsun. Birinci çoğul ağız (biz, ailemle), kusursuz Türkçe, "
    "kısa ve net cümleler. Verilmeyen saat/fiyat/sayı/mekan UYDURMA. Klişe tavsiye yok."
)

# Her mekân için: gerçek tüyolar + hook + overlay + hashtag + el yapımı açıklama.
SEEDS: dict[str, dict[str, Any]] = {
    "Nara Geyikleri": {
        "tips": [
            "Geyik bisküvisi 'shika senbei' sadece resmi tezgahlarda satılır; kendi yiyeceğini verme.",
            "Bisküviyi gösterince geyikler selam verir gibi öne eğilir; önce sen selam ver.",
            "Bisküviyi cebinde saklama, kokusunu alıp üstüne gelirler; avucunu açıp göster.",
            "Todai-ji'nin dev Buda'sı Nara Parkı'nın içinde, geyiklerle aynı rotada.",
        ],
        "hook": "Nara geyiklerinin kimsenin söylemediği kuralı",
        "overlays": ["ÖNCE SEN SELAM VER", "SHIKA SENBEI", "CEBİNDE SAKLAMA", "TODAI-JI İÇERİDE"],
        "hashtags": ["nara", "narapark", "japonya", "geyik", "japan", "narageyikleri", "gezi", "traveltips", "japonyagezi", "todaiji"],
        "aciklama": (
            "Nara'ya günübirlik gittik ve geyikler sandığımızdan çok daha 'kurallı' çıktı 🦌 "
            "Bisküvileri (shika senbei) sadece parktaki resmi tezgahlardan alın, kendi getirdiğiniz "
            "yiyeceği vermeyin. En tatlısı şu: bisküviyi gösterince çoğu geyik selam verir gibi öne "
            "eğiliyor, siz önce selam verince karşılık veriyorlar. Bisküviyi cebinizde saklamayın, "
            "kokusunu alıp üstünüze gelirler; avucunuzu açıp gösterin. Todai-ji'nin dev Buda'sı da "
            "aynı parkın içinde, geyiklerle aynı rotada. Ailece 13 günde biriktirdiğimiz bu tür "
            "detayları burada paylaşıyorum 👇"
        ),
    },
    "Tokyo Disneyland": {
        "tips": [
            "Resmi uygulamadan 'Premier Access' alıp popüler binitlerde sıra beklemiyorsun.",
            "Bazı binitlere Standby/Priority Pass'i uygulamadan almadan giremiyorsun.",
            "Electrical Parade için yeri erkenden uygulamadan takip et.",
            "Popcorn kovaları sınırlı; sevdiğin tasarımı gördüğün an al.",
        ],
        "hook": "Tokyo Disney'de sırada beklememenin yolu",
        "overlays": ["UYGULAMAYI İNDİR", "PREMIER ACCESS", "STANDBY PASS", "AKŞAM PARADE"],
        "hashtags": ["tokyodisney", "disneyland", "tokyo", "japonya", "japan", "disney", "gezi", "traveltips", "japonyagezi", "tokyodisneyland"],
        "aciklama": (
            "Tokyo Disney'de en büyük hatamız resmi uygulamayı geç indirmek oldu 🎢 Park girişinde "
            "uygulamadan 'Premier Access' alınca popüler binitlerde sıra beklemiyorsunuz. Bazı binitlere "
            "ise Standby veya Priority Pass'i yine uygulamadan almadan giremiyorsunuz. Akşamki Electrical "
            "Parade için yerinizi erkenden uygulamadan takip edin. Sevdiğiniz popcorn kovasını gördüğünüz "
            "an alın; tasarımlar sınırlı, sonra bulamıyorsunuz. Bu tür tüyoları ailece topladık, burada "
            "paylaşıyorum 👇"
        ),
    },
    "Universal Studios Japan": {
        "tips": [
            "Nintendo World'e giriş çoğu zaman zaman-bantlı; 'Area Timed Entry' almadan giremeyebilirsin.",
            "Express Pass sırayı kısaltıyor ama ayrı ve pahalı; kalabalık günlerde işe yarıyor.",
            "Power-Up Band ile Mario dünyasındaki etkileşimli oyunları oynayabiliyorsun.",
            "Harry Potter tarafında Butterbeer'i kupasıyla alırsan hatıra kalıyor.",
        ],
        "hook": "Universal Japan'a girmeden bilmen gereken",
        "overlays": ["TIMED ENTRY", "EXPRESS PASS", "POWER-UP BAND", "BUTTERBEER"],
        "hashtags": ["universalstudios", "usj", "osaka", "nintendoworld", "japonya", "japan", "supermario", "gezi", "traveltips", "japonyagezi"],
        "aciklama": (
            "Universal Studios Japan'a girmeden bilmemiz gerekenleri maalesef orada öğrendik 🍄 Nintendo "
            "World'e giriş çoğu zaman zaman-bantlı; uygulamadan 'Area Timed Entry' almadan alana "
            "giremeyebiliyorsunuz. Express Pass sıra süresini ciddi kısaltıyor ama ayrı ve pahalı, "
            "kalabalık günlerde işe yarıyor. Power-Up Band alırsanız Mario dünyasındaki etkileşimli "
            "oyunları oynuyorsunuz. Harry Potter tarafında Butterbeer'i kupasıyla alırsanız hatıra "
            "kalıyor. Japonya notlarımızı burada paylaşıyoruz 👇"
        ),
    },
    "Universal - Nintendo World": {
        "tips": [
            "Nintendo World'e giriş zaman-bantlı; 'Area Timed Entry' almadan giremeyebilirsin.",
            "Power-Up Band ile bloklara vurup etkileşimli mini oyunlar oynuyorsun.",
            "Mario Kart binişinde AR gözlük veriyorlar; gözlüğe göre nişan alıyorsun.",
        ],
        "hook": "Nintendo World'e girişin gizli şartı",
        "overlays": ["TIMED ENTRY ŞART", "POWER-UP BAND", "MARIO KART AR", "UYGULAMADAN AL"],
        "hashtags": ["nintendoworld", "supermario", "usj", "osaka", "japonya", "japan", "mariokart", "gezi", "traveltips", "japonyagezi"],
        "aciklama": (
            "Nintendo World hayal ettiğimizden bile iyiydi ama girişin bir şartı var 🎮 Alana giriş "
            "zaman-bantlı; uygulamadan 'Area Timed Entry' almadan giremeyebiliyorsunuz. İçeride "
            "Power-Up Band ile bloklara vurup etkileşimli mini oyunlar oynuyorsunuz. Mario Kart "
            "binişinde AR gözlük veriyorlar, gözlüğe göre nişan alıyorsunuz. Erkenden timed entry "
            "kapmak günün en kritik işi oldu bizim için. Bunun gibi detayları burada paylaşıyorum 👇"
        ),
    },
    "Kyoto Fushimi Inari": {
        "tips": [
            "Binlerce kırmızı torii bağış yapan kişi/şirketlerin adına dikilmiş; arkasında isim yazar.",
            "Tepeye tırmanış birkaç saat; yukarı çıktıkça kalabalık eriyip yol tenhalaşır.",
            "Giriş ücretsiz ve 24 saat açık.",
        ],
        "hook": "Fushimi Inari'nin torii'lerinin gerçek sırrı",
        "overlays": ["TORII = BAĞIŞ", "ARKASINDA İSİM VAR", "GİRİŞ ÜCRETSİZ", "YUKARISI TENHA"],
        "hashtags": ["fushimiinari", "kyoto", "japonya", "japan", "torii", "kyototravel", "gezi", "traveltips", "japonyagezi", "kyotojapan"],
        "aciklama": (
            "Fushimi Inari'nin binlerce kırmızı torii'sinin altından geçerken bir detay dikkatimizi "
            "çekti ⛩️ Bu torii'ler aslında bağış yapan kişi ve şirketlerin adına dikilmiş; arka "
            "yüzlerinde isim ve tarih yazıyor. Tepeye kadar tırmanış birkaç saat sürüyor ama asıl "
            "güzel yanı, yukarı çıktıkça kalabalığın eriyip yolun tenhalaşması. Giriş ücretsiz ve "
            "24 saat açık. Kyoto notlarımızı burada paylaşıyoruz 👇"
        ),
    },
    "Kyoto": {
        "tips": [
            "Kyoto otobüs ağırlıklı; metro sınırlı, çoğu tapınağa otobüsle gidiliyor.",
            "Gion'da geyşaların fotoğrafını izinsiz çekmek yasak, tabelalar var.",
            "Fushimi Inari girişi ücretsiz ve 24 saat açık.",
        ],
        "hook": "Kyoto'da turistlerin geç öğrendiği detay",
        "overlays": ["OTOBÜS ŞEHRİ", "GION'DA İZİN ŞART", "METRO SINIRLI", "FUSHIMI 24 SAAT"],
        "hashtags": ["kyoto", "japonya", "japan", "gion", "kyototravel", "gezi", "traveltips", "japonyagezi", "kyotojapan", "japantravel"],
        "aciklama": (
            "Kyoto'da ulaşımı yanlış kurgulayınca vakit kaybettik, siz aynısını yapmayın 🏮 Şehir "
            "otobüs ağırlıklı; metro çok sınırlı ve tapınakların çoğuna otobüsle gidiliyor. Gion'un "
            "tarihi sokaklarında geyşaların fotoğrafını izinsiz çekmek yasak, ara sokaklarda uyarı "
            "tabelaları var. Fushimi Inari ise ücretsiz ve 24 saat açık, sabaha karşı bambaşka. "
            "Bunun gibi tüyoları burada paylaşıyorum 👇"
        ),
    },
    "Kyoto Tapınakları": {
        "tips": [
            "Çoğu tapınağa otobüsle ulaşılıyor; metro sınırlı.",
            "Girişte el yıkama (temizu) ritüeli var; önce sol el, sonra sağ el.",
            "İçeride fotoğraf çoğu yerde yasak, tabelaya dikkat et.",
        ],
        "hook": "Kyoto tapınaklarında bilinmeyen kural",
        "overlays": ["TEMIZU RİTÜELİ", "SOL EL ÖNCE", "İÇERİDE FOTOĞRAF YOK", "OTOBÜSLE GİT"],
        "hashtags": ["kyoto", "tapinak", "japonya", "japan", "temple", "kyototravel", "gezi", "traveltips", "japonyagezi", "kyotojapan"],
        "aciklama": (
            "Kyoto tapınaklarında küçük ama önemli bir görgü kuralı öğrendik 🏯 Girişteki çeşmede "
            "el yıkama (temizu) ritüeli var: önce sol elinizi, sonra sağ elinizi yıkıyorsunuz. "
            "İçeride fotoğraf çoğu yerde yasak, tabelalara dikkat edin. Tapınakların çoğuna metroyla "
            "değil otobüsle ulaşılıyor, rotayı ona göre kurun. Japonya notlarımızı burada paylaşıyoruz 👇"
        ),
    },
    "Osaka Kalesi": {
        "tips": [
            "Kalenin içi müzeye çevrilmiş; en üst katta şehir manzarası var.",
            "Kaleyi çevreleyen park çok geniş; kapıdan kaleye yürüyüş uzun sürüyor.",
            "Havadan bakınca hendek ve surların büyüklüğü anlaşılıyor.",
        ],
        "hook": "Osaka Kalesi'ni gezmeden bilmen gereken",
        "overlays": ["İÇİ MÜZE", "EN ÜST MANZARA", "PARK ÇOK GENİŞ", "HENDEK DEVASA"],
        "hashtags": ["osakacastle", "osaka", "japonya", "japan", "osakakalesi", "gezi", "traveltips", "japonyagezi", "osakajapan", "japantravel"],
        "aciklama": (
            "Osaka Kalesi'ni gezerken iki şeyi keşke önceden bilseydik dedik 🏯 İçi tamamen müzeye "
            "çevrilmiş ve en üst kata çıkınca şehir manzarası açılıyor. Kaleyi çevreleyen park çok "
            "geniş; ana kapıdan kaleye yürüyüş hatırı sayılır sürüyor, ona göre zaman ayırın. Havadan "
            "bakınca hendeklerin ve surların büyüklüğü ancak anlaşılıyor. Japonya notlarımızı burada "
            "paylaşıyoruz 👇"
        ),
    },
    "Dotonbori": {
        "tips": [
            "Meşhur Glico tabelası Ebisubashi köprüsünün üstünden çekiliyor.",
            "Takoyaki ve okonomiyaki sokağın imzası; sıcakken içi çok sıcak olur.",
            "Işıklar asıl gece açılıyor; gündüz aynı yer sönük.",
        ],
        "hook": "Dotonbori'de o meşhur kareyi nerede çekersin",
        "overlays": ["EBISUBASHI KÖPRÜSÜ", "GLICO TABELASI", "GECE GİT", "TAKOYAKI SICAK"],
        "hashtags": ["dotonbori", "osaka", "japonya", "japan", "glico", "osakafood", "gezi", "traveltips", "japonyagezi", "osakajapan"],
        "aciklama": (
            "Dotonbori'deki o meşhur Glico tabelası fotoğrafını nerede çekeceğimizi arayınca öğrendik 🌃 "
            "En temiz kare Ebisubashi köprüsünün üstünden çıkıyor. Takoyaki ve okonomiyaki bu sokağın "
            "imzası; sıcak sıcak yiyin ama dikkat, içi gerçekten çok sıcak oluyor. Işıklar asıl gece "
            "açılıyor, gündüz aynı yer sönük kalıyor; akşam gidin. Osaka notlarımızı burada paylaşıyoruz 👇"
        ),
    },
    "Shibuya Meydanı": {
        "tips": [
            "Shibuya Crossing manzarasını Shibuya Sky'dan ya da istasyon üstü Starbucks'tan çekebiliyorsun.",
            "Hachiko heykeli buluşma noktası; meydanın çıkışında, hep kalabalık.",
            "Karşıdan karşıya herkes aynı anda geçiyor.",
        ],
        "hook": "Shibuya Crossing'i yukarıdan çekmenin yolu",
        "overlays": ["SHIBUYA SKY", "STARBUCKS ÜST KAT", "HACHIKO ÇIKIŞTA", "TÜM YÖNLER AÇILIR"],
        "hashtags": ["shibuya", "tokyo", "shibuyacrossing", "japonya", "japan", "hachiko", "gezi", "traveltips", "japonyagezi", "tokyojapan"],
        "aciklama": (
            "Shibuya Crossing'in o meşhur kuşbakışı karesini nasıl çekeceğimizi merak ediyorduk 🏙️ "
            "İki yol var: Shibuya Sky teras katı ya da istasyondaki Starbucks'ın üst katı. Aşağıdan "
            "çekmek istiyorsanız ışık döngüsünde herkes aynı anda geçtiği anı yakalayın. Hachiko "
            "heykeli meydanın çıkışında, buluşma noktası olduğu için hep kalabalık. Tokyo notlarımızı "
            "burada paylaşıyoruz 👇"
        ),
    },
    "Tokyo Tower": {
        "tips": [
            "Kulenin dibinden bakınca turuncu-beyaz yapı çok daha etkileyici.",
            "Gece aydınlatması akşam açılıyor; en iyi kare karşı sokaklardan.",
            "Yakınında konbini'den atıştırmalık alıp manzarada mola verilebiliyor.",
        ],
        "hook": "Tokyo Tower'ı en iyi nereden çekersin",
        "overlays": ["DİPTEN ÇEK", "GECE IŞIKLARI", "KARŞI SOKAKLAR", "KONBINI MOLASI"],
        "hashtags": ["tokyotower", "tokyo", "japonya", "japan", "tokyotravel", "gezi", "traveltips", "japonyagezi", "tokyojapan", "japantravel"],
        "aciklama": (
            "Tokyo Tower'ı en güzel nereden çekeceğimizi deneye deneye bulduk 🗼 Kulenin tam dibinden "
            "yukarı bakınca turuncu-beyaz yapı çok daha etkileyici duruyor. Gece aydınlatması akşam "
            "açılıyor ve en iyi kareler karşı sokaklardan çıkıyor. Biz yakındaki 7-Eleven'dan "
            "atıştırmalık alıp kule manzarasında keyifli bir mola verdik. Bunun gibi küçük tüyoları "
            "burada paylaşıyorum 👇"
        ),
    },
    "Tokyo Skytree": {
        "tips": [
            "Skytree yüksekliğiyle Tokyo Tower'dan farklı; şehir çok daha uzağa görünüyor.",
            "Alt katındaki alışveriş merkezi başlı başına gezilecek yer.",
        ],
        "hook": "Tokyo Skytree'yi gezmeden bil",
        "overlays": ["ÇOK YÜKSEK", "ŞEHİR UÇSUZ", "ALTI AVM", "GÜN BATIMI GÜZEL"],
        "hashtags": ["tokyoskytree", "skytree", "tokyo", "japonya", "japan", "gezi", "traveltips", "japonyagezi", "tokyojapan", "japantravel"],
        "aciklama": (
            "Tokyo Skytree'ye çıkınca şehrin ne kadar uçsuz bucaksız olduğunu ilk kez o zaman anladık 🌆 "
            "Yüksekliği Tokyo Tower'dan farklı, manzara çok daha uzağa uzanıyor. Kulenin alt katındaki "
            "alışveriş merkezi başlı başına gezilecek bir yer. Gün batımına denk getirirseniz manzara "
            "bambaşka oluyor. Tokyo notlarımızı burada paylaşıyoruz 👇"
        ),
    },
    "Shinkansen & Fuji": {
        "tips": [
            "Tokyo-Osaka hattında sağ (D-E) koltukları seç; Fuji o taraftan görünüyor.",
            "Valizleri takkyubin ile önceden yolladık, trene elimiz boş bindik.",
            "NOZOMI en hızlısı ama JR Pass eski sürümünde geçmiyordu; bileti ayrı aldık.",
        ],
        "hook": "Shinkansen'de Fuji'yi görmenin koltuğu",
        "overlays": ["SAĞ KOLTUK D-E", "FUJI O TARAFTA", "TAKKYUBIN İLE VALİZ", "NOZOMI EN HIZLI"],
        "hashtags": ["shinkansen", "fuji", "japonya", "japan", "mtfuji", "japantravel", "gezi", "traveltips", "japonyagezi", "bullettrain"],
        "aciklama": (
            "Tokyo'dan Osaka'ya Shinkansen'le geçerken küçük bir koltuk tüyosu her şeyi değiştirdi 🚄 "
            "Bu hatta sağ taraftaki (D-E) koltukları seçin; Fuji Dağı yolun o tarafından görünüyor. "
            "Valizlerimizi takkyubin ile otelden otele önceden yolladık, trene elimiz boş bindik. "
            "NOZOMI en hızlısı ama JR Pass'in eski sürümünde geçmiyordu, biletimizi ayrı aldık. "
            "Bunun gibi detayları burada paylaşıyorum 👇"
        ),
    },
    "Konbini (7-Eleven)": {
        "tips": [
            "7-Eleven ATM'leri yabancı kartla nakit çekmede en sorunsuzu.",
            "Onigiri paketini üstteki 1-2-3 adımlarına göre açarsan yosun gevrek kalıyor.",
            "Sıcak yemekleri kasada 'atatamemasu ka?' diye ısıtıyorlar.",
        ],
        "hook": "Japonya'da konbini'yi böyle kullanmalısın",
        "overlays": ["7-BANK ATM", "ONIGIRI 1-2-3", "KASADA ISITILIR", "KARTLA NAKİT"],
        "hashtags": ["konbini", "7eleven", "japonya", "japan", "japantravel", "japonyagezi", "gezi", "traveltips", "tokyo", "osaka"],
        "aciklama": (
            "Japonya'da konbini (özellikle 7-Eleven) sandığınızdan çok daha işlevli 🍙 Yabancı kartla "
            "nakit çekmek isterseniz en sorunsuzu 7-Bank ATM'leri; birçok yerde sadece bunlar çalışıyor. "
            "Onigiri paketini üstteki 1-2-3 adımlarına göre açarsanız yosun gevrek kalıyor, ezmeden "
            "yiyorsunuz. Sıcak yemekleri kasada 'atatamemasu ka?' deyince ısıtıyorlar. Ailece 13 günde "
            "biriktirdiğimiz bu tür tüyoları burada paylaşıyorum 👇"
        ),
    },
    "Uniqlo Alışveriş": {
        "tips": [
            "Büyük Uniqlo şubelerinde pasaportla anında vergisiz (tax-free) alışveriş yapılıyor.",
            "Japonya'ya özel UT tişörtler sadece burada; ülkende bulamıyorsun.",
            "Paçayı ücretsiz ve dakikalar içinde kısaltıyorlar.",
        ],
        "hook": "Japonya'da Uniqlo'yu böyle vurmalısın",
        "overlays": ["PASAPORTLA TAX-FREE", "JAPONYAYA ÖZEL UT", "ÜCRETSİZ PAÇA", "BÜYÜK ŞUBE"],
        "hashtags": ["uniqlo", "japonya", "japan", "tokyo", "alisveris", "taxfree", "gezi", "traveltips", "japonyagezi", "japantravel"],
        "aciklama": (
            "Uniqlo'yu Japonya'da gezerken birkaç şeyi geç fark ettik 🛍️ Büyük şubelerde pasaportunuzu "
            "gösterince anında vergisiz (tax-free) alışveriş yapabiliyorsunuz. Japonya'ya özel UT "
            "tişört tasarımları sadece burada satılıyor, ülkenizde bulamıyorsunuz. Aldığınız pantolonun "
            "paçasını ücretsiz ve dakikalar içinde kısaltıyorlar. Japonya notlarımızı burada paylaşıyoruz 👇"
        ),
    },
    "Japon Tuvaletleri": {
        "tips": [
            "Kumanda panelindeki büyük düğme genelde sifon değil, bide.",
            "Bazı tuvaletlerde 'ses' düğmesi su sesi çıkarıp mahremiyet sağlıyor.",
            "Konbini ve istasyon tuvaletleri ücretsiz ve tertemiz.",
        ],
        "hook": "Japon tuvaletinde ilk hatanı yapma",
        "overlays": ["BÜYÜK DÜĞME = BİDE", "SES DÜĞMESİ", "ÜCRETSİZ VE TEMİZ", "PANELE DİKKAT"],
        "hashtags": ["japonya", "japan", "japankultur", "japantravel", "japonyagezi", "gezi", "traveltips", "tokyo", "kultur", "seyahat"],
        "aciklama": (
            "Japon tuvaletleri ilk gün bizi resmen şaşırttı 🚻 Kumanda panelindeki büyük düğme çoğu "
            "zaman sifon değil, bide oluyor; acele edip yanlışına basmayın. Bazılarında 'ses' düğmesi "
            "su sesi çıkarıp mahremiyet sağlıyor. En güzeli, konbini ve istasyon tuvaletleri ücretsiz "
            "ve tertemiz. Ailece biriktirdiğimiz bu tür pratik detayları burada paylaşıyorum 👇"
        ),
    },
    "Pokemon Center": {
        "tips": [
            "Pokemon Center'da sadece o şubeye/şehre özel ürünler satılıyor.",
            "Büyük şubelerde pasaportla tax-free yapılıyor.",
            "Kasadaki hediye paketi ücretsiz ve çok özenli.",
        ],
        "hook": "Pokemon Center'da kaçırılan detay",
        "overlays": ["ŞUBEYE ÖZEL ÜRÜN", "TAX-FREE", "ÜCRETSİZ PAKET", "HEDİYELİK CENNETİ"],
        "hashtags": ["pokemon", "pokemoncenter", "japonya", "japan", "tokyo", "japantravel", "gezi", "traveltips", "japonyagezi", "anime"],
        "aciklama": (
            "Pokemon Center hayranı bir aileyseniz bir detayı kaçırmayın 🎁 Her şubede sadece o "
            "şubeye ya da şehre özel ürünler satılıyor, hepsi her yerde yok. Büyük şubelerde "
            "pasaportla tax-free yapabiliyorsunuz. Kasada hediye paketi ücretsiz ve inanılmaz "
            "özenli, hediyelik için birebir. Japonya notlarımızı burada paylaşıyoruz 👇"
        ),
    },
    "Osaka Havadan": {
        "tips": [
            "Havadan bakınca Dotonbori kanalı ve kalenin hendekleri şehri baştan anlatıyor.",
            "Drone kuralları sıkı; kalabalık ve tapınak üstünde uçurmak yasak, açık alan seç.",
        ],
        "hook": "Osaka'yı gökten görünce anlıyorsun",
        "overlays": ["KANALLAR ŞEHRİ", "KALE HENDEKLERİ", "DRONE KURALI SIKI", "AÇIK ALAN SEÇ"],
        "hashtags": ["osaka", "japonya", "japan", "drone", "havadan", "osakajapan", "gezi", "traveltips", "japonyagezi", "aerial"],
        "aciklama": (
            "Osaka'yı bir de gökten görünce şehri baştan tanıdık 🚁 Havadan bakınca Dotonbori kanalı "
            "ve kalenin hendekleri şehrin dokusunu bambaşka anlatıyor. Ama dikkat: Japonya'da drone "
            "kuralları çok sıkı, kalabalık ve tapınak üstünde uçurmak yasak; biz izinli açık alanları "
            "seçtik. Kalkıştan önce yerel kuralları mutlaka kontrol edin. Japonya notlarımızı burada "
            "paylaşıyoruz 👇"
        ),
    },
    "Tokyo Havadan": {
        "tips": [
            "Havadan bakınca Tokyo'nun ne kadar uçsuz bucaksız olduğu anlaşılıyor.",
            "Drone kuralları çok sıkı; merkezde çoğu yerde yasak, izinli açık alan seç.",
        ],
        "hook": "Tokyo'nun büyüklüğünü gökten gör",
        "overlays": ["UÇSUZ BUCAKSIZ", "DRONE KURALI SIKI", "MERKEZDE YASAK", "AÇIK ALAN SEÇ"],
        "hashtags": ["tokyo", "japonya", "japan", "drone", "havadan", "tokyojapan", "gezi", "traveltips", "japonyagezi", "aerial"],
        "aciklama": (
            "Tokyo'yu havadan görünce şehrin büyüklüğü bambaşka anlam kazandı 🚁 Kare kare uzanan "
            "yapıların ucu bucağı yok. Ama Japonya'da drone kuralları çok sıkı: merkezde çoğu yerde "
            "uçurmak yasak, biz izinli açık alanları seçtik. Kalkıştan önce yerel kuralları mutlaka "
            "kontrol edin, cezası ağır. Tokyo notlarımızı burada paylaşıyoruz 👇"
        ),
    },
}

GENERIC = {
    "hook": "Japonya'da bunu bilseydik keşke",
    "overlays": ["BUNU KAÇIRMA", "NOT AL", "BİZ GEÇ ÖĞRENDİK", "GİTMEDEN BİL"],
    "hashtags": ["japonya", "japan", "gezi", "traveltips", "japonyagezi", "seyahat", "japantravel", "tokyo", "osaka", "reels"],
    "aciklama": (
        "Japonya'da ailece 13 gün geçirdik ve sıradan bir turistin geç fark ettiği pek çok "
        "detay biriktirdik. Bu tür pratik tüyoları burada paylaşıyorum, kaydetmeyi unutmayın 👇"
    ),
    "tips": [],
}

CTA_HAVUZU = [
    "Kaydet, gittiğinde işine yarar",
    "Takip et, Japonya notlarımı paylaşıyorum",
    "Yorumda sorularını bekliyorum",
    "Kaydet, listene ekle",
]

_BANNED_PATTERNS = [
    re.compile(r"\bsabah\s+\d", re.IGNORECASE),
    re.compile(r"\bsaat\s+\d", re.IGNORECASE),
    re.compile(r"\d+\s*['’]?d[ae]\s+(başla|basla|git|gel|ol)", re.IGNORECASE),
    re.compile(r"\b(erken git|erkenden git|rahat ayakkabı|bol su iç|kalabalıktan kaçın)", re.IGNORECASE),
    re.compile(r"\bbüyülü bir ülke\b", re.IGNORECASE),
]


def cliche_iceriyor(text: str) -> bool:
    return any(p.search(text or "") for p in _BANNED_PATTERNS)


def seed_for(mekan: str, kategori: str) -> dict[str, Any]:
    if mekan in SEEDS:
        return SEEDS[mekan]
    for m, v in SEEDS.items():
        if kategori and (kategori.lower() in m.lower() or m.lower() in mekan.lower()):
            return v
    return dict(GENERIC)
