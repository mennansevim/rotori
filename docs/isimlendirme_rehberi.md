# Video Dosyası İsimlendirme Rehberi

Prompt-driven Reels üretimi, video dosyasının **adında geçen anahtar kelimeleri**
[src/labeling.py](../src/labeling.py) `_KURALLAR` sözlüğü ile match ederek çalışır.
Yani senin `IMG_1234.MOV` diye adlandırdığın Todai-ji videosu, adında `todai` geçmediği
için "Nara Todai-ji" olarak tanınamıyor.

Bu rehber, videolarını yeniden adlandırıp arşivi maksimum aranabilir hale getirmene
yardım eder.

---

## Temel format

```
<sehir>-<mekan>-<konu>-<opsiyonel-etiketler>.<ext>
```

Türkçe karakter kullanma, boşluk yerine `-` veya `_`, hepsi küçük harf.

**İyi örnekler:**
- `nara-todaiji-dev-buda.mov`
- `kyoto-kinkakuji-altin-pavyon.mp4`
- `kyoto-fushimi-inari-torii-tunel.mp4`
- `tokyo-shinjuku-yodobashi-tax-free.mp4`
- `osaka-dotonbori-glico-gece.mov`
- `nara-kasuga-taisha-fener.mp4`
- `tokyo-teamlab-planets-su-odasi.mp4`
- `universal-nintendo-mario-kart.mp4`

**Kötü örnekler (tanınamaz):**
- `IMG_1234.MOV` — hiç bir şey söylemiyor
- `nara video 3.mp4` — boşluk + Türkçe olmayan tanımlayıcı
- `DJI_20260521_034.mp4` — sadece tarih (fallback etiketi verir ama spesifik değil)

---

## Şu an tanınan anahtar kelimeler (sözlükten)

Aşağıdakilerden hangisi dosya adında geçerse otomatik doğru etiket verilir:

### Nara
| Etiket | Anahtar kelimeler |
|---|---|
| Nara Todai-ji | `todai`, `todaiji`, `buddha`, `budist`, `buda-heykel`, `dev-buda` |
| Kasuga Taisha | `kasuga`, `taisha` |
| Nara Parkı | `nara-park` |
| Nara Geyikleri | `nara`, `geyik`, `deer` |

### Kyoto
| Etiket | Anahtar kelimeler |
|---|---|
| Kyoto Fushimi Inari | `fushimi`, `inari`, `torii`, `kirmizi-kapi` |
| Kyoto Kinkaku-ji | `kinkaku`, `kinkakuji`, `altin` |
| Kyoto Ginkaku-ji | `ginkaku`, `ginkakuji`, `gumus` |
| Kyoto Kiyomizu-dera | `kiyomizu`, `kiyomizudera` |
| Kyoto Ryoan-ji | `ryoan`, `ryoanji`, `zen-bahce` |
| Kyoto Gion / Yasaka | `yasaka`, `gion` |
| Kyoto Arashiyama Bambu | `arashiyama`, `bambu` |
| Kyoto Nishiki Market | `nishiki` |

### Osaka
| Etiket | Anahtar kelimeler |
|---|---|
| Dotonbori | `dotonbori`, `glico` |
| Osaka Kalesi | `osaka-castle`, `castle`, `osaka-kale` |
| Umeda Sky | `umeda` |
| Shinsekai | `shinsekai`, `tsutenkaku` |
| Kuromon Market | `kuromon` |
| Abeno Harukas | `abeno`, `harukas` |
| Namba | `namba` |

### Tokyo
| Etiket | Anahtar kelimeler |
|---|---|
| Asakusa Senso-ji | `asakusa`, `senso`, `kaminarimon`, `nakamise` |
| Meiji Jingu | `meiji-jingu`, `meiji-shrine`, `meiji-ormani` |
| Shibuya Meydanı | `shibuya`, `hachiko`, `shibuya-sky` |
| Shinjuku | `shinjuku`, `yodobashi`, `bic-camera` |
| Akihabara | `akihabara`, `elektronik` |
| Ginza | `ginza` |
| Tokyo Tower | `tokyo-tower` |
| Tokyo Skytree | `skytree` |
| teamLab Planets | `teamlab` |
| Odaiba | `odaiba`, `gundam`, `rainbow-bridge` |
| Ueno Doğa Bilimleri | `ueno`, `t-rex`, `spinosaurus`, `doga-bilim` |
| Harajuku | `harajuku`, `takeshita` |

### Tema Parkları
| Etiket | Anahtar kelimeler |
|---|---|
| Tokyo Disneyland | `disneyland`, `disney`, `prenses`, `cinderella`, `space-mountain` |
| Tokyo DisneySea | `disneysea`, `disney-sea` |
| Universal Studios Japan | `universal`, `usj`, `waterworld` |
| Universal - Nintendo World | `nintendo`, `mario`, `yoshi`, `super-nintendo` |
| Universal - Harry Potter | `harry-potter`, `hogwarts`, `butterbeer` |

### Kültür / Genel
| Etiket | Anahtar kelimeler |
|---|---|
| Shinkansen & Fuji | `shinkansen`, `fuji`, `nozomi`, `hikari` |
| Takkyubin | `takkyubin`, `yamato`, `valiz-kargo` |
| Ryokan | `ryokan`, `tatami` |
| Onsen | `onsen`, `kaplica` |
| Konbini (7-Eleven) | `7-eleven`, `konbini`, `seven-eleven`, `familymart`, `lawson` |
| Uniqlo | `uniqlo` |
| Sumo | `sumo` |
| Sakura | `sakura`, `cherry-blossom`, `kiraz-cicek` |
| Sushi | `sushi` |
| Ramen | `ramen` |
| Takoyaki (Osaka) | `takoyaki` |
| Okonomiyaki (Osaka) | `okonomiyaki` |

---

## Hızlı iş akışı

1. Video kaynak klasörünü aç (Finder): `open ~/Documents/Japonya`
2. `IMG_*` gibi anlamsız isimleri seç, önizleyerek şu formata çevir:
   ```
   <sehir>-<mekan>-<konu>.<ext>
   ```
3. Örn: 4 saniye bakıp `IMG_0567.MOV` → `nara-todaiji-dev-buda-yakin.mov`
4. 20-30 dosya rename ettikten sonra:
   ```bash
   .venv/bin/python -m src.step1_analyze --relabel-only
   ```
   Bu **saniyeler içinde** metadata.csv'yi yeni isimlerle günceller. Vision çağırmaz,
   sadece dosya adı kurallarını yeniden uygular.
5. Web UI'ye gidip yeni promptu dene (`Nara Todai-ji`, `Kinkakuji`, `Meiji Jingu` vb.).

## Toplu rename için — `scripts/list_videos_for_rename.py`

Elde tanınmayan (kaynak "vision" veya "tarih" olan, spesifik etiket alamamış)
dosyaların listesini gösteren yardımcı:

```bash
.venv/bin/python scripts/list_videos_for_rename.py
```

Bu script:
- metadata.csv'yi okur
- `kaynak != "dosya_adi"` olan satırları filtreler (yani ismi kural sözlüğüne uymayan
  ve fallback ile etiketlenen dosyalar)
- her satır için mevcut dosya yolu + öneri format gösterir
- kendi terminalinden output'u dosyaya yazıp aç, elle isimlendir

## Yeni bir mekan/konu ekleme

Sözlükte olmayan bir kural varsa (örn. Kaiyukan Akvaryumu),
[src/labeling.py](../src/labeling.py) `_KURALLAR`'a satır ekle:

```python
(["kaiyukan", "akvaryum", "kaiyu"], "Osaka Kaiyukan", "Akvaryum", "Osaka"),
```

Sözlük **spesifikten genele** sıralı — yeni satırı doğru yere koy (genel `osaka`
kuralından önce). Sonra `--relabel-only` çalıştır, mevcut satırlar yeni kuralı görür.

## Not

- Rename yaptığın videoların bir **yedeğini almaya gerek yok** — biz sadece
  dosya adını okuyoruz, içeriğini değiştirmiyoruz. Ama Finder'da yeniden
  adlandırmayı geri almak isteyebileceğin için birkaç günlük bir Time Machine
  snapshot her zaman iyi fikir.
- MoviePy render sırasında dosyanın yeni adını kullanır. Onay galerisinde
  eski `_final.json` dosyaları eski adları referans edebilir — o eski dosyalar
  bir kereye mahsus geçersiz olabilir (silinebilir).
