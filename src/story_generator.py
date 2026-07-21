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

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from src.config import Config
from src.utils.logging import get_logger

log = get_logger("story")


# --- Yazı stili sabitleri (klasik/tutarlı) ---
COLOR_TEXT = (255, 255, 255)          # beyaz gövde
COLOR_ACCENT = (255, 214, 61)         # altın sarı (kullanıcı örneklerinden)
COLOR_SHADOW = (0, 0, 0, 180)         # koyu shadow
COLOR_HANDLE_BG = (0, 0, 0, 200)      # handle badge arka planı
COLOR_HANDLE_TEXT = (255, 255, 255)   # handle text
GRADIENT_ALPHA_TOP = 0                # üstte transparan
GRADIENT_ALPHA_BOTTOM = 235           # altta neredeyse opak

FONT_IMPACT = "/System/Library/Fonts/Supplemental/Impact.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_MEDIUM = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

_ANAHTAR_RE = re.compile(r"[a-zçğıöşü0-9]+", re.IGNORECASE)


def _norm(text: str) -> str:
    text = (text or "").lower()
    for a, b in {"ç":"c","ğ":"g","ı":"i","ö":"o","ş":"s","ü":"u","İ":"i"}.items():
        text = text.replace(a, b)
    return "".join(c for c in unicodedata.normalize("NFKD", text)
                   if not unicodedata.combining(c))


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


# --- 2) Arşivden arka plan foto seçici ---
def _pick_background(cfg: Config, anahtarlar: list[str]) -> Path | None:
    """metadata.csv'deki sahne_ogeleri'nde en yüksek puan alan videonun frame'ini
    döndür. anahtarlar boş veya match yoksa random frame."""
    frames_dir = cfg.paths.frames_dir
    if not cfg.paths.metadata_csv.exists():
        # metadata yok: frames'ten rastgele
        candidates = list(frames_dir.glob("*.jpg"))
        return random.choice(candidates) if candidates else None

    with cfg.paths.metadata_csv.open("r", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    # anahtarları normalize et
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
        # multi-frame varsa random, yoksa tek frame
        cand = list(frames_dir.glob(f"{stem}_f*.jpg")) or [frames_dir / f"{stem}.jpg"]
        cand = [p for p in cand if p.exists()]
        if cand:
            scored.append((s, random.choice(cand)))

    if scored:
        scored.sort(key=lambda x: -x[0])
        # top 3 arasında rastgele (çeşitlilik)
        return random.choice([p for _, p in scored[:3]])

    # fallback: rastgele frame
    candidates = list(frames_dir.glob("*.jpg"))
    return random.choice(candidates) if candidates else None


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


def _draw_gradient(img: Image.Image, gradient_top_frac: float = 0.35) -> Image.Image:
    """Alt %65'e karanlık gradient (metnin okunması için)."""
    W, H = img.size
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(grad)
    top_y = int(H * gradient_top_frac)
    span = H - top_y
    for y in range(top_y, H):
        t = (y - top_y) / span
        alpha = int(GRADIENT_ALPHA_TOP + (GRADIENT_ALPHA_BOTTOM - GRADIENT_ALPHA_TOP) * (t ** 1.5))
        d.line([(0, y), (W, y)], fill=(0, 0, 0, alpha))
    return Image.alpha_composite(img.convert("RGBA"), grad)


def _wrap_words(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    """Metni verilen genişliğe göre satırlara böl."""
    words = text.split()
    lines: list[str] = []
    cur: list[str] = []
    for w in words:
        test = " ".join(cur + [w])
        bbox = font.getbbox(test)
        if (bbox[2] - bbox[0]) <= max_width or not cur:
            cur.append(w)
        else:
            lines.append(" ".join(cur))
            cur = [w]
    if cur:
        lines.append(" ".join(cur))
    return lines


def _text_with_shadow(img: Image.Image, xy: tuple[int, int], text: str,
                     font: ImageFont.FreeTypeFont, fill: tuple[int, int, int],
                     stroke_w: int = 3, anchor: str = "mm") -> None:
    """Text + shadow draw. anchor 'mm' = ortalanmış."""
    d = ImageDraw.Draw(img)
    # gölge (2px offset)
    d.text((xy[0] + 3, xy[1] + 3), text, font=font, fill=(0, 0, 0, 180),
           anchor=anchor, stroke_width=stroke_w, stroke_fill=(0, 0, 0))
    d.text(xy, text, font=font, fill=fill, anchor=anchor,
           stroke_width=stroke_w, stroke_fill=(0, 0, 0))


def _draw_line_with_accents(img: Image.Image, line: str, y: int, W: int,
                            font: ImageFont.FreeTypeFont, vurgu_norm: set[str],
                            stroke_w: int = 3) -> None:
    """Bir satırdaki kelimeleri tek tek çiz — vurgu olanlar sarı, diğerleri beyaz.
    Satırın toplam genişliğine göre center'la."""
    words = line.split()
    # gap width
    space_bbox = font.getbbox(" ")
    space_w = space_bbox[2] - space_bbox[0]
    # kelime genişliklerini ölç
    word_widths = []
    for w in words:
        bb = font.getbbox(w)
        word_widths.append(bb[2] - bb[0])
    total_w = sum(word_widths) + space_w * max(0, len(words) - 1)
    x = (W - total_w) // 2

    d = ImageDraw.Draw(img)
    for i, w in enumerate(words):
        # normalize edip vurgu setinde mi kontrol
        w_clean = re.sub(r"[^\wçğıöşüÇĞİÖŞÜ]", "", w).lower()
        w_norm = _norm(w_clean)
        is_accent = any(vn == w_norm or (vn and vn in w_norm) for vn in vurgu_norm)
        color = COLOR_ACCENT if is_accent else COLOR_TEXT
        # shadow
        d.text((x + 3, y + 3), w, font=font, fill=(0, 0, 0),
               stroke_width=stroke_w, stroke_fill=(0, 0, 0))
        d.text((x, y), w, font=font, fill=color,
               stroke_width=stroke_w, stroke_fill=(0, 0, 0))
        x += word_widths[i] + space_w


def _draw_handle_badge(img: Image.Image, handle: str, W: int, H: int) -> None:
    """Alt orta konumda handle badge — pill şeklinde."""
    d = ImageDraw.Draw(img)
    font = _load_font(FONT_MEDIUM, 30)
    bb = font.getbbox(handle)
    tw = bb[2] - bb[0]
    th = bb[3] - bb[1]
    pad_x, pad_y = 22, 12
    badge_w = tw + pad_x * 2
    badge_h = th + pad_y * 2
    bx = (W - badge_w) // 2
    by = H - 90
    # arka plan yuvarlak dikdörtgen
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle((bx, by, bx + badge_w, by + badge_h),
                         radius=badge_h // 2, fill=COLOR_HANDLE_BG)
    img.alpha_composite(overlay)
    d.text((W // 2, by + badge_h // 2), handle, font=font,
           fill=COLOR_HANDLE_TEXT, anchor="mm")


def render_card(cfg: Config, kart: dict[str, Any], bg_path: Path | None,
                out_path: Path) -> Path:
    """Bir kartı renderla + jpg olarak kaydet."""
    if cfg.stories is None:
        raise RuntimeError("stories config yok")

    W, H = cfg.stories.width, cfg.stories.height

    # arka plan
    if bg_path and bg_path.exists():
        try:
            bg = Image.open(bg_path).convert("RGB")
            bg = _cover_resize(bg, W, H)
        except Exception as exc:
            log.warning(f"  arka plan yüklenemedi ({bg_path.name}): {exc}, siyah fallback")
            bg = Image.new("RGB", (W, H), (26, 30, 40))
    else:
        # koyu gradient default
        bg = Image.new("RGB", (W, H), (26, 30, 40))

    # gradient overlay
    bg = _draw_gradient(bg, gradient_top_frac=0.30)

    # metin: başlık + açıklama
    baslik = kart["baslik"].upper()
    aciklama = kart["aciklama"]
    vurgu = kart.get("vurgu_kelimeler", [])
    vurgu_norm = {_norm(v).replace(" ", "") for v in vurgu}
    # ayrıca çok kelimeli vurguları da her kelime bazında ekleyelim
    for v in vurgu:
        for word in v.split():
            vurgu_norm.add(_norm(word).replace(" ", ""))

    # başlık font size — uzun başlıklar için otomatik küçült
    base_title = 96
    max_word_len = max((len(w) for w in baslik.split()), default=0)
    if max_word_len >= 14 or len(baslik) > 40:
        title_size = int(base_title * 0.72)
    elif max_word_len >= 11 or len(baslik) > 28:
        title_size = int(base_title * 0.85)
    else:
        title_size = base_title
    title_font = _load_font(FONT_IMPACT, title_size)

    # açıklama font size
    subtitle_size = 40
    subtitle_font = _load_font(FONT_MEDIUM, subtitle_size)

    caption_w = int(W * 0.85)

    # başlık satırlarını hazırla
    title_lines = _wrap_words(baslik, title_font, caption_w)
    subtitle_lines = _wrap_words(aciklama, subtitle_font, caption_w)

    # y-layout: alt %55'e yerleştir. Başlık üstte, açıklama altta
    line_h_title = int(title_size * 1.1)
    line_h_sub = int(subtitle_size * 1.35)
    total_title_h = line_h_title * len(title_lines)
    total_sub_h = line_h_sub * len(subtitle_lines)
    gap = 40

    # başlığın merkez y'si — H'nin %65'i civarında (alt-ortada)
    base_y = int(H * 0.63)
    title_start_y = base_y - total_title_h // 2 - gap // 2 - total_sub_h // 2

    y = title_start_y
    for line in title_lines:
        _draw_line_with_accents(bg, line, y, W, title_font, vurgu_norm, stroke_w=5)
        y += line_h_title

    y += gap
    for line in subtitle_lines:
        _draw_line_with_accents(bg, line, y, W, subtitle_font, vurgu_norm, stroke_w=2)
        y += line_h_sub

    # handle badge
    _draw_handle_badge(bg, cfg.stories.handle, W, H)

    # JPG olarak kaydet
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
