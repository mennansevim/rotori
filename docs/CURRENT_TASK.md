# CURRENT_TASK.md — Bugünün İşi

> Bu dosya *bugünkü* çalışmanın canlı görünümüdür. Her tamamlanan görevden
> hemen sonra güncellenir.

**Bugünün tarihi:** 2026-07-30
**Aktif branch:** `main`
**Sprint hedefi:** Tanıtım sitesi etkileşim regresyonları + mobil F2 son
regresyonları.

---

## Aktif Hedef

Tanıtım sitesinin hero bölümündeki el ve telefon SVG'si masaüstünde %40
büyütüldü; mobil genişlik sınırı korundu. Japonca örnek seslerin oynatma hızı
0,78× değerine düşürüldü ve cümle kartının masaüstü genişliği ile iç yerleşimi
%40 küçültüldü. Güven bölümündeki altı kartın geniş ekranda 5+1 biçiminde
taşması düzeltilerek geniş ekranda tek sıra, orta ekranda dengeli 3×2 düzen
hedeflendi. Alışveriş kategorisindeki “Ikura desu ka? / Ne kadar?” örneği,
metin ve ses birlikte değiştirilerek kartla ödeme sorusuna dönüştürüldü.
Hero sahnesi referans görseldeki oranlara yaklaştırıldı: el/telefon merkezde
daha baskın, bildirim kartları iki yanda katmanlı ve aşama çubuğu görselin
altına bindirilmiş durumda. Bu düzenlemelerin tamamı masaüstü ve mobil
görünümlerde taşma olmadan doğrulandı. Hero sahnesi ayrıca geniş ekranlarda
iki yanda daha belirgin ve dengeli boşluk bırakacak şekilde daraltıldı.
Referans siteyle yapılan oran karşılaştırmasında kompozisyonun hâlâ fazla
büyük ve yüksek kaldığı görüldü; telefon/el, bildirim kartları ve sahne
birlikte küçültüldü. Kullanıcının gerçek masaüstü genişliğinde sahne yine
ekranın büyük bölümünü kapladığı için bu kez yalnızca piksel üst sınırı değil,
ekran genişliği oranı da %84 ile sınırlandırıldı.
Sağ taraftaki bildirim kartları, telefonla aralarındaki gereksiz boşluğu
azaltacak şekilde sahne genişliğinin %7–8'i kadar sola yaklaştırıldı.
Referans görseldeki gibi bildirim kartlarının iç kenarları telefon
kompozisyonuna bitiştirildi; iki taraftaki boşluklar birlikte kaldırıldı.
Telefon çevresindeki bildirim başlıkları ve alt açıklamalar, her kelimenin
ilk harfi büyük olacak biçimde ortak yazım düzenine geçirildi. Hero bildirim
gruplarının dış kenarlarını tek tek eşitleme yaklaşımı kompozisyonun ilişkisini
bozduğu için geri alındı; sol kartlar, telefon/el ve sağ kartlar göreli
konumları korunarak tek blok olarak ortalandı.
Tanıtım sitesi ve App Store önizlemesindeki tüm `teamLab` marka yazımları,
`TeamLab` biçiminde standartlaştırıldı. Son site değişiklikleri commit edilip
GitHub'a gönderildikten sonra Raspberry Pi üzerindeki `deploy.sh` ile
yayınlanacak.

## Tamamlananlar (bu ve önceki oturumlardan)

- ✅ **2026-07-22** Marka ismi Rotori olarak rebrand + sitede/uygulamada
  tutarlı hale getirildi (`360e5ae`).
- ✅ **2026-07-29** Mobil planner/viewer refaktörü ve site cilası commit edilip
  gönderildi (`f9b1207`).
- ✅ **2026-07-29** Hero görseli `rotori-hand-mobile.svg` adıyla yayın asset'i
  olarak sabitlendi (`4c0f735`).
- ✅ **2026-07-30** Hero “Planla / Yolculuk / Sahada” öğeleri erişilebilir
  bölüm bağlantılarına dönüştürüldü; aktif durum ve kaydırma doğrulandı.
- ✅ **2026-07-30** Altı Japonca kategori uygulamadaki yerel MP3'lere bağlandı;
  oynat/durdur, kategori seçimi, TR/EN metinleri ve romaji görünümü doğrulandı.
- ✅ **2026-07-30** Site genelindeki TR/EN pazarlama metinleri baştan sona
  gözden geçirildi; belirsiz vaatler somut fayda ve gizlilik açıklamalarıyla
  değiştirildi.
- ✅ **2026-07-30** Hero el ve telefon SVG'si masaüstünde %40 büyütüldü;
  Japonca cümle kartı %40 küçültüldü ve sesler 0,78× hızda oynatıldı.
- ✅ **2026-07-30** Hero sahnesi referanstaki merkez telefon, iki yandaki
  katmanlı bildirimler ve görsele binen koyu aşama çubuğuyla yeniden düzenlendi.
- ✅ **2026-07-30** Güven kartları geniş ekranda 6×1, orta ekranda 3×2,
  mobilde 1×6 olacak şekilde dengelendi.
- ✅ **2026-07-30** Alışveriş ses örneği “Kaado wa tsukaemasu ka?” /
  “Kart kullanabilir miyim?” cümlesi ve eşleşen MP3 ile değiştirildi.
- ✅ **2026-07-30** Hero sahnesi 1.600 px maksimum genişlikte ortalandı;
  2.048 px ekranda iki yanda 224 px, mobilde 36 px güvenli boşluk doğrulandı.
- ✅ **2026-07-30** Referans site oranına göre hero sahnesi 1.400 px'e,
  el/telefon 520 px'e ve bildirim kartları 460 px'e indirildi; sahne yüksekliği
  901 px'den 759 px'e düşürüldü.
- ✅ **2026-07-30** Hero sahnesi en fazla 1.120 px ve ekranın %84'ü olacak
  şekilde daraltıldı; el/telefon 460 px, bildirim kartları en fazla 400 px oldu.
- ✅ **2026-07-30** Hero sahnesindeki sağ bildirim kartları telefona 75–86 px
  yaklaştırıldı; 1.280 px ve 1.024 px genişliklerde yatay taşma olmadığı
  doğrulandı.
- ✅ **2026-07-30** Hero bildirim kartları iki tarafta telefonun arkasına
  bitişecek biçimde içeri alındı; 1.280 px ve 1.024 px genişliklerde katmanlama
  ve yatay taşma kontrol edildi.
- ✅ **2026-07-30** Hero bildirimlerindeki başlık, alt açıklama ve zaman
  etiketleri TR/EN için kelime başları büyük olacak biçimde düzenlendi.
- ✅ **2026-07-30** Hero kartlarının dış boşluklarını kartları ayrı ayrı
  taşıyarak eşitleme denemesi yapıldı; kompozisyonu bozduğu için sonraki
  düzenlemede geri alınmasına karar verildi.
- ✅ **2026-07-30** Sol bildirimler, telefon/el ve sağ bildirimler tek bir
  görsel blok olarak ortalandı; merkez sapması 1.280 px ve 1.024 px
  genişliklerde 0 px, yatay taşma 0 px ölçüldü.
- ✅ **2026-07-30** `website/` altındaki tüm `teamLab` marka yazımları
  `TeamLab` olarak düzeltildi; TR/EN sözlüklerinde eski yazım kalmadı.
- ✅ **2026-07-22** Website F1 seti (privacy + support + footer link + copy
  tazeleme) — `08d7449`, `cbd592a`.
- ✅ **2026-07-22** F1 App Store hazırlığı: Info.plist, hesap silme, aydınlık
  mor tanıtım (`11f3541`).
- ✅ **2026-07-2x** Design System v2 devreye alındı (`4578280`).
- ✅ F2.0 test regresyonları çözüldü — `plan_viewer` + `day_map` (`70c82d2`).
- ✅ Daha önce: Supabase auth uçtan uca (`233a57e` · Google OAuth),
  QA framework 100 senaryo (`13969b9`, `888feb2`), viewer satır içi düzenleme
  (`e66429c`), top-down shinkansen planı (`c7ef17f`).

## Kalanlar (kısa vadeli)

- [ ] Son site değişikliklerini GitHub'a gönder, Pi'de `~/rotori-web/deploy.sh`
  çalıştır ve canlı HTTP durumunu doğrula.
- [ ] `flutter analyze` ve `flutter test` yeşile boyanmalı — commit
  öncesi mutlaka çalıştır.
- [ ] `place_coords.dart` +32 satır ve `city_places.dart` -1 satır — yeni
  yerlerin koordinatları eklenmiş mi doğrula.
- [ ] Kök `img/hand-mobile.svg` tasarım kaynak dosyasıdır. Yayında bunun
  `website/img/rotori-hand-mobile.svg` adlı kopyası kullanılır; kök kopya
  deploy paketine girmez.
- [ ] Supabase Auth "Confirm email" prod öncesi **aç** (hâlâ kapalı — `[[supabase-backend]]`).
- [ ] App Store submission checklist — Sign in with Apple Services ID
  yapılandırması ($99/yıl Developer + Services ID) — `[[supabase-backend]]`.

## Bilinen Blocker'lar

- **2026-07-29 regresyon kontrolü:** `flutter test` sonucunda 327 test geçti,
  10 widget testi başarısız oldu. Hatalar ağırlıkla sadeleştirilen welcome
  akışının eski metinlerini ve viewer'ın eski menü/tema davranışını bekleyen
  testlerde. Push sonrasında testleri güncel ürün davranışıyla hizalama öncelikli.
- `flutter analyze` uygulama hatası üretmedi; 1 deprecated API bildirimi ve
  testlerde 4 lint bilgisi nedeniyle komut 5 issue ile kapandı.

## Sıradaki Uygulama Adımı

1. Başarısız 10 widget testini güncel welcome/viewer davranışıyla hizala.
2. `flutter analyze` bildirimlerini temizle ve `flutter test`i yeşile boya.
3. Site düzeltmesini ayrı bir commit olarak gönder.

## Şu An Değişen Dosyalar

`docs/*.md`, `website/index.html` ve `website/audio/`. Kök `img/` klasörü
yalnızca untracked tasarım kaynağıdır ve bu düzeltmenin parçası değildir.

## Son Commit'ler (referans)

```
4578280 feat(website): baştan aşağı revizyon — Design System v2
70c82d2 fix(test): plan_viewer + day_map regresyonlarını çöz — F2.0
cbd592a copy(website): 'Hesap gerekmez' → 'Ücretsiz · reklamsız'
08d7449 feat(website): Privacy Policy + Destek sayfaları + footer link
11f3541 feat(release+web): F1 App Store prep — Info.plist, hesap silme
```
