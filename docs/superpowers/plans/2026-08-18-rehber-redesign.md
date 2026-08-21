# Rehber Sekmesi Yeniden Tasarım Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rehber sekmesini sabit ana sekme kabuğu içinde hızlı erişim, tek gruplanmış konu listesi ve sekme-içi detay görünümüyle yenilemek.

**Architecture:** Mevcut `_TabMustKnowView`, seçili konu kimliğini yerel sunum durumu olarak tutacak; konu seçimi yeni bir rota açmadan aynı IndexedStack çocuğunda liste ve detay görünümü arasında geçecek. Var olan `kMustKnowSections`, çocuk filtresi ve `_PreDepartureCard` veri/işlev kaynağı olarak korunacak.

**Tech Stack:** Flutter, Material tabanlı Apple-stili viewer bileşenleri, Flutter widget testleri.

**Spec:** `docs/superpowers/specs/2026-08-18-rehber-redesign-design.md`

## Global Constraints

- UI metinleri TR ve EN olmalı; uzun yeni metinler `LText` ile sağlanmalı.
- Alt navigasyon ve üst durum çubuğu konu açıldığında yerinde kalmalı.
- Dokunma alanları en az 44 dp olmalı.
- Rehber verisi, affiliate hedefleri ve rota algoritması değişmemeli.
- Mevcut kirli çalışma alanındaki kapsam dışı değişikliklere dokunulmamalı.

---

### Task 1: Yeni bilgi mimarisini widget testleriyle kilitle

**Files:**
- Modify: `rotori-mobile/test/features/viewer/guide_tab_test.dart`

**Interfaces:**
- Consumes: `PlanViewerScreen`, `kMustKnowSections`, mevcut test harness'i.
- Produces: Rehber başlığı, hızlı erişim, konu listesi, sekme-içi detay ve alttaki hazırlık satırı için davranış sözleşmesi.

- [ ] **Step 1: Eski üst hazırlık kartı beklentilerini yeni düzen beklentileriyle değiştir**

  `Rehber`, `Hızlı erişim` ve `Tüm konular` başlıklarının görünmesini; `Seyahat öncesi hallet` satırının `Tüm konular` başlığından sonra gelmesini bekle.

- [ ] **Step 2: Testi çalıştır ve doğru nedenle kırmızı olduğunu doğrula**

  Run: `flutter test test/features/viewer/guide_tab_test.dart`
  Expected: Yeni başlıklar bulunamadığı ve hazırlık satırı hâlâ üstte olduğu için FAIL.

- [ ] **Step 3: Sekme-içi detay davranışını testle**

  `Suica Kartı Nasıl Alınır?` satırına dokunulduğunda madde metninin ve `Tüm konular` geri aksiyonunun görünmesini; alt navigasyondaki `Rehber` etiketinin kalmasını bekle.

- [ ] **Step 4: Arama ve çocuk filtresi regresyonlarını yeni görünüm için koru**

  Aramanın eşleşen konuyu açması, eşleşmeyeni gizlemesi ve çocuk maddelerinin yalnız çocuklu gezide görünmesi beklentilerini sürdür.

---

### Task 2: Rehber liste ve detay görünümünü uygula

**Files:**
- Modify: `rotori-mobile/lib/features/plans/plan_viewer_screen.dart`
- Test: `rotori-mobile/test/features/viewer/guide_tab_test.dart`

**Interfaces:**
- Consumes: `MustKnowSection`, `MustKnowTip`, `ViewerPalette`, `AppLang`.
- Produces: `_TabMustKnowView` içinde liste/detay sunum durumu ve yeniden kullanılabilir konu satırı/hızlı erişim kartları.

- [ ] **Step 1: Minimal liste görünümünü yaz**

  Büyük `Rehber` başlığı, arama, dört hızlı erişim kartı, tek inset-group konu listesi ve en altta `_PreDepartureCard` üret.

- [ ] **Step 2: Aynı sekmede detay görünümünü yaz**

  Seçili bölüm için `Tüm konular` geri aksiyonu, bölüm başlığı, madde sayısı ve filtrelenmiş tavsiye satırlarını göster; geri dönüşte liste arama durumunu koru.

- [ ] **Step 3: Hareket ve erişilebilirliği tamamla**

  Satırlarda `Semantics(button: true)`, en az 52 dp yükseklik ve `RotoriMotion`/MediaQuery azaltılmış hareket davranışıyla sakin geçiş kullan.

- [ ] **Step 4: Hedefli testi çalıştır ve yeşili doğrula**

  Run: `flutter test test/features/viewer/guide_tab_test.dart`
  Expected: PASS.

---

### Task 3: Belgele ve kapsamlı doğrula

**Files:**
- Modify: `docs/CURRENT_TASK.md`
- Test: `rotori-mobile/test/features/viewer/guide_tab_test.dart`
- Test: `rotori-mobile/test/features/viewer/plan_viewer_test.dart`

**Interfaces:**
- Consumes: Task 1-2 çıktısı.
- Produces: Güncel iş kaydı ve doğrulama kanıtı.

- [ ] **Step 1: Rehber teslimatını CURRENT_TASK'e ekle**

  Yeni bilgi mimarisini, sabit sekme davranışını ve doğrulama sonuçlarını tarihli tamamlanan iş olarak kaydet.

- [ ] **Step 2: Hedefli test ve analiz çalıştır**

  Run: `flutter test test/features/viewer/guide_tab_test.dart test/features/viewer/plan_viewer_test.dart`
  Run: `flutter analyze --no-pub lib/features/plans/plan_viewer_screen.dart test/features/viewer/guide_tab_test.dart`
  Expected: Tüm testler PASS, analiz 0 issue.

- [ ] **Step 3: Release web önizlemesini üret ve görsel kontrol et**

  Run: `flutter build web --release -t lib/preview_main.dart`
  Expected: Build succeeds; Rehber liste/detay akışı dar telefon görünümünde taşmadan çalışır ve alt menü kalır.

