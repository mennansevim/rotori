# japan-reels-maker

Lokal (Ollama + Dify + MoviePy) çalışan, arşivdeki ~1000 videodan otomatik Reels üreten pipeline.

## Kurulum

```bash
# 1. Ortam
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 2. Modeller
./scripts/pull_models.sh   # llava:7b (~4.7GB) + qwen2.5:3b

# 3. Config
# config.yaml içindeki REPLACE_ME alanlarını doldur:
#   - paths.video_source_dir: video klasörünün mutlak yolu
#   - dify.api_key: Dify app'in Access API token'ı (aşağıdaki workflow kurulduktan sonra alınır)
```

## Dify Workflow Kurulumu (Tek tıkla DSL import)

Workflow'un tamamı [dify/reels_kurgu_planlayici.yml](dify/reels_kurgu_planlayici.yml) içinde hazır. Manuel node kurulumu yok, sadece import edin:

1. **Ollama'yı LAN'a aç** (Dify Docker container'ından Mac'inize erişebilsin):
   ```bash
   launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
   # Ollama uygulamasını yeniden başlatın (menu bar → Quit → tekrar aç)
   ```
   LAN IP'nizi öğrenin: `ipconfig getifaddr en0` (örn. `192.168.1.42`).

2. **Ollama provider'ı Dify'a ekleyin** (bir kereye mahsus):
   - Tarayıcı: `http://192.168.1.60:3000` → giriş yap.
   - Sağ üst avatar → **Settings** → **Model Provider** → **Ollama** → **Add**.
   - Base URL: `http://<mac-lan-ip>:11434`
   - Modeller: `qwen2.5:3b` (LLM, mode: chat) ve `llava:7b` (Vision, opsiyonel) ekleyin.

3. **Workflow DSL'i import et:**
   - Dify → **Studio** → **Create App** → **Import DSL file** → `dify/reels_kurgu_planlayici.yml` seç.
   - Sağ üstten **Publish**.

4. **API key'i al:**
   - Sol menüde **API Access** → **API Key** → New Secret Key → kopyala.
   - `config.yaml` içinde `dify.api_key: "app-..."` alanına yapıştır.

5. **Doğrulama:**
   ```bash
   .venv/bin/python -m src.step3_dify   # --no-dify olmadan
   ```
   `data/kurgu_planlari/*_final.json` içinde Dify'dan gelen kurgu görünmeli.

**Not:** Import ederken Dify sürümüne göre "DSL version mismatch" uyarısı verebilir; genelde yine de import eder. Node'lar eksik/hatalı görünürse UI'da düzelt → Publish.

## Çalıştırma

### A) Web arayüzü (önerilen)

Tarayıcıdan pipeline'ı başlat, süreci canlı izle, üretilen reels'leri oynat ve caption'ı kopyala:

```bash
./scripts/run_web.sh          # http://127.0.0.1:8420
# port değiştirmek için: PORT=9000 ./scripts/run_web.sh
```

Panelde:
- Her adımı tek tek çalıştırma (güvenlik için "Tümünü çalıştır" yok; step1 tek seferde en fazla `run.max_videos_per_run` video işler)
- **Dify'ı atla** toggle'ı (lokal üretim için önerilir)
- Aşama kartlarında canlı sayaç/ilerleme + canlı log akışı + **Durdur**
- **Onay kuyruğu**: üretilen reels önce "Onay Bekleyen" galeride birikir; **Onayla** ile "Yayına Hazır"a taşınır, **Reddet** ile silinir
- Galeri: video oynatıcı, kare önizleme (poster), açıklama ve hashtag kopyalama

### B) Komut satırı

```bash
# Pilot (10 video)
./scripts/run_pipeline.sh --pilot

# Tümü (~1000 video)
./scripts/run_pipeline.sh
```

## Pipeline Aşamaları

| Adım | Script | Ne yapar |
|---|---|---|
| 1 | `src/step1_analyze.py` | **Akıllı etiketleme** (`src/labeling.py`): önce dosya adı + alt klasör + çekim tarihinden şehir/kategori/mekan/çekim-tipi çıkarır (ör. `Disneyland*`→Tokyo Disneyland, `DJI_20260522*`→Osaka Havadan). Yalnızca belirsiz kliplerde llava:7b vision'a düşer. Aynı dosyayı basename ile tekilleştirir. `data/metadata.csv`. Idempotent. |
| 2 | `src/step2_group.py` | Mekana göre gruplar; **süre-farkındalıklı** doldurma yapar (klipler intro→geçiş sırasına dizilir, siyah dolgu olmadan hedef süreye ulaşır), kategoriye göre anlatım tonu atar. `*_input.json`. |
| 3 | `src/step3_dify.py` | **Seed-öncelikli lokal üretim** (`src/persona.py`): her mekân için gerçek geziye dayalı el yapımı hook/overlay/hashtag/açıklama → kusursuz Türkçe, klişesiz, uydurmasız. Dify opsiyonel. `*_final.json`. |
| 4 | `src/step4_render.py` | 9:16 crop, **orantılı klip süreleri** (kaynağı aşmaz, kesik/siyah bar yok), Türkçe-duyarlı büyük harf overlay + CTA, H.264 export ve **ffprobe ile tam-render doğrulaması** → `output/reels/*.mp4`. |

### Akıllı Etiketleme (`src/labeling.py`)
Arşivdeki dosya adları çok açıklayıcı olduğu için (Disneyland, Universal, Nara, fushimi inari, osaka castle, dotonbori, shibuya, tokyo tower, 7 eleven, uniqlo…) llava'nın jenerik "Street" etiketleri yerine bunlar birincil sinyal. DJI drone klipleri için dosya adındaki tarihten şehir tahmin edilir (Tokyo ≤ 20 May, Osaka ≥ 21 May). Kişi adları (miray, mennan…) ve çekim betimleyicileri (intro, geçiş, yürüyüş, yavaş) mekân etiketinden ayıklanıp klip sıralamasında kullanılır.

## Config

Tüm parametreler `config.yaml` içinde. Öne çıkanlar:
- `reels.max_duration_sn`: hedef reel süresi (30-60 arası)
- `reels.clip_per_reel`: bir reelde birleştirilecek klip sayısı
- `ollama.vision_concurrency`: paralel vision çağrısı (M-serisi Mac için 4 makul)
- `pilot.pilot_mode`: `true` iken sadece `pilot_count` kadar örnek işler

## Yardımcı Komutlar

```bash
# Sadece Dify'ı bypass edip Ollama fallback ile
.venv/bin/python -m src.step3_dify --no-dify

# Sadece render, ilk 3 reel
.venv/bin/python -m src.step4_render --limit 3

# Ollama sağlık kontrolü
curl -s http://localhost:11434/api/tags | head
```

## Sorun Giderme

- **"Ollama erişilemiyor"** → `ollama serve` veya Ollama.app açık mı?
- **Dify workflow 404** → `dify.api_key` doğru mu? Workflow **Publish** edildi mi?
- **MoviePy `TextClip` hata** → `Arial Unicode.ttf` yolunu `config.yaml`'da doğrulayın.
- **Vision etiketleri hep aynı çıkıyor** → llava:7b Türkçe zayıf; `llava:13b`'e geçmeyi deneyin.
