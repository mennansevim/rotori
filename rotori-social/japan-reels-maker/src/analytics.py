"""Analytics — Upload log analizi + Hook A/B test performans takibi.

Veri kaynakları:
    data/instagram_uploads.jsonl  — Instagram'a yüklenen medya (media_id, tarih)
    data/tiktok_uploads.jsonl     — TikTok'a yüklenen videolar
    data/kurgu_planlari/*_final.json — ab_test.hook_variants + impressions
    data/scheduler_queue.json     — planlanan/tamamlanan yayınlar

Kullanım (web API):
    GET /api/analytics/overview   → haftalık yayın sayısı, platform dağılımı
    GET /api/analytics/hooks      → hook varyant tipleri + kazanan analizi
    POST /api/analytics/hooks/{plan_name}/impression  → belirli hook tipine impression kaydı

Not: Bu modül Instagram Graph API istatistiklerini çekmez (Business Login gerektirir).
Mevcut implementasyon upload_log tabanlı lokal analizdir. Graph API entegrasyonu
eklenmek istenirse: src/instagram_graph.py → get_media_insights() fonksiyonu.
"""
from __future__ import annotations

import json
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from src.utils.logging import get_logger

log = get_logger("analytics")


# ---------------------------------------------------------------------------
# Upload log okuma
# ---------------------------------------------------------------------------

def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    """JSONL dosyasını satır satır oku, bozuk satırları atla."""
    if not path.exists():
        return []
    entries = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


def get_instagram_uploads(project_root: Path, uploads_log: str = "data/instagram_uploads.jsonl") -> list[dict[str, Any]]:
    return _read_jsonl(project_root / uploads_log)


def get_tiktok_uploads(project_root: Path, uploads_log: str = "data/tiktok_uploads.jsonl") -> list[dict[str, Any]]:
    return _read_jsonl(project_root / uploads_log)


# ---------------------------------------------------------------------------
# Genel bakış istatistikleri
# ---------------------------------------------------------------------------

def overview(
    project_root: Path,
    ig_log: str = "data/instagram_uploads.jsonl",
    tt_log: str = "data/tiktok_uploads.jsonl",
    scheduler_queue: str = "data/scheduler_queue.json",
    lookback_days: int = 30,
) -> dict[str, Any]:
    """Son `lookback_days` günlük yayın istatistikleri.

    Returns:
        total_ig: Instagram'a yüklenen toplam medya sayısı
        total_tiktok: TikTok'a yüklenen toplam video sayısı
        last_30d_ig: Son 30 gün Instagram
        last_30d_tiktok: Son 30 gün TikTok
        daily_ig: {"YYYY-MM-DD": count} son 30 gün
        daily_tiktok: {"YYYY-MM-DD": count} son 30 gün
        avg_per_week_ig: haftalık ortalama Instagram
        pending_queue: kuyruktaki bekleyen reels sayısı
        recommended_frequency: hedef haftalık yayın sayısı önerisi
    """
    ig_entries = get_instagram_uploads(project_root, ig_log)
    tt_entries = get_tiktok_uploads(project_root, tt_log)

    now = datetime.now()
    cutoff = now - timedelta(days=lookback_days)

    def _filter_recent(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
        result = []
        for e in entries:
            ts = e.get("uploaded_at", "")
            try:
                if datetime.fromisoformat(ts) >= cutoff:
                    result.append(e)
            except (ValueError, TypeError):
                pass
        return result

    recent_ig = _filter_recent(ig_entries)
    recent_tt = _filter_recent(tt_entries)

    # Günlük dağılım
    daily_ig: dict[str, int] = defaultdict(int)
    for e in recent_ig:
        day = e.get("uploaded_at", "")[:10]
        if day:
            daily_ig[day] += 1

    daily_tt: dict[str, int] = defaultdict(int)
    for e in recent_tt:
        day = e.get("uploaded_at", "")[:10]
        if day:
            daily_tt[day] += 1

    # Haftalık ortalama
    weeks = max(lookback_days / 7, 1)
    avg_ig = round(len(recent_ig) / weeks, 1)

    # Scheduler kuyruğu
    pending_count = 0
    sched_path = project_root / scheduler_queue
    if sched_path.exists():
        try:
            queue = json.loads(sched_path.read_text(encoding="utf-8"))
            pending_count = sum(1 for i in queue if i.get("status") == "pending")
        except Exception:
            pass

    # Öneri: 1 milyon hedefi için haftada 5-7 Reels gerekiyor
    recommended = 7
    gap = max(0, recommended - avg_ig)
    if gap == 0:
        recommendation = "🟢 Frekans hedefte! Devam et."
    elif gap <= 2:
        recommendation = f"🟡 Haftada {gap:.0f} Reels daha ekle. Hedef: 7/hafta."
    else:
        recommendation = f"🔴 Haftada {gap:.0f} Reels daha ekle. Şu an: {avg_ig}/hafta, hedef: 7/hafta."

    return {
        "total_ig": len(ig_entries),
        "total_tiktok": len(tt_entries),
        f"last_{lookback_days}d_ig": len(recent_ig),
        f"last_{lookback_days}d_tiktok": len(recent_tt),
        "daily_ig": dict(sorted(daily_ig.items())),
        "daily_tiktok": dict(sorted(daily_tt.items())),
        "avg_per_week_ig": avg_ig,
        "pending_queue": pending_count,
        "recommended_weekly": recommended,
        "recommendation": recommendation,
        "lookback_days": lookback_days,
    }


# ---------------------------------------------------------------------------
# Hook A/B Test analizi
# ---------------------------------------------------------------------------

def hook_ab_analysis(plans_dir: Path) -> dict[str, Any]:
    """Tüm final.json'lardan hook varyant performansını topla.

    Returns:
        by_type: {hook_tipi: {total_impressions, plans_count, hooks: [str]}}
        winner: en çok impression alan tip
        plans: per-plan detaylar
    """
    by_type: dict[str, dict[str, Any]] = {}
    plans_detail = []

    for final_path in sorted(plans_dir.glob("*_final.json")):
        try:
            data = json.loads(final_path.read_text(encoding="utf-8"))
        except Exception:
            continue

        ab = data.get("ab_test", {})
        variants = ab.get("hook_variants", [])
        impressions = ab.get("impressions", {})
        active = ab.get("active_variant")

        if not variants:
            continue

        plan_detail = {
            "plan": final_path.stem,
            "mekan": data.get("mekan_etiketi", ""),
            "variants": variants,
            "active_variant": active,
            "impressions": impressions,
        }
        plans_detail.append(plan_detail)

        for v in variants:
            tip = v.get("tip", "unknown")
            hook_text = v.get("hook", "")
            imp = impressions.get(tip, 0)
            if tip not in by_type:
                by_type[tip] = {"total_impressions": 0, "plans_count": 0, "hooks": []}
            by_type[tip]["total_impressions"] += imp
            by_type[tip]["plans_count"] += 1
            by_type[tip]["hooks"].append(hook_text)

    # Winner: en yüksek ortalama impression
    winner = None
    best_avg = -1
    for tip, stats in by_type.items():
        avg = stats["total_impressions"] / max(stats["plans_count"], 1)
        stats["avg_impressions"] = round(avg, 1)
        if avg > best_avg:
            best_avg = avg
            winner = tip

    if not by_type:
        return {
            "by_type": {},
            "winner": None,
            "plans_count": 0,
            "plans": [],
            "message": "Henüz A/B test verisi yok. step3_dify.py çalıştıktan sonra final.json'lara hook_variants eklenir.",
        }

    return {
        "by_type": by_type,
        "winner": winner,
        "plans_count": len(plans_detail),
        "plans": plans_detail[:20],   # max 20 plan döndür
    }


def record_hook_impression(
    plans_dir: Path,
    plan_name: str,
    hook_tip: str,
) -> dict[str, Any]:
    """Belirli bir plan için hook tipine impression kaydı ekle.

    plan_name: final.json dosya adının stem'i (uzantısız)
    hook_tip: "merak" | "sayi_gercek" | "karsilastirma" | "hata_uyarisi"
    """
    # _final.json veya _final ile biten dosyayı bul
    candidates = [
        plans_dir / f"{plan_name}_final.json",
        plans_dir / f"{plan_name}.json",
    ]
    final_path = next((p for p in candidates if p.exists()), None)
    if not final_path:
        raise FileNotFoundError(f"Plan bulunamadı: {plan_name}")

    data = json.loads(final_path.read_text(encoding="utf-8"))
    ab = data.setdefault("ab_test", {"hook_variants": [], "active_variant": None, "impressions": {}})
    ab.setdefault("impressions", {})
    ab["impressions"][hook_tip] = ab["impressions"].get(hook_tip, 0) + 1

    # En çok impression alan tipi active_variant yap
    if ab["impressions"]:
        ab["active_variant"] = max(ab["impressions"], key=lambda k: ab["impressions"][k])

    final_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    log.info(f"Impression kaydedildi: {plan_name} / {hook_tip} → {ab['impressions'][hook_tip]}")
    return {"plan": plan_name, "tip": hook_tip, "total": ab["impressions"][hook_tip]}


# ---------------------------------------------------------------------------
# Platform karşılaştırma
# ---------------------------------------------------------------------------

def platform_comparison(
    project_root: Path,
    ig_log: str = "data/instagram_uploads.jsonl",
    tt_log: str = "data/tiktok_uploads.jsonl",
) -> dict[str, Any]:
    """Instagram vs TikTok yayın karşılaştırması.

    Her platform için: toplam yayın, ilk yayın tarihi, son yayın tarihi,
    en aktif haftalar.
    """
    def _platform_stats(entries: list[dict[str, Any]], platform: str) -> dict[str, Any]:
        if not entries:
            return {"platform": platform, "total": 0, "first": None, "last": None, "weekly": {}}
        dates = []
        for e in entries:
            ts = e.get("uploaded_at", "")
            try:
                dates.append(datetime.fromisoformat(ts))
            except (ValueError, TypeError):
                pass
        dates.sort()
        weekly: dict[str, int] = defaultdict(int)
        for d in dates:
            week = d.strftime("%Y-W%W")
            weekly[week] += 1
        return {
            "platform": platform,
            "total": len(entries),
            "first": dates[0].strftime("%Y-%m-%d") if dates else None,
            "last": dates[-1].strftime("%Y-%m-%d") if dates else None,
            "weekly": dict(sorted(weekly.items())[-12:]),   # son 12 hafta
        }

    ig = _platform_stats(get_instagram_uploads(project_root, ig_log), "instagram")
    tt = _platform_stats(get_tiktok_uploads(project_root, tt_log), "tiktok")

    return {"instagram": ig, "tiktok": tt}
