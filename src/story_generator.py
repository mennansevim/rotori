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


# --- Renk sabitleri ---
COLOR_ACCENT = (255, 214, 61)   # altın sarı (highlight blokları, üst rozet)

FONT_IMPACT = "/System/Library/Fonts/Supplemental/Impact.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_MEDIUM = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
# Oswald variable font (OFL, ticari OK) — story kartı başlık/açıklama.
# Referans tasarımdaki font. Ağırlıklar: ExtraLight/Light/Regular/Medium/SemiBold/Bold
FONT_OSWALD = str(Path(__file__).resolve().parent.parent / "assets/fonts/Oswald-VariableFont.ttf")
# ChunkFive (OFL, The League of Moveable Type) — ağır slab display, wordmark için
FONT_CHUNK = str(Path(__file__).resolve().parent.parent / "assets/fonts/ChunkFive.otf")

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


def _load_oswald(size: int, weight: str = "SemiBold") -> ImageFont.FreeTypeFont:
    """Oswald variable font'u verilen ağırlıkta yükle (SemiBold/Medium/Bold…).
    Font yoksa Impact'e düşer. Auto-shrink döngüsünde her boyut için yeni
    obje döner (variation her seferinde set edilir)."""
    try:
        f = ImageFont.truetype(FONT_OSWALD, size)
        try:
            f.set_variation_by_name(weight)
        except (OSError, ValueError):
            pass
        return f
    except OSError:
        return _load_font(FONT_IMPACT, size)


def _load_chunk(size: int) -> ImageFont.FreeTypeFont:
    """ChunkFive slab display font — wordmark büyük kelimesi için."""
    try:
        return ImageFont.truetype(FONT_CHUNK, size)
    except OSError:
        return _load_font(FONT_IMPACT, size)


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
                    ust_tag: str = "GEZİ DEFTERİ",
                    style: str = "style2") -> Path:
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
        "ust_tag": (ust_tag or "GEZİ DEFTERİ").strip(),
    }
    ts = int(time.time())
    # başlık alanı kaldırıldı — slug'ı açıklamadan üret (başlık boşsa)
    # Not: _slugify("") "story" döndürür (falsy değil), o yüzden strip ile kontrol
    out_slug = _slugify(baslik if baslik.strip() else aciklama)
    out_path = cfg.stories.output_dir / f"{out_slug}_{ts}.jpg"
    # style2, kullanıcının eski JAPONYA / RÜYASI wordmark tasarımıdır ve
    # özellikle korunur. Yeni üretimler varsayılan olarak style2 kullanır.
    if style == "style2":
        render_card(cfg, kart, bg_path, out_path)
    else:
        render_card_style1(cfg, kart, bg_path, out_path, bg_query=bg_query)
    log.info(f"  ✓ kart: {out_path.name}")
    return out_path


# --- yeni tasarım yardımcıları (Explore-Japan-News stili) ---
_FLAG_RED = (188, 0, 45, 255)   # resmî Hinomaru kırmızısı (#BC002D)


def _draw_line_center(d: ImageDraw.ImageDraw, cx: int, y_top: int, text: str,
                      font: ImageFont.FreeTypeFont, fill, spacing: int = 0,
                      shadow=None) -> None:
    """Metni yatayda cx'e ortalayarak (letter-spacing ile) çiz.
    shadow: (fill, (ox, oy)) verilirse önce offsetli gölge çizilir."""
    w = _spaced_width(text, font, spacing)
    x = cx - w // 2
    if shadow is not None:
        sfill, (ox, oy) = shadow
        _draw_spaced(d, (x + ox, y_top + oy), text, font, sfill, spacing)
    _draw_spaced(d, (x, y_top), text, font, fill, spacing)


def _draw_flag_badge(img: Image.Image, cx: int, cy: int, r: int) -> None:
    """Sol üst dairesel Hinomaru rozeti: yumuşak gölge + beyaz alan + ince
    halka + kırmızı disk. Görselin parlak bölgesinde bile ayrışsın diye
    gölge + halka var."""
    W, H = img.size
    # 1) yumuşak gölge (ayrı katman + blur)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse((cx - r + 4, cy - r + 9, cx + r + 4, cy + r + 9), fill=(0, 0, 0, 130))
    shadow = shadow.filter(ImageFilter.GaussianBlur(11))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)
    # 2) beyaz alan (bayrak zemini)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 255))
    # 3) ince halka
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(228, 228, 232, 255), width=3)
    # 4) kırmızı disk (Hinomaru; çap ≈ %60)
    rr = int(r * 0.60)
    d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=_FLAG_RED)


def _prepare_wordmark(img_w: int) -> dict[str, Any]:
    """Wordmark lockup — referanstaki JAPAN/NEWS gibi:
        büyük 'JAPONYA' (ChunkFive slab) + hemen altında küçük, ALTIN,
        geniş harf-aralıklı 'RÜYASI'. RÜYASI'nin harf aralığı, tam JAPONYA
        genişliğine oturacak şekilde otomatik hesaplanır (optik hizalama).
    Ölçüler görsel bbox'a göre → satırlar sıkı ve dengeli oturur."""
    big_text, sub_text = "JAPONYA", "RÜYASI"
    big_font = _load_chunk(72)
    sub_font = _load_oswald(30, "SemiBold")
    big_sp = 1

    big_w = _spaced_width(big_text, big_font, big_sp)
    # RÜYASI dar kalsın (başlıktan küçük) — JAPONYA'nın ~%52'si genişlik hedefi,
    # harf aralığı makul sınırda [4, 16]. Tam genişliğe YAYMA (çok geniş durur).
    sub_natural = _spaced_width(sub_text, sub_font, 0)
    target_sub_w = int(big_w * 0.52)
    sub_sp = int((target_sub_w - sub_natural) / max(1, len(sub_text) - 1))
    sub_sp = max(4, min(16, sub_sp))

    big_bb = big_font.getbbox(big_text)     # görsel dikey sınırlar
    sub_bb = sub_font.getbbox(sub_text)
    big_vh = big_bb[3] - big_bb[1]
    sub_vh = sub_bb[3] - sub_bb[1]
    gap = 3   # RÜYASI JAPONYA'ya çok yakın otursun (referanstaki NEWS proximity)
    return {"big_font": big_font, "sub_font": sub_font,
            "big_text": big_text, "sub_text": sub_text,
            "big_sp": big_sp, "sub_sp": sub_sp,
            "big_bb": big_bb, "sub_bb": sub_bb,
            "big_vh": big_vh, "sub_vh": sub_vh, "gap": gap,
            "h": big_vh + gap + sub_vh}


def _draw_wordmark(img: Image.Image, cx: int, y_top: int, wm: dict[str, Any]) -> None:
    """Wordmark'ı y_top'tan itibaren çiz — görsel bbox offset'iyle sıkı stack."""
    d = ImageDraw.Draw(img)
    y = y_top
    # büyük JAPONYA (beyaz, hafif gölge) — görsel tepe y_top'a otursun
    _draw_line_center(d, cx, y - wm["big_bb"][1], wm["big_text"], wm["big_font"],
                      (255, 255, 255, 255), spacing=wm["big_sp"],
                      shadow=((0, 0, 0, 150), (0, 3)))
    y += wm["big_vh"] + wm["gap"]
    # küçük RÜYASI (altın, geniş aralık)
    _draw_line_center(d, cx, y - wm["sub_bb"][1], wm["sub_text"], wm["sub_font"],
                      COLOR_ACCENT, spacing=wm["sub_sp"])


def render_card_style1(cfg: Config, kart: dict[str, Any], bg_path: Path | None,
                       out_path: Path, bg_query: str = "") -> Path:
    """Stil 1 — fotoğraf üstü editöryel kart.

    Üstte tam kadraj fotoğraf, altta yumuşak siyah geçiş; sarı kategori,
    serif başlık ve okunaklı kısa açıklama. Bu, yeni içerik stüdyosunun
    varsayılan stilidir.
    """
    if cfg.stories is None:
        raise RuntimeError("stories config yok")
    W, H = cfg.stories.width, cfg.stories.height
    bg = Image.new("RGBA", (W, H), (10, 11, 10, 255))
    if bg_path and bg_path.exists():
        try:
            photo = Image.open(bg_path).convert("RGB")
            bg.paste(_cover_resize(photo, W, H), (0, 0))
        except Exception as exc:
            log.warning(f"  foto yüklenemedi ({bg_path.name}): {exc}")

    aciklama = kart["aciklama"].strip()
    title = (kart.get("baslik") or bg_query or "Japonya").strip()
    # Haber başlıkları uzun olabilir; kartta kısa, net bir başlık göster.
    if len(title) > 34:
        title = " ".join(title.split()[:5]).rstrip(".,:;!?…")
    tag = (kart.get("ust_tag") or "JAPONYA RÜYASI").strip().upper()

    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    start = int(H * 0.38)
    for y in range(start, H):
        t = (y - start) / max(1, H - start)
        od.line([(0, y), (W, y)], fill=(0, 0, 0, int(245 * (t ** 1.25))))
    bg = Image.alpha_composite(bg, overlay)
    d = ImageDraw.Draw(bg)

    pad = int(W * 0.10)
    content_w = W - 2 * pad
    tag_font = _load_oswald(28, "SemiBold")
    title_font = _load_chunk(72)
    body_size = 40
    body_font = _load_oswald(body_size, "Medium")
    body_lines = _wrap_words(aciklama, body_font, content_w, 0)
    while len(body_lines) > 5 and body_size > 28:
        body_size -= 2
        body_font = _load_oswald(body_size, "Medium")
        body_lines = _wrap_words(aciklama, body_font, content_w, 0)

    body_h = len(body_lines) * int(body_size * 1.28)
    title_bb = title_font.getbbox(title)
    title_h = title_bb[3] - title_bb[1]
    tag_h = tag_font.getbbox(tag)[3] - tag_font.getbbox(tag)[1]
    gap = 22
    block_h = tag_h + 22 + title_h + 22 + body_h
    y = max(int(H * 0.53), H - int(H * 0.09) - block_h)
    _draw_spaced(d, (pad, y - tag_font.getbbox(tag)[1]), tag, tag_font,
                 COLOR_ACCENT, spacing=5)
    y += tag_h + gap
    d.text((pad, y - title_bb[1]), title, font=title_font,
           fill=(250, 249, 245, 255), stroke_width=1, stroke_fill=(0, 0, 0, 130))
    y += title_h + gap
    for line in body_lines:
        d.text((pad, y), line, font=body_font,
               fill=(242, 242, 238, 255), stroke_width=1, stroke_fill=(0, 0, 0, 100))
        y += int(body_size * 1.28)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    bg.convert("RGB").save(out_path, "JPEG", quality=92, optimize=True)
    return out_path


def render_card(cfg: Config, kart: dict[str, Any], bg_path: Path | None,
                out_path: Path) -> Path:
    """Explore-Japan-News stili tasarım:
        - Tam-kadraj (full-bleed) arka plan foto
        - Altta foto → siyah YUMUŞAK gradient; metnin hemen üstünde tam
          siyaha ulaşır → yazı her zaman okunur
        - Ortalı wordmark: JAPONYA (ChunkFive) / RÜYASI (altın)
        - Ana metin (açıklama): Oswald Medium, ortalı — tek metin bloğu
      (Not: sol üst bayrak rozeti + ayrı büyük başlık kaldırıldı —
       kullanıcı isteği; referanstaki gibi wordmark + tek metin.)
    """
    if cfg.stories is None:
        raise RuntimeError("stories config yok")

    W, H = cfg.stories.width, cfg.stories.height  # 1080 × 1350 (Instagram Post 4:5)
    cx = W // 2
    padding_x = int(W * 0.055)
    content_w = W - 2 * padding_x

    aciklama = _tr_upper(kart["aciklama"].strip())

    # === 1) Tam-kadraj foto ===
    bg = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    if bg_path and bg_path.exists():
        try:
            photo = Image.open(bg_path).convert("RGB")
            photo = _cover_resize(photo, W, H)
            bg.paste(photo, (0, 0))
        except Exception as exc:
            log.warning(f"  foto yüklenemedi ({bg_path.name}): {exc}")

    # === 2) Metin bloğunu ölç (gradient konumu + dikey yerleşim için) ===
    # Oswald condensed — letter-spacing az yeter
    BODY_LSP = 1
    # Ana metin (açıklama) — Oswald Medium; 5 satırdan fazlaysa küçült
    body_size = 48
    body_font = _load_oswald(body_size, "Medium")
    body_lines = _wrap_words(aciklama, body_font, content_w, BODY_LSP)
    while len(body_lines) > 5 and body_size > 32:
        body_size -= 3
        body_font = _load_oswald(body_size, "Medium")
        body_lines = _wrap_words(aciklama, body_font, content_w, BODY_LSP)
    body_line_h = int(body_size * 1.28)
    body_h = body_line_h * len(body_lines)

    # Wordmark (JAPONYA / RÜYASI) — metnin üstünde
    wm = _prepare_wordmark(W)
    wm_h = wm["h"]

    gap_wm_body, bottom_pad = 42, 62
    block_h = wm_h + gap_wm_body + body_h
    block_top = H - bottom_pad - block_h
    # metin çok uzunsa fotoyu tamamen yeme — en az ~%28 foto kalsın
    block_top = max(block_top, int(H * 0.28))

    # === 3) Yumuşak gradient — foto → siyah, metnin üstünde tam siyaha ulaşır ===
    grad_full_y = max(1, block_top - 30)                     # buradan aşağısı tam siyah
    grad_start_y = max(int(H * 0.20), grad_full_y - 360)     # 360px hafif/uzun geçiş
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    span = max(1, grad_full_y - grad_start_y)
    for gy in range(grad_start_y, H):
        if gy >= grad_full_y:
            alpha = 255
        else:
            t = (gy - grad_start_y) / span
            alpha = int(255 * (t ** 1.35))   # daha yumuşak eğri
        gd.line([(0, gy), (W, gy)], fill=(0, 0, 0, alpha))
    bg = Image.alpha_composite(bg, grad)
    d = ImageDraw.Draw(bg)

    # === 4) Bottom-anchored blok: wordmark → ana metin ===
    y = block_top
    _draw_wordmark(bg, cx, y, wm)
    d = ImageDraw.Draw(bg)
    y += wm_h + gap_wm_body

    for line in body_lines:
        _draw_line_center(d, cx, y, line, body_font, (238, 238, 242, 255),
                          spacing=BODY_LSP, shadow=((0, 0, 0, 130), (0, 2)))
        y += body_line_h

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
