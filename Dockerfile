# rotori-social — Japan Reels Maker web + otomasyon servisi
# Hedef: Raspberry Pi 5 (ARM64). python:3.11-slim multi-arch olduğundan
# aynı Dockerfile hem Mac (arm64) hem Pi'de derlenir.
FROM python:3.11-slim

# ffmpeg (moviepy/imageio render), fonts (video overlay + PIL story kartları),
# libGL/glib (opencv/moviepy bağımlılıkları) — hepsi runtime için gerekli.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        fonts-dejavu-core \
        libgl1 \
        libglib2.0-0 \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

# İstanbul saati — scheduler/otomasyon zamanlamaları için (news Pzt 20:00 vs.).
ENV TZ=Europe/Istanbul
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Önce bağımlılıklar — layer cache için ayrı kopyalanır.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# instagrapi ayrı aşamada — Pillow pin çatışması (moviepy<12 vs instagrapi>=12.2)
# tek resolver çalışmasında çözülemiyor. --no-deps ile kurup Pillow'u 12'ye
# yükseltiyoruz; moviepy Pillow 12 ile fiilen sorunsuz çalışır (Mac'te de öyle).
# NOT: Bu kurulum SADECE bu container imajının içinde — Pi host'una veya diğer
# container'lara (dify, agora, rotori-web) hiçbir etkisi yok.
# pydantic zaten fastapi ile geldi (uyumlu) — tekrar kurmuyoruz ki pydantic-core
# eşleşmesi bozulmasın. Sadece instagrapi'nin eksik çekirdek bağımlılıkları:
RUN pip install --no-cache-dir --no-deps \
        instagrapi>=2.18.9 \
        "PySocks>=1.7.1,<2" \
        "pycryptodomex>=3.23.0,<4" \
    && pip install --no-cache-dir --no-deps --upgrade "Pillow>=12.2.0,<13"

# Uygulama kodu + gömülü fontlar/assets.
COPY . .

# Sürüm damgası — deploy'da build arg ile geçilir (deploy.sh doldurur).
# /api/version bu dosyayı okur; container'da .git olmadığı için gerekli.
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=
RUN printf '{"commit":"%s","date":"%s"}\n' "$GIT_COMMIT" "$BUILD_DATE" > /app/VERSION

# Web arayüzü portu (compose'da host 3090 → container 8420 map edilir).
EXPOSE 8420

# uvicorn — 0.0.0.0 (container dışından erişilebilir olmalı).
CMD ["python", "-m", "uvicorn", "src.web.app:app", "--host", "0.0.0.0", "--port", "8420"]
