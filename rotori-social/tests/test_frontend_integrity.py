"""Frontend bütünlük testleri — studio.html'in runtime'da patlamamasını garanti eder.

Bu testler, JS'in çalışma anında `Cannot set properties of null` gibi hatalar
vermesine yol açan sınıf hatalarını STATİK olarak yakalar:

  1. `getElementById("X")` çağrılan her ID, HTML'de `id="X"` olarak var mı?
  2. `querySelector("#X")` ile hedeflenen ID'ler var mı?
  3. `data-page` / `data-go` ile gidilen her sayfa `<section id=...>` olarak var mı?
  4. Inline `onclick="fnName(...)"` çağrılan her fonksiyon JS'te tanımlı mı?
  5. Tüm <script> blokları dengeli (kaba brace/paren dengesi) mi?

Amaç: bir daha "bu kısım çalışmıyor" hatası UI'da değil, burada CI'da yakalansın.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

STUDIO = Path(__file__).resolve().parent.parent / "src" / "web" / "static" / "studio.html"


@pytest.fixture(scope="module")
def html() -> str:
    assert STUDIO.exists(), f"studio.html bulunamadı: {STUDIO}"
    return STUDIO.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def scripts(html: str) -> str:
    """Tüm <script>…</script> içeriklerini birleştirir."""
    blocks = re.findall(r"<script[^>]*>(.*?)</script>", html, re.DOTALL)
    return "\n".join(blocks)


@pytest.fixture(scope="module")
def defined_ids(html: str) -> set[str]:
    """HTML'de tanımlı tüm id="..." değerleri."""
    return set(re.findall(r'\bid="([^"]+)"', html))


# ---------------------------------------------------------------------------
# 1) getElementById bütünlüğü — asıl yaşanan hatanın testi
# ---------------------------------------------------------------------------
def test_dangerous_getElementById_targets_exist(scripts: str, defined_ids: set[str]):
    """HEMEN dereference edilen `getElementById("X").foo` hedefleri var olmalı.

    `document.getElementById("navCountQueue").textContent = ...` gibi, sonucu
    anında `.` ile kullanılan çağrılar null ise runtime'da PATLAR. Bu testin
    yakaladığı asıl hata sınıfı budur.

    Not: `const b = getElementById("x")` veya `getElementById("x") || …` gibi
    savunmacı kullanımlar güvenlidir; onlar `test_guarded_getElementById_*`
    ile ayrıca denetlenir.
    """
    # getElementById("X") hemen ardından . ile dereference ediliyorsa tehlikeli
    dangerous = set(re.findall(
        r'getElementById\(\s*["\']([^"\']+)["\']\s*\)\s*\.', scripts
    ))
    missing = sorted(dangerous - defined_ids)
    assert not missing, (
        "studio.html'de `getElementById(\"X\").foo` ile ANINDA kullanılan ama "
        f"HTML'de OLMAYAN id'ler (runtime'da null hatası verir): {missing}"
    )


def test_guarded_getElementById_targets_known(scripts: str, defined_ids: set[str]):
    """Savunmacı erişilen (guard'lı) getElementById hedefleri: ya HTML'de var,
    ya da bilinçli-opsiyonel allowlist'te olmalı.

    Böylece 'JS'te kalmış ama tamamen ölü' referanslar da fark edilir; ama
    guard'lı oldukları için build'i kırmazlar — allowlist ile belgelenir.
    """
    referenced = set(re.findall(
        r'getElementById\(\s*["\']([^"\']+)["\']\s*\)', scripts
    ))
    # Bilinçli opsiyonel / geriye-dönük fallback id'ler (hepsi guard'lı erişilir)
    OPTIONAL = {"imgAiVisionBtn", "regenTextBtn", "regenCaptionBtn", "libRefresh"}
    unknown = sorted(referenced - defined_ids - OPTIONAL)
    assert not unknown, (
        "getElementById ile çağrılan, HTML'de olmayan ve allowlist'te de "
        f"bulunmayan id'ler: {unknown}. Ya HTML'e ekle, ya guard'la + OPTIONAL'a al."
    )


# ---------------------------------------------------------------------------
# 2) querySelector("#id") / querySelectorAll("#id ...") bütünlüğü
# ---------------------------------------------------------------------------
def test_queryselector_id_targets_exist(scripts: str, defined_ids: set[str]):
    """querySelector içindeki basit `#id` seçicileri de tanımlı olmalı."""
    # #id (yalnızca id seçici; başında `#`, sonrasında boşluk/tırnak/[/. gelebilir)
    refs = re.findall(r'querySelector(?:All)?\(\s*["\']#([A-Za-z0-9_-]+)', scripts)
    missing = sorted(set(refs) - defined_ids)
    assert not missing, f"querySelector('#id') hedefleri HTML'de yok: {missing}"


# ---------------------------------------------------------------------------
# 3) Navigasyon — data-page / data-go hedefleri gerçek sayfa mı?
# ---------------------------------------------------------------------------
def test_nav_targets_are_real_pages(html: str):
    """Her data-page / data-go değeri bir <section class="page" id="..."> olmalı."""
    page_ids = set(re.findall(r'<section class="page[^"]*" id="([^"]+)"', html))
    assert page_ids, "Hiç .page section bulunamadı — HTML yapısı bozulmuş olabilir."

    nav_targets = set(re.findall(r'data-(?:page|go)="([^"]+)"', html))
    missing = sorted(nav_targets - page_ids)
    assert not missing, (
        f"data-page/data-go ile gidilen ama var olmayan sayfa(lar): {missing}. "
        f"Mevcut sayfalar: {sorted(page_ids)}"
    )


def test_validpages_matches_sections(scripts: str, html: str):
    """JS'teki validPages listesi ile gerçek <section> id'leri tutarlı olmalı."""
    m = re.search(r'validPages\s*=\s*\[([^\]]+)\]', scripts)
    if not m:
        pytest.skip("validPages listesi bulunamadı")
    listed = set(re.findall(r'["\']([^"\']+)["\']', m.group(1)))
    page_ids = set(re.findall(r'<section class="page[^"]*" id="([^"]+)"', html))
    # validPages'te olup section'da olmayan → ölü referans
    dead = sorted(listed - page_ids)
    assert not dead, f"validPages'te olup HTML'de olmayan sayfa: {dead}"


# ---------------------------------------------------------------------------
# 4) Inline onclick fonksiyonları JS'te tanımlı mı?
# ---------------------------------------------------------------------------
def test_inline_onclick_functions_defined(html: str, scripts: str):
    """onclick="fn(...)" ile çağrılan her fonksiyon JS'te tanımlı olmalı.

    `event.stopPropagation()` gibi built-in'ler ve `this.` çağrıları hariç.
    """
    calls = re.findall(r'onclick="(?:event\.stopPropagation\(\);\s*)?([A-Za-z_$][\w$]*)\s*\(', html)
    called = set(calls) - {"event"}

    # JS'te tanımlı olabilecek isimler: function X, window.X =, const X =, X =, let X =
    defined = set(re.findall(r'\bfunction\s+([A-Za-z_$][\w$]*)', scripts))
    defined |= set(re.findall(r'window\.([A-Za-z_$][\w$]*)\s*=', scripts))
    defined |= set(re.findall(r'(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=', scripts))

    # Built-in / güvenli çağrılar
    builtin = {"stopPropagation", "preventDefault"}
    missing = sorted(called - defined - builtin)
    assert not missing, (
        f"onclick ile çağrılan ama JS'te tanımlı OLMAYAN fonksiyon(lar): {missing}"
    )


# ---------------------------------------------------------------------------
# 5) Kaba sözdizimi dengesi — script bloğu yarıda kesilmiş mi?
# ---------------------------------------------------------------------------
def test_script_braces_balanced(scripts: str):
    """Süslü parantez / normal parantez dengesi (kaba ama etkili bozulma testi).

    String/regex/comment içindekileri saymamak için önce onları soyar.
    """
    s = scripts
    # blok yorumları
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.DOTALL)
    # satır yorumları
    s = re.sub(r"//[^\n]*", "", s)
    # template literal / string / char — kaba temizlik
    s = re.sub(r"`(?:\\.|[^`\\])*`", "``", s, flags=re.DOTALL)
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)

    assert s.count("{") == s.count("}"), (
        f"Süslü parantez dengesizliği: {{={s.count('{')} vs }}={s.count('}')} "
        "— bir script bloğu yarıda kesilmiş olabilir."
    )
    assert s.count("(") == s.count(")"), (
        f"Parantez dengesizliği: (={s.count('(')} vs )={s.count(')')}"
    )


# ---------------------------------------------------------------------------
# 6) Kritik ID'ler mutlaka var (regresyon kilidi)
# ---------------------------------------------------------------------------
CRITICAL_IDS = [
    "navCountQueue", "toast", "btnRefresh", "accountName", "accountStatus",
    "queueDraftList", "queuePlannedList", "queueApprovalList", "queueScheduledList",
    "queueCountDraft", "queueCountPlanned", "queueCountApproval", "queueCountScheduled",
    "libraryGrid", "libFilters", "statsGrid",
    "modeNews", "modeVisual", "studioGenerateBtn",
    "runNewsBtn", "runTopicBtn", "runQueueBtn",
    "schedThreadDetail", "togAutoUpload",
    "genOverlay", "genLog", "genProgressBar",
]


@pytest.mark.parametrize("cid", CRITICAL_IDS)
def test_critical_id_present(defined_ids: set[str], cid: str):
    assert cid in defined_ids, f"Kritik DOM id eksik: #{cid}"
