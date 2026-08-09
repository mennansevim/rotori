# Rehber tohum verisi (guide seed)

Yeni eklenen 14 şehrin gezilecek yerleri için **doğrulanmış** Wikimedia Commons
görselleri. Her URL Commons API'sinden geldi ve HTTP 200 ile doğrulandı —
elle uydurulmuş URL YOKTUR.

- `fetch_images.py` — toplayıcı. Sürdürülebilir (kesilirse kaldığı yerden
  devam eder) ve 429'a saygılı (üstel geri çekilme).
- `new_city_images.json` — `place_id -> [url, ...]`

## Ne için

`lib/domain/place_guide.dart` içindeki küratörlük sınırı
(`kGuideCuratedCityKeys`) şu an çekirdek 7 şehri kapsıyor. Yeni şehirlere
rehber yazılırken görselleri buradan alın; kalan iş TR/EN tanıtım + en az
3 ipucu yazmak.

Rehberi olmayan yer BOZUK DEĞİLDİR: `PlaceImageResolver` çalışma anında
Wikipedia'dan görsel çeker, detay sayfası kategori+şehir özetine düşer.

## Çalıştırma

```bash
python3 tool/guide_seed/fetch_images.py
```
