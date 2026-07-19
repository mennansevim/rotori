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

## Dify Workflow Kurulumu (Manuel — bir kereye mahsus)

1. Tarayıcıdan `http://192.168.1.60:3000/apps` → **Create App** → **Workflow** → İsim: `Reels Kurgu Planlayıcı`.

2. **Ollama provider ayarı** (henüz eklenmediyse):
   - Sağ üst → **Settings** → **Model Provider** → **Ollama** → Add.
   - Base URL: `http://<mac-lan-ip>:11434` (Docker içinden `localhost` çalışmaz).
   - Modeller: `qwen2.5:3b` (LLM) ve `llava:7b` (Vision) ekleyin.
   - **Not:** Mac'te Ollama'yı LAN'a açmak için:
     ```bash
     launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
     # Ollama uygulamasını yeniden başlatın
     ```

3. **Start Node — Girdiler:**
   | Değişken | Tip | Açıklama |
   |---|---|---|
   | `mekan_etiketi` | String | "Fushimi Inari Tapınağı" |
   | `video_dosyalari` | String | virgülle ayrılmış dosya listesi |
   | `toplam_sure_sn` | Number | Hedef reel süresi |

4. **LLM Node** ekle:
   - Model: `qwen2.5:3b`
   - Structured Output: açık
   - Şema:
     ```json
     {
       "hook": "string",
       "overlays": [
         {"saniye": 0.0, "metin": "string", "sure": 3.0, "stil": "vurgu"}
       ],
       "cta": "string"
     }
     ```
   - System prompt:
     ```
     Sen bir Instagram Reels senaristisin. Verilen mekan için Türkçe hook, 3-5 overlay ve bir CTA üret.
     hook: 6-8 kelime, çarpıcı.
     overlays: her biri max 5 kelime, saniye/sure float.
     stil: baslik | altbaslik | vurgu.
     ```
   - User prompt: `Mekan: {{mekan_etiketi}} / Süre: {{toplam_sure_sn}}s`

5. **End Node** → Output değişken adı: `kurgu_json` → LLM node çıktısını bağla.

6. Sağ üstten **Publish** → **Access API** → App API key'i kopyala → `config.yaml` içine yapıştır.

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
