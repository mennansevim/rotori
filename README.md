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

```bash
# Pilot (10 video)
./scripts/run_pipeline.sh --pilot

# Tümü (~1000 video)
./scripts/run_pipeline.sh
```

## Pipeline Aşamaları

| Adım | Script | Ne yapar |
|---|---|---|
| 1 | `src/step1_analyze.py` | Her videonun ilk karesini ffmpeg ile çıkarır, llava:7b'ye sorar, `data/metadata.csv`'ye yazar. Idempotent. |
| 2 | `src/step2_group.py` | Etiketleri fuzzy-normalize eder, mekan başına 3-5 klip seçer, `data/kurgu_planlari/*_input.json` üretir. |
| 3 | `src/step3_dify.py` | Her input JSON için Dify workflow API'yi çağırır (yoksa Ollama fallback), `*_final.json` yazar. |
| 4 | `src/step4_render.py` | 9:16 crop, concat, hook + overlay + CTA metin, H.264 export → `output/reels/*.mp4`. |

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
