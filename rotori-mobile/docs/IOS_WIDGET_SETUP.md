# iOS Home Screen Widget — Kurulum Notları

Bu belge, "Sıradaki Aktivite" özelliğinin iOS Home Screen widget'ı olarak
görünmesi için gereken **manuel Xcode adımlarını** listeler. Dart tarafı
bugün derler ve çalışır (`lib/features/viewer/home_widget_hook.dart`); native
Widget Extension target'ı henüz repo'da yok, çünkü `project.pbxproj`
otomatik düzenlemeleri kırılgan — aşağıdaki adımları Xcode üzerinden
uygulayın, hook o zaman widget'a veri akıtmaya başlar.

> Kod durumu:
> - `pubspec.yaml` → `home_widget: ^0.6.0` (web derlemesinde no-op).
> - `lib/features/viewer/home_widget_hook.dart` → veriyi hesaplar + yazar.
> - `lib/features/plans/plan_viewer_screen.dart` → Rehber açılınca ve
>   `AppLifecycleState.resumed` olayında hook'u tetikler.

Dart tarafı native target eksikse **sessizce no-op'a düşer** (try/catch);
uygulama kırılmaz, sadece widget güncellenmez.

---

## 1. Widget Extension target'ını ekle

1. `ios/Runner.xcworkspace` dosyasını Xcode ile aç.
2. **File → New → Target…**
3. Sol panelde **Widget Extension** seç → **Next**.
4. Ayarlar:
   - **Product Name:** `RotoriWidget` (Dart tarafı bu ismi bekliyor;
     `home_widget_hook.dart` içindeki `kRotoriWidgetName` sabiti).
   - **Include Configuration Intent:** **KAPALI**.
   - Team + Bundle Identifier default'ta bırak (Xcode otomatik ayarlar).
5. **Finish** → "Activate scheme?" penceresinde **Cancel** (Runner scheme'i
   ana geliştirme için tutuyoruz).

## 2. App Groups capability'sini bağla — **iki hedef de aynı grupta olmalı**

1. Sol panelde **Runner** target'ını seç → **Signing & Capabilities**.
2. Geçerli bir **Team** seçili olduğundan emin ol.
3. **+ Capability** → **App Groups** ekle → **+** ile grubu oluştur:
   `group.com.mennansevim.rotori`
4. Aynı adımı **RotoriWidget** target'ında da uygula (App Groups → aynı
   grubu seç). Dart tarafı bu ID'yi bekliyor (`kRotoriAppGroupId`).

> Not: App Group ID'sini değiştirmek isterseniz, hem Xcode'da hem
> `lib/features/viewer/home_widget_hook.dart` içindeki `kRotoriAppGroupId`
> sabitinde eş zamanlı güncelleyin.

## 3. SwiftUI widget kodunu yapıştır

Xcode `RotoriWidget/RotoriWidget.swift` dosyasını sizin için oluşturdu.
İçeriğini aşağıdaki örnekle değiştirin — `UserDefaults(suiteName:)` ile Dart
tarafından yazılan altı anahtarı okur ve küçük/orta boyutta gösterir.

```swift
import WidgetKit
import SwiftUI

// Dart tarafındaki `home_widget_hook.dart` ile eşleşen anahtarlar.
private let appGroupId = "group.com.mennansevim.rotori"

struct NextActivityEntry: TimelineEntry {
    let date: Date
    let title: String
    let time: String
    let emoji: String
    let city: String
    let tripTitle: String
    let daysUntilStart: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NextActivityEntry {
        NextActivityEntry(
            date: Date(),
            title: "Fushimi Inari",
            time: "09:00",
            emoji: "📍",
            city: "Kyoto",
            tripTitle: "Japonya",
            daysUntilStart: "0"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextActivityEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextActivityEntry>) -> Void) {
        // Uygulama her verisi ittirdiğinde WidgetCenter.reloadTimelines tetikleniyor
        // (home_widget paketi), bu yüzden .atEnd ile 1 saatlik nazik bir yenileme
        // yeterli — pil dostu.
        let entry = readEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> NextActivityEntry {
        let d = UserDefaults(suiteName: appGroupId)
        return NextActivityEntry(
            date: Date(),
            title: d?.string(forKey: "nextTitle") ?? "",
            time: d?.string(forKey: "nextTime") ?? "",
            emoji: d?.string(forKey: "nextEmoji") ?? "",
            city: d?.string(forKey: "nextCity") ?? "",
            tripTitle: d?.string(forKey: "tripTitle") ?? "Japonya",
            daysUntilStart: d?.string(forKey: "daysUntilStart") ?? "0"
        )
    }
}

struct RotoriWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.emoji.isEmpty ? "🗾" : entry.emoji).font(.title3)
                Text(entry.tripTitle)
                    .font(.caption).bold()
                    .foregroundColor(.secondary)
                Spacer()
                if let n = Int(entry.daysUntilStart), n > 0 {
                    Text("\(n)g")
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.pink.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            Text(entry.title.isEmpty ? "Plan yükleniyor…" : entry.title)
                .font(.headline).lineLimit(2)
            HStack {
                if !entry.time.isEmpty {
                    Text(entry.time).font(.subheadline).bold()
                }
                if !entry.city.isEmpty {
                    Text(entry.city).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
    }
}

@main
struct RotoriWidget: Widget {
    let kind: String = "RotoriWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RotoriWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sıradaki Aktivite")
        .description("Japonya rehberindeki bir sonraki plan öğesi.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

## 4. Build & Run

1. Xcode'da scheme'i **Runner**'a al → gerçek cihaz veya simülatörde çalıştır.
2. Uygulamayı en az bir kez aç ve bir rehberi görüntüle (`plan_viewer_screen`
   `initState`'te hook'u tetikliyor).
3. Home Screen'e dön → uzun bas → **+** → **Japan Trip** widget'ını ekle.
4. "Sıradaki Aktivite" ilk push ile görünmelidir.

## 5. Veri sözleşmesi — anahtarlar

Widget `UserDefaults(suiteName: "group.com.mennansevim.rotori")` üzerinden okur;
Dart tarafı `home_widget_hook.dart` içinde birebir aynı anahtarları
`String` olarak yazar:

| Anahtar          | Açıklama                                        |
| ---------------- | ----------------------------------------------- |
| `nextTitle`      | Sıradaki aktivitenin adı                        |
| `nextTime`       | "HH:MM" (boş olabilir)                          |
| `nextEmoji`      | Aktivite tipine göre emoji (📍 🍜 🚄 🏨)         |
| `nextCity`       | Günün teması / şehir etiketi                    |
| `tripTitle`      | Gezi başlığı                                    |
| `daysUntilStart` | Geziye kalan gün sayısı (int, string olarak)    |

## 6. Ne zaman tazelenir?

Dart tarafı iki noktada `updateWidget` çağırıyor:
- Rehber ekranı ilk açıldığında (`_ViewerBodyState.initState` → post-frame).
- Uygulama arka plandan öne alındığında (`AppLifecycleState.resumed`).

Widget kendi başına 1 saatlik nazik bir yenileme timeline'ı da tutar
(pil dostu). Kullanıcı planda değişiklik yaparsa Rehberi yeniden açtığında
veri güncellenecektir.
