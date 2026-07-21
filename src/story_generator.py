"""Instagram Story kartı üretici.

Kullanıcı konu verir (örn "Japonya'da kredi kartı nasıl kullanılır"), sistem:
  1. GPT (gpt-4o-mini) ile konuya özel 3 farklı kart pack'i üretir
     — her kart: başlık + kısa açıklama + vurgu kelimeleri + arka plan anahtarları
  2. Her kart için arşivden (metadata.csv sahne_ogeleri) uygun bir frame seçer
  3. PIL ile 1080x1920 render eder — Impact başlık + sarı vurgu + karanlık
     gradient + handle badge

Örnek stil (kullanıcının paylaştığı örneklerden alındı):
  - Arka plan: mekana özel foto, alt %55'te karanlık gradient
  - Başlık: Impact 96pt, uppercase, ortalanmış, bazı kelimeler sarı (#FFD700)
  - Açıklama: Arial Bold 40pt beyaz, 2-3 satır, bazı kelimeler sarı
  - Alt köşede handle badge: @mennansjapan yuvarlak pill
"""
from __future__ import annotations

import csv
import json
import random
import re
import time
import unicodedata
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from src.config import Config
from src.utils.logging import get_logger

log = get_logger("story")


# --- Renk sabitleri ---
COLOR_ACCENT = (255, 214, 61)   # altın sarı (highlight blokları, üst rozet)

FONT_IMPACT = "/System/Library/Fonts/Supplemental/Impact.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_MEDIUM = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

def _norm(text: str) -> str:
    text = (text or "").lower()
    for a, b in {"ç":"c","ğ":"g","ı":"i","ö":"o","ş":"s","ü":"u","İ":"i"}.items():
        text = text.replace(a, b)
    return "".join(c for c in unicodedata.normalize("NFKD", text)
                   if not unicodedata.combining(c))


def _tr_upper(s: str) -> str:
    """Türkçe-aware uppercase — Python'un .upper()'ı 'i'yi 'İ' yapmaz."""
    return (s or "").replace("i", "İ").replace("ı", "I").upper()


def _slugify(text: str, max_len: int = 40) -> str:
    n = _norm(text)
    s = re.sub(r"[^a-z0-9]+", "-", n).strip("-")
    return s[:max_len] or "story"


# --- 1) GPT ile 3 kart pack'i üret ---
_STORY_SYSTEM = (
    "Sen Japonya'yı ailesiyle 13 gün gezmiş bir Türk gezginsin (Mayıs 2026, "
    "Tokyo/Osaka/Kyoto/Nara). Kanalın Instagram'da 'Mennan'ın Japonya Günlüğü'. "
    "Her istekte kullanıcının verdiği konuyla ilgili Instagram STORY tarzı 3 "
    "hap bilgi kartı hazırlıyorsun. Her kart farklı bir alt-konuya odaklanmalı "
    "(tekrar yok). Kısa, çarpıcı, informatif. Yanıt SADECE JSON."
)


def generate_pack(cfg: Config, konu: str, count: int = 3) -> list[dict[str, Any]]:
    """GPT ile 3 (default) farklı kart pack'i üret."""
    from src.openai_client import OpenAIClient

    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise RuntimeError("OpenAI API key yok. config.yaml → openai bölümünü doldur.")

    user_prompt = f"""KONU: {konu}

Bu konuyla ilgili {count} farklı Instagram Story kartı üret. Her kart farklı bir alt-konuya odaklansın.

Her kart için:
- baslik: BÜYÜK HARFLERLE, MAX 4 KELİME (Impact tarzı vurucu Türkçe cümle).
  Örnek: "YÜRÜRKEN YEMEK YEMEMELİSİN", "IC CARD ŞART", "BAHŞİŞ VERMEYİN"
- aciklama: 1-2 kısa cümle (max 25 kelime), informatif, örnek/tüyo verir.
  Örnek: "Konbini ve büyük mağazalarda kart geçerli. Sokak yemeklerinde nakit gerek."
- vurgu_kelimeler: baslık ve açıklamada sarı renkte gösterilecek 1-3 anahtar
  kelime (aynen o kelimeler geçmeli, tam eşleşme).
- arka_plan_anahtarlar: bu karta uygun sahne arka planı için 3-5 İngilizce
  anahtar kelime (metadata.csv'de sahne_ogeleri içinde aranacak). Örnek:
  "convenience store, cashier" veya "subway train, passengers".

JSON şeması:
{{
  "kartlar": [
    {{"baslik":"...", "aciklama":"...", "vurgu_kelimeler":["..."], "arka_plan_anahtarlar":["..."]}}
    // ... {count} adet
  ]
}}

KURALLAR:
- Uydurma sayı/saat/fiyat YASAK — bilmiyorsan yazma
- Klişe/genel tavsiye YASAK ("erken git", "rahat ayakkabı")
- Türkçe kusursuz olmalı
- SADECE JSON döndür"""

    data = oai.chat_json(_STORY_SYSTEM, user_prompt, temperature=0.75, max_tokens=1500)
    kartlar = data.get("kartlar", [])
    if not isinstance(kartlar, list) or not kartlar:
        raise ValueError("GPT çıktısı geçersiz: kartlar listesi boş.")

    # sanitize
    out: list[dict[str, Any]] = []
    for k in kartlar[:count]:
        out.append({
            "baslik": str(k.get("baslik", "")).strip()[:60],
            "aciklama": str(k.get("aciklama", "")).strip()[:220],
            "vurgu_kelimeler": [str(v).strip() for v in (k.get("vurgu_kelimeler") or []) if str(v).strip()][:5],
            "arka_plan_anahtarlar": [str(v).strip() for v in (k.get("arka_plan_anahtarlar") or []) if str(v).strip()][:5],
        })
    return out


# --- 2) Arka plan foto seçici (assets öncelik, frames fallback) ---
_IMG_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def _pick_from_assets(bg_dir: Path, anahtarlar: list[str]) -> Path | None:
    """Kullanıcının yüklediği assets/story_backgrounds/ klasöründen dosya adı
    match'i ile seç. Match yoksa random. Klasör boşsa None."""
    if not bg_dir.exists():
        return None
    all_imgs = [p for p in bg_dir.iterdir()
                if p.is_file() and p.suffix.lower() in _IMG_EXTS]
    if not all_imgs:
        return None

    kws_norm = [_norm(k) for k in anahtarlar if k]
    if kws_norm:
        # dosya adında (basename, uzantısız) anahtar kelime match'i
        scored: list[tuple[int, Path]] = []
        for p in all_imgs:
            name_norm = _norm(p.stem.replace("-", " ").replace("_", " "))
            s = sum(1 for k in kws_norm if k in name_norm)
            if s > 0:
                scored.append((s, p))
        if scored:
            scored.sort(key=lambda x: -x[0])
            # top 3'ten rastgele → çeşitlilik
            top = [p for _, p in scored[:3]]
            return random.choice(top)

    # match yok veya anahtar yok → random
    return random.choice(all_imgs)


def _pick_from_frames(cfg: Config, anahtarlar: list[str]) -> Path | None:
    """Eski davranış: metadata.csv sahne_ogeleri match'i → data/frames/*.jpg."""
    frames_dir = cfg.paths.frames_dir
    if not cfg.paths.metadata_csv.exists():
        candidates = list(frames_dir.glob("*.jpg"))
        return random.choice(candidates) if candidates else None

    with cfg.paths.metadata_csv.open("r", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    kws_norm = [_norm(k) for k in anahtarlar if k]
    scored: list[tuple[int, Path]] = []
    for r in rows:
        if not kws_norm:
            break
        hay = _norm(" ".join([
            r.get("sahne_ogeleri", "") or "",
            r.get("sahne_ozeti", "") or "",
            r.get("sahne_mekan_tahmini", "") or "",
            r.get("mekan_etiketi", "") or "",
        ]))
        s = sum(1 for k in kws_norm if k in hay)
        if s == 0:
            continue
        stem = Path(r.get("dosya_adi", "")).stem
        cand = list(frames_dir.glob(f"{stem}_f*.jpg")) or [frames_dir / f"{stem}.jpg"]
        cand = [p for p in cand if p.exists()]
        if cand:
            scored.append((s, random.choice(cand)))

    if scored:
        scored.sort(key=lambda x: -x[0])
        return random.choice([p for _, p in scored[:3]])

    candidates = list(frames_dir.glob("*.jpg"))
    return random.choice(candidates) if candidates else None


def _pick_background(cfg: Config, anahtarlar: list[str]) -> Path | None:
    """Öncelik: 1) cfg.stories.backgrounds_dir (kullanıcının Japon görselleri)
    2) data/frames/*.jpg (arşiv video frame'leri) — fallback."""
    if cfg.stories and cfg.stories.backgrounds_dir:
        pick = _pick_from_assets(cfg.stories.backgrounds_dir, anahtarlar)
        if pick is not None:
            return pick
    return _pick_from_frames(cfg, anahtarlar)


# --- 3) PIL render ---
def _load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.truetype(FONT_MEDIUM, size)


def _cover_resize(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    """Foto'yu target boyuta CROP-COVER şekilde uydur (aspect ratio bozulmadan)."""
    src_w, src_h = img.size
    src_ratio = src_w / src_h
    tgt_ratio = target_w / target_h
    if src_ratio > tgt_ratio:
        # foto yatay geniş — yüksekliği target'a eşitle, x-crop
        new_h = target_h
        new_w = int(new_h * src_ratio)
        img = img.resize((new_w, new_h), Image.LANCZOS)
        x1 = (new_w - target_w) // 2
        return img.crop((x1, 0, x1 + target_w, target_h))
    else:
        # dikey — genişliği eşitle, y-crop
        new_w = target_w
        new_h = int(new_w / src_ratio)
        img = img.resize((new_w, new_h), Image.LANCZOS)
        y1 = (new_h - target_h) // 2
        return img.crop((0, y1, target_w, y1 + target_h))


def _spaced_width(text: str, font: ImageFont.FreeTypeFont, spacing: int = 0) -> int:
    """Letter-spacing uygulanmış toplam pixel genişliği."""
    if not text:
        return 0
    total = sum((font.getbbox(ch)[2] - font.getbbox(ch)[0]) for ch in text)
    return total + spacing * max(0, len(text) - 1)


def _draw_spaced(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str,
                 font: ImageFont.FreeTypeFont,
                 fill: tuple[int, int, int] | tuple[int, int, int, int],
                 spacing: int = 0) -> None:
    """Letter-spacing ile harfleri tek tek çiz (Pillow'da native letter-spacing yok)."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        cbb = font.getbbox(ch)
        x += (cbb[2] - cbb[0]) + spacing


def _wrap_words(text: str, font: ImageFont.FreeTypeFont, max_width: int,
                letter_spacing: int = 0) -> list[str]:
    """Metni verilen genişliğe göre satırlara böl (letter-spacing'e duyarlı)."""
    words = text.split()
    lines: list[str] = []
    cur: list[str] = []
    for w in words:
        test = " ".join(cur + [w])
        if _spaced_width(test, font, letter_spacing) <= max_width or not cur:
            cur.append(w)
        else:
            lines.append(" ".join(cur))
            cur = [w]
    if cur:
        lines.append(" ".join(cur))
    return lines


def render_from_url(cfg: Config, bg_url: str, bg_id: str, bg_query: str,
                    baslik: str, aciklama: str, vurgu: list[str] | None = None,
                    photographer: str = "",
                    ust_tag: str = "İLGİNÇ BİLGİ!") -> Path:
    """Unsplash'tan gelen bir görseli indir + kart render et. Foto kartın üst
    %55'ine yerleşir, altında siyah bant + başlık + sarı highlight açıklama.
    """
    del vurgu, photographer  # yeni tasarımda vurgu kelimesi yok

    if cfg.stories is None:
        raise RuntimeError("stories config yok")

    import requests as _rq

    bg_dir = cfg.stories.backgrounds_dir
    if bg_dir is None:
        raise RuntimeError("stories.backgrounds_dir yok")
    bg_dir.mkdir(parents=True, exist_ok=True)
    slug_q = _slugify(bg_query)
    bg_path = bg_dir / f"unsplash-{slug_q}-{bg_id}.jpg"
    if not bg_path.exists():
        r = _rq.get(bg_url, timeout=60, stream=True)
        r.raise_for_status()
        with bg_path.open("wb") as fh:
            for chunk in r.iter_content(chunk_size=8192):
                fh.write(chunk)
        log.info(f"  bg indirildi: {bg_path.name} ({bg_path.stat().st_size // 1024} KB)")
    else:
        log.info(f"  bg cache'ten: {bg_path.name}")

    kart = {
        "baslik": baslik.strip(),
        "aciklama": aciklama.strip(),
        "ust_tag": (ust_tag or "İLGİNÇ BİLGİ!").strip(),
    }
    ts = int(time.time())
    out_slug = _slugify(baslik) or "kart"
    out_path = cfg.stories.output_dir / f"{out_slug}_{ts}.jpg"
    render_card(cfg, kart, bg_path, out_path)
    log.info(f"  ✓ kart: {out_path.name}")
    return out_path


def render_card(cfg: Config, kart: dict[str, Any], bg_path: Path | None,
                out_path: Path) -> Path:
    """Kullanıcı referansına göre yeni tasarım:
        [ÜST ~%55]  foto arka plan
        [SOL, sınırda]  küçük SARI "İLGİNÇ BİLGİ!" tag
        [ALT ~%45]  siyah bant:
            - başlık: beyaz Impact, sol-yaslı
            - alt açıklama satırları: her biri sarı highlight bloğu, siyah yazı
            - "DETAYLAR AÇIKLAMADA" küçük sarı tag
            - En altta orta: kırmızı Japon-bayrağı dairesi + handle beyaz yazı
    """
    if cfg.stories is None:
        raise RuntimeError("stories config yok")

    W, H = cfg.stories.width, cfg.stories.height  # 1080 × 1350 (Instagram Post 4:5)
    split_y = int(H * 0.50)   # foto/siyah nominal ayrım (4:5 için biraz daha kompakt)

    # Letter-spacing sabitleri (Impact kalın, sıkı yerleşir — açalım)
    UST_LSP = 2
    TITLE_LSP = 4
    BODY_LSP = 3
    TAG_LSP = 2

    # === Zemin: siyah dolgu; foto split_y'den daha uzun paste, üstüne
    # yumuşak gradient (foto siyaha yavaş yavaş erisin) ===
    bg = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    photo_h = split_y + 70   # foto biraz daha uzansın, gradient içinde erisin
    if bg_path and bg_path.exists():
        try:
            photo = Image.open(bg_path).convert("RGB")
            photo = _cover_resize(photo, W, photo_h)
            bg.paste(photo, (0, 0))
        except Exception as exc:
            log.warning(f"  foto yüklenemedi ({bg_path.name}): {exc}")

    # Gradient overlay: yumuşak foto → siyah geçiş
    grad_start = max(0, split_y - 100)
    grad_end = photo_h
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    span = max(1, grad_end - grad_start)
    for gy in range(grad_start, min(H, grad_end)):
        t = (gy - grad_start) / span
        alpha = int(255 * min(1.0, t ** 1.6))
        gd.line([(0, gy), (W, gy)], fill=(0, 0, 0, alpha))
    bg = Image.alpha_composite(bg, grad)
    d = ImageDraw.Draw(bg)

    baslik = _tr_upper(kart["baslik"].strip())
    aciklama = _tr_upper(kart["aciklama"].strip())
    ust_tag = _tr_upper((kart.get("ust_tag") or "İLGİNÇ BİLGİ!").strip())
    handle = cfg.stories.handle

    padding_x = int(W * 0.05)
    caption_w = W - 2 * padding_x

    # === Üst rozet — gradient bandın içinde, sol tarafta ===
    ust_font = _load_font(FONT_IMPACT, 36)   # 4:5 için biraz küçük
    ust_pad_x, ust_pad_y = 14, 6
    ust_x_text = padding_x + ust_pad_x
    ust_y_text = split_y - 50
    ust_tw = _spaced_width(ust_tag, ust_font, UST_LSP)
    ust_bb = d.textbbox((ust_x_text, ust_y_text), ust_tag, font=ust_font)
    d.rectangle(
        (ust_bb[0] - ust_pad_x, ust_bb[1] - ust_pad_y,
         ust_x_text + ust_tw + ust_pad_x, ust_bb[3] + ust_pad_y),
        fill=COLOR_ACCENT,
    )
    _draw_spaced(d, (ust_x_text, ust_y_text), ust_tag, ust_font,
                 (0, 0, 0, 255), spacing=UST_LSP)

    # === Alt yarı: başlık ===
    title_size = 80   # 96 → 80 (4:5 için)
    title_font = _load_font(FONT_IMPACT, title_size)
    title_lines = _wrap_words(baslik, title_font, caption_w, TITLE_LSP)
    while len(title_lines) > 2 and title_size > 58:
        title_size = int(title_size * 0.92)
        title_font = _load_font(FONT_IMPACT, title_size)
        title_lines = _wrap_words(baslik, title_font, caption_w, TITLE_LSP)
    line_h_title = int(title_size * 1.10)

    # === Alt açıklama — sarı highlight ===
    body_size = 58    # 72 → 58 (4:5 için)
    body_font = _load_font(FONT_IMPACT, body_size)
    hi_pad_x, hi_pad_y = 10, 4
    body_max_w = caption_w - hi_pad_x * 2
    body_lines = _wrap_words(aciklama, body_font, body_max_w, BODY_LSP)
    while len(body_lines) > 4 and body_size > 40:
        body_size = int(body_size * 0.92)
        body_font = _load_font(FONT_IMPACT, body_size)
        body_lines = _wrap_words(aciklama, body_font, body_max_w, BODY_LSP)
    line_h_body = int(body_size * 1.25)

    # === Tag (DETAYLAR AÇIKLAMADA) ===
    tag_size = 26   # 32 → 26
    tag_font = _load_font(FONT_IMPACT, tag_size)
    tag_text = "DETAYLAR AÇIKLAMADA"
    tag_pad_x, tag_pad_y = 8, 3

    # === Layout: gradient sonrası ===
    y = split_y + 50

    for line in title_lines:
        _draw_spaced(d, (padding_x, y), line, title_font,
                     (255, 255, 255, 255), spacing=TITLE_LSP)
        y += line_h_title

    y += 16

    for line in body_lines:
        text_x = padding_x + hi_pad_x
        text_y = y
        # sarı rect için yatay tam genişlik letter-spacing ile
        line_tw = _spaced_width(line, body_font, BODY_LSP)
        line_bb = d.textbbox((text_x, text_y), line, font=body_font)
        d.rectangle(
            (line_bb[0] - hi_pad_x, line_bb[1] - hi_pad_y,
             text_x + line_tw + hi_pad_x, line_bb[3] + hi_pad_y),
            fill=COLOR_ACCENT,
        )
        _draw_spaced(d, (text_x, text_y), line, body_font,
                     (0, 0, 0, 255), spacing=BODY_LSP)
        y += line_h_body

    y += 14

    # DETAYLAR AÇIKLAMADA
    tag_x = padding_x + tag_pad_x
    tag_tw = _spaced_width(tag_text, tag_font, TAG_LSP)
    tag_bb = d.textbbox((tag_x, y), tag_text, font=tag_font)
    d.rectangle(
        (tag_bb[0] - tag_pad_x, tag_bb[1] - tag_pad_y,
         tag_x + tag_tw + tag_pad_x, tag_bb[3] + tag_pad_y),
        fill=COLOR_ACCENT,
    )
    _draw_spaced(d, (tag_x, y), tag_text, tag_font,
                 (0, 0, 0, 255), spacing=TAG_LSP)

    # === Alt orta: kırmızı daire + handle ===
    handle_font = _load_font(FONT_BOLD, 34)
    circle_r = 22
    gap = 12
    hbb = handle_font.getbbox(handle)
    handle_tw = hbb[2] - hbb[0]
    total_w = circle_r * 2 + gap + handle_tw
    row_center_y = H - 60
    start_x = (W - total_w) // 2

    circle_cx = start_x + circle_r
    d.ellipse(
        (circle_cx - circle_r, row_center_y - circle_r,
         circle_cx + circle_r, row_center_y + circle_r),
        fill=(220, 30, 40, 255),
    )

    text_x = start_x + circle_r * 2 + gap
    tmp_bb = d.textbbox((text_x, 0), handle, font=handle_font)
    text_h = tmp_bb[3] - tmp_bb[1]
    text_y = row_center_y - text_h // 2 - tmp_bb[1]
    d.text((text_x, text_y), handle, font=handle_font, fill=(255, 255, 255, 255))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    bg.convert("RGB").save(out_path, "JPEG", quality=92, optimize=True)
    return out_path


# --- Ana runner ---
def run_story_generation(cfg: Config, konu: str, count: int = 3) -> list[dict[str, Any]]:
    """Ana giriş: konu al, 3 kart üret, jpg'lere kaydet + metadata döndür."""
    if cfg.stories is None:
        raise RuntimeError("stories config yok")

    log.info(f"▶ Story kartı üretimi: '{konu}' ({count} varyant)")
    kartlar = generate_pack(cfg, konu, count=count)
    log.info(f"  GPT {len(kartlar)} kart döndürdü")

    ts = int(time.time())
    slug = _slugify(konu)
    out: list[dict[str, Any]] = []
    for i, kart in enumerate(kartlar, 1):
        bg = _pick_background(cfg, kart.get("arka_plan_anahtarlar", []))
        bg_name = bg.name if bg else "(default)"
        log.info(f"  [{i}/{len(kartlar)}] '{kart['baslik'][:40]}' | arka plan: {bg_name}")
        out_path = cfg.stories.output_dir / f"{slug}_{ts}_{i:02d}.jpg"
        try:
            render_card(cfg, kart, bg, out_path)
        except Exception as exc:
            log.error(f"    ✗ render hatası: {exc}")
            continue
        out.append({
            "baslik": kart["baslik"],
            "aciklama": kart["aciklama"],
            "vurgu": kart.get("vurgu_kelimeler", []),
            "arka_plan": bg_name,
            "file": out_path.name,
        })
        log.info(f"    ✓ {out_path.name}")
    return out
