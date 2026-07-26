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

# Uygulama kodu + gömülü fontlar/assets.
COPY . .

# Web arayüzü portu (compose'da host 3090 → container 8420 map edilir).
EXPOSE 8420

# uvicorn — 0.0.0.0 (container dışından erişilebilir olmalı).
CMD ["python", "-m", "uvicorn", "src.web.app:app", "--host", "0.0.0.0", "--port", "8420"]
