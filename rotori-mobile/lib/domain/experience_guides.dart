import 'localized_text.dart';

enum ExperienceGuideKind { themePark, digitalArt }

class ExperienceTimelineStop {
  const ExperienceTimelineStop({
    required this.time,
    required this.title,
    required this.detail,
  });

  final String time;
  final LText title;
  final LText detail;
}

class ExperienceHighlight {
  const ExperienceHighlight({
    required this.title,
    required this.duration,
    required this.strategy,
  });

  final LText title;
  final LText duration;
  final LText strategy;
}

class ExperienceGuide {
  const ExperienceGuide({
    required this.id,
    required this.kind,
    required this.emoji,
    required this.title,
    required this.city,
    required this.tagline,
    required this.duration,
    required this.arrivalBuffer,
    required this.bookingWindow,
    required this.bestFor,
    required this.ticketSteps,
    required this.timeline,
    required this.highlights,
    required this.tips,
    required this.officialUrl,
    this.appUrl,
    this.videoUrl,
    this.reminderWindowId,
  });

  final String id;
  final ExperienceGuideKind kind;
  final String emoji;
  final String title;
  final String city;
  final LText tagline;
  final LText duration;
  final LText arrivalBuffer;
  final LText bookingWindow;
  final LText bestFor;
  final List<LText> ticketSteps;
  final List<ExperienceTimelineStop> timeline;
  final List<ExperienceHighlight> highlights;
  final List<LText> tips;
  final String officialUrl;
  final String? appUrl;
  final String? videoUrl;
  final String? reminderWindowId;
}

const List<ExperienceGuide> kExperienceGuides = [
  ExperienceGuide(
    id: 'usj',
    kind: ExperienceGuideKind.themePark,
    emoji: '🎢',
    title: 'Universal Studios Japan',
    city: 'Osaka',
    tagline: LText(
      'Nintendo, Harry Potter ve yüksek tempolu oyuncaklar için tam gün.',
      'A full day for Nintendo, Harry Potter and high-energy rides.',
    ),
    duration: LText('10–12 saat', '10–12 hours'),
    arrivalBuffer: LText('Kapıdan 45–60 dk önce', '45–60 min before the gate'),
    bookingWindow: LText(
      '45–60 gün önce kontrol et',
      'Start checking 45–60 days ahead',
    ),
    bestFor: LText(
      'Yoğun oyuncak günü, oyun ve sinema dünyaları',
      'A ride-heavy day, games and movie worlds',
    ),
    ticketSteps: [
      LText(
        'Önce tarihli Studio Pass al; bu park giriş biletidir.',
        'First buy a dated Studio Pass; this is your park admission.',
      ),
      LText(
        'Express Pass ayrı üründür. İçindeki oyuncakları ve sabit saatleri tek tek karşılaştır.',
        'Express Pass is separate. Compare its exact ride lineup and fixed times.',
      ),
      LText(
        'QR kodları telefona indir, ekran görüntüsü al ve tüm grubun biletini resmî uygulamaya kaydet.',
        'Save every QR code offline and register the whole party in the official app.',
      ),
      LText(
        'Nintendo girişi Express paketinde garanti değilse parka girer girmez Area Timed Entry iste.',
        'If Nintendo entry is not guaranteed by your Express product, request Area Timed Entry after entering.',
      ),
    ],
    timeline: [
      ExperienceTimelineStop(
        time: '07:30',
        title: LText('Universal City', 'Universal City'),
        detail: LText(
          'Kahvaltı, tuvalet ve güvenlik kuyruğu için tampon bırak.',
          'Leave time for breakfast, toilets and the security line.',
        ),
      ),
      ExperienceTimelineStop(
        time: '08:30',
        title: LText('Kapı ve uygulama', 'Gate and app'),
        detail: LText(
          'Yayınlanan saat değişebilir; kapı açılır açılmaz ilk hedefe yürü.',
          'Published hours can change; walk to your first target as soon as entry begins.',
        ),
      ),
      ExperienceTimelineStop(
        time: '09:00',
        title: LText('En zor hedef', 'Hardest target'),
        detail: LText(
          'Nintendo zamanın yoksa Flying Dinosaur veya en uzun kuyruklu favorin.',
          'If Nintendo is timed later, start with Flying Dinosaur or your longest-queue favorite.',
        ),
      ),
      ExperienceTimelineStop(
        time: '11:00',
        title: LText('Erken öğle', 'Early lunch'),
        detail: LText(
          '12:00 yoğunluğuna kalmadan ye; Express saatini kaçırmayacak bölgeyi seç.',
          'Eat before the noon rush and stay near your next fixed Express window.',
        ),
      ),
      ExperienceTimelineStop(
        time: '12:00–16:30',
        title: LText('Express + gösteri', 'Express + show'),
        detail: LText(
          'Sabit saatlerin çevresine Harry Potter, kapalı oyuncak ve WaterWorld yerleştir.',
          'Build Harry Potter, indoor rides and WaterWorld around fixed Express times.',
        ),
      ),
      ExperienceTimelineStop(
        time: '17:00–Kapanış',
        title: LText('Gece turu', 'Night lap'),
        detail: LText(
          'Kuyruğu düşen favoriler, Hogsmeade ışıkları ve çıkıştan önce alışveriş.',
          'Revisit shorter queues, see Hogsmeade lit up, then shop before exit.',
        ),
      ),
    ],
    highlights: [
      ExperienceHighlight(
        title: LText('Super Nintendo World', 'Super Nintendo World'),
        duration: LText('2–3 saat ayır', 'Allow 2–3 hours'),
        strategy: LText(
          'Timed Entry saatini kaçırma; interaktif oyun istiyorsan Power-Up Band için de süre ekle.',
          'Do not miss the Timed Entry window; add time for interactive play if buying a Power-Up Band.',
        ),
      ),
      ExperienceHighlight(
        title: LText('The Flying Dinosaur', 'The Flying Dinosaur'),
        duration:
            LText('İlk saat veya Single Rider', 'First hour or Single Rider'),
        strategy: LText(
          'En yoğun hız trenlerinden; grupça yan yana oturmak şart değilse Single Rider kullan.',
          'One of the busiest coasters; use Single Rider if sitting together is not essential.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Harry Potter and the Forbidden Journey',
            'Harry Potter and the Forbidden Journey'),
        duration: LText('Bölge için 90–120 dk', '90–120 min for the area'),
        strategy: LText(
          'Oyuncak kadar kale kuyruğu ve Hogsmeade gezisi için de vakit bırak.',
          'Leave time for the castle queue and Hogsmeade, not only the ride.',
        ),
      ),
      ExperienceHighlight(
        title: LText('WaterWorld', 'WaterWorld'),
        duration: LText('20–30 dk erken git', 'Arrive 20–30 min early'),
        strategy: LText(
          'Öğleden sonraki oturmalı mola olarak kullan; ön sıralar ıslanabilir.',
          'Use it as a seated afternoon break; the front rows can get wet.',
        ),
      ),
    ],
    tips: [
      LText(
        'Studio Pass ile Express Pass aynı şey değildir; Express tek başına park girişi sağlamaz.',
        'Studio Pass and Express Pass are different; Express alone does not admit you to the park.',
      ),
      LText(
        'Express saatleri çakışıyorsa ürün adından çok saat çizelgesine bak.',
        'If Express windows conflict, judge the schedule rather than the product name.',
      ),
      LText(
        'Günlük açılış, bakım ve boy sınırlarını bir gece önce resmî uygulamadan kontrol et.',
        'Check opening hours, closures and height rules in the official app the night before.',
      ),
    ],
    officialUrl: 'https://www.usj.co.jp/web/en/us/tickets',
    appUrl:
        'https://www.usj.co.jp/web/en/us/enjoy/numbered-ticket/app/timed-entry-ticket',
    videoUrl: 'https://www.youtube.com/user/usjTV',
    reminderWindowId: 'usj-express',
  ),
  ExperienceGuide(
    id: 'disneyland',
    kind: ExperienceGuideKind.themePark,
    emoji: '🏰',
    title: 'Tokyo Disneyland',
    city: 'Tokyo',
    tagline: LText(
      'Klasik Disney atmosferi, aile oyuncakları ve gece geçit töreni.',
      'Classic Disney atmosphere, family rides and a nighttime parade.',
    ),
    duration: LText('11–13 saat', '11–13 hours'),
    arrivalBuffer: LText('Kapıdan 60 dk önce', '60 min before the gate'),
    bookingWindow: LText('Yaklaşık 2 ay önce', 'About 2 months ahead'),
    bestFor: LText(
      'İlk Disney deneyimi, çocuklu aile, klasik karakterler',
      'A first Disney visit, families and classic characters',
    ),
    ticketSteps: [
      LText(
        'Belirli tarih ve park için 1-Day Passport al; Disneyland ile DisneySea ayrı seçimdir.',
        'Buy a dated 1-Day Passport for one park; Disneyland and DisneySea are separate choices.',
      ),
      LText(
        'Tokyo Disney Resort uygulamasını indir, MyDisney hesabını ve grubunu önceden hazırla.',
        'Install the Tokyo Disney Resort app and prepare your MyDisney account and group in advance.',
      ),
      LText(
        'Girişten sonra ücretli Disney Premier Access, ücretsiz Priority Pass ve Entry Request durumunu kontrol et.',
        'After entry, check paid Disney Premier Access, free Priority Pass and Entry Request availability.',
      ),
      LText(
        'Öğle yemeği için Mobile Order seç; oyuncak saatleriyle çakışmayacak teslim aralığı al.',
        'Use Mobile Order for lunch and choose a pickup window clear of ride reservations.',
      ),
    ],
    timeline: [
      ExperienceTimelineStop(
        time: '07:30',
        title: LText('Maihama varış', 'Arrive at Maihama'),
        detail: LText(
          'Güvenlik ve giriş kuyruğunu hesaba kat; grup QR’ları hazır olsun.',
          'Allow for security and entry queues; have every group QR ready.',
        ),
      ),
      ExperienceTimelineStop(
        time: 'Giriş anı',
        title: LText('Uygulama sprinti', 'App sprint'),
        detail: LText(
          'Önce en önemli Premier Access/Priority Pass, sonra Entry Request ve öğle siparişi.',
          'Secure the top Premier/Priority access first, then Entry Request and lunch.',
        ),
      ),
      ExperienceTimelineStop(
        time: '09:00–11:30',
        title: LText('Uzak bölge', 'Far side first'),
        detail: LText(
          'Girişten uzak popüler oyuncağa yürü; sabahı fotoğrafla tüketme.',
          'Walk to a popular ride away from the entrance; do not spend the best hour on photos.',
        ),
      ),
      ExperienceTimelineStop(
        time: '11:30–15:30',
        title: LText('Sipariş + sabit saatler', 'Order + fixed windows'),
        detail: LText(
          'Yemek, DPA ve gösteri saatlerinin etrafına kısa kuyrukları yerleştir.',
          'Fit shorter waits around dining, DPA and show windows.',
        ),
      ),
      ExperienceTimelineStop(
        time: '16:00–Kapanış',
        title: LText('Geçit ve gece', 'Parade and night'),
        detail: LText(
          'Geçit yerini erken seç; kapanışa yakın popüler oyuncakları tekrar kontrol et.',
          'Choose a parade spot early and recheck popular rides near closing.',
        ),
      ),
    ],
    highlights: [
      ExperienceHighlight(
        title: LText('Enchanted Tale of Beauty and the Beast',
            'Enchanted Tale of Beauty and the Beast'),
        duration: LText('DPA önceliği', 'Top DPA priority'),
        strategy: LText(
          'İlk kez gidiyorsan ücretli erişim bütçesini burada kullanmak günü rahatlatır.',
          'For a first visit, spending paid access here can simplify the whole day.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Pooh’s Hunny Hunt', 'Pooh’s Hunny Hunt'),
        duration: LText('Sabah veya akşam', 'Morning or evening'),
        strategy: LText(
          'Japonya’ya özgü favorilerden; gün ortası yoğunluğuna bırakma.',
          'A Japan favorite; avoid leaving it for the midday peak.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Electrical Parade', 'Electrical Parade'),
        duration: LText('30–45 dk önce yer seç', 'Pick a spot 30–45 min early'),
        strategy: LText(
          'Program hava ve operasyonla değişebilir; aynı gün uygulamadan doğrula.',
          'Schedules can change with weather and operations; confirm in the app that day.',
        ),
      ),
    ],
    tips: [
      LText(
        'DPA park biletine dahil değildir ve girişten sonra alınır.',
        'DPA is not included with park admission and is purchased after entry.',
      ),
      LText(
        'Tüm grubun biletini tek uygulama grubunda toplamak saat çakışmasını azaltır.',
        'Keeping the whole party in one app group reduces reservation conflicts.',
      ),
      LText(
        'Geçit sırasında bazı oyuncak kuyrukları kısalabilir; önceliğini önceden seç.',
        'Some ride queues can ease during parades; decide your priority in advance.',
      ),
    ],
    officialUrl: 'https://www.tokyodisneyresort.jp/en/tdl/ticket/index.html',
    appUrl: 'https://www.tokyodisneyresort.jp/en/tdr/app/',
    videoUrl: 'https://www.youtube.com/TDRofficialchannel',
    reminderWindowId: 'tokyo-disney',
  ),
  ExperienceGuide(
    id: 'disneysea',
    kind: ExperienceGuideKind.themePark,
    emoji: '🌊',
    title: 'Tokyo DisneySea',
    city: 'Tokyo',
    tagline: LText(
      'Daha yetişkin atmosfer, benzersiz limanlar ve Japonya’ya özel oyuncaklar.',
      'A more grown-up atmosphere, unique ports and Japan-only rides.',
    ),
    duration: LText('11–13 saat', '11–13 hours'),
    arrivalBuffer: LText('Kapıdan 60 dk önce', '60 min before the gate'),
    bookingWindow: LText('Yaklaşık 2 ay önce', 'About 2 months ahead'),
    bestFor: LText(
      'Yetişkin çiftler, atmosfer ve benzersiz Disney deneyimi',
      'Adult couples, atmosphere and a unique Disney experience',
    ),
    ticketSteps: [
      LText(
        'DisneySea için tarihli 1-Day Passport seç; Disneyland bileti burada geçmez.',
        'Choose a dated DisneySea 1-Day Passport; a Disneyland ticket is not interchangeable.',
      ),
      LText(
        'Biletleri resmî uygulamada aynı gruba ekle ve ödeme kartını önceden hazırla.',
        'Add tickets to one app group and prepare your payment card before the visit.',
      ),
      LText(
        'Girişten hemen sonra günün DPA, Priority Pass ve Entry Request seçeneklerini sırala.',
        'Immediately after entry, rank the day’s DPA, Priority Pass and Entry Request options.',
      ),
      LText(
        'Fantasy Springs ve diğer popüler alanlarda erişim yöntemi değişebileceği için aynı gün uygulamayı esas al.',
        'Access rules for Fantasy Springs and other popular areas can change, so follow the app that day.',
      ),
    ],
    timeline: [
      ExperienceTimelineStop(
        time: '07:30',
        title: LText('Resort Line varış', 'Arrive via Resort Line'),
        detail: LText(
          'Maihama’dan monoray ve güvenlik süresini planına ekle.',
          'Add monorail and security time from Maihama to your plan.',
        ),
      ),
      ExperienceTimelineStop(
        time: 'Giriş anı',
        title: LText('DPA + Priority Pass', 'DPA + Priority Pass'),
        detail: LText(
          'Soaring, Fantasy Springs veya kaçırmak istemediğin tek hedefi önce çöz.',
          'Solve Soaring, Fantasy Springs or your single must-do before anything else.',
        ),
      ),
      ExperienceTimelineStop(
        time: '09:00–12:00',
        title: LText('Arka limanlar', 'Outer ports'),
        detail: LText(
          'Girişten uzak hedefleri sabah bitir, liman fotoğraflarını dönüşte çek.',
          'Finish distant targets early and take harbor photos on the way back.',
        ),
      ),
      ExperienceTimelineStop(
        time: '12:00–17:00',
        title: LText('Sabit rezervasyonlar', 'Fixed reservations'),
        detail: LText(
          'Yemek, gösteri ve DPA saatleri arasında komşu limanları gez.',
          'Explore neighboring ports between dining, show and DPA windows.',
        ),
      ),
      ExperienceTimelineStop(
        time: '17:00–Kapanış',
        title: LText('Liman gecesi', 'Harbor at night'),
        detail: LText(
          'Akşam şovu, Mediterranean Harbor ve kapanışa yakın son oyuncak.',
          'Evening show, Mediterranean Harbor and one final late ride.',
        ),
      ),
    ],
    highlights: [
      ExperienceHighlight(
        title: LText('Journey to the Center of the Earth',
            'Journey to the Center of the Earth'),
        duration: LText('Sabah önceliği', 'Morning priority'),
        strategy: LText(
          'Mysterious Island’daki ana hedef; bakım durumunu bir gece önce kontrol et.',
          'The Mysterious Island anchor; check maintenance status the night before.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Soaring: Fantastic Flight', 'Soaring: Fantastic Flight'),
        duration: LText('DPA adayı', 'Strong DPA candidate'),
        strategy: LText(
          'Uzun standby yerine DPA bütçesiyle günün sabit noktasına dönüştürülebilir.',
          'Use DPA to turn a long standby into a predictable fixed point.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Fantasy Springs', 'Fantasy Springs'),
        duration: LText('2–3 saatlik blok', 'A 2–3 hour block'),
        strategy: LText(
          'Erişim ve oyuncak kuralları değişkendir; yalnız güncel uygulama bilgisini izle.',
          'Area and ride access rules change; rely only on current in-app information.',
        ),
      ),
    ],
    tips: [
      LText(
        'DisneySea büyük ve eğimlidir; aynı limana tekrar tekrar dönmekten kaçın.',
        'DisneySea is large and hilly; avoid repeatedly crossing back to the same port.',
      ),
      LText(
        'Akşam liman atmosferi deneyimin yarısıdır; erken çıkış planlama.',
        'The harbor after dark is half the experience; do not plan an early exit.',
      ),
      LText(
        'Gemi ve trenleri yalnız oyuncak değil, yürümeyi azaltan ulaşım olarak da kullan.',
        'Use boats and trains as transport, not only as attractions, to reduce walking.',
      ),
    ],
    officialUrl: 'https://www.tokyodisneyresort.jp/en/tds/ticket/index.html',
    appUrl: 'https://www.tokyodisneyresort.jp/en/tdr/app/',
    videoUrl: 'https://www.youtube.com/TDRofficialchannel',
    reminderWindowId: 'tokyo-disney',
  ),
  ExperienceGuide(
    id: 'teamlab-planets',
    kind: ExperienceGuideKind.digitalArt,
    emoji: '💧',
    title: 'teamLab Planets',
    city: 'Toyosu, Tokyo',
    tagline: LText(
      'Çıplak ayak, su, ayna ve bedenin eserin içine girdiği rota.',
      'A barefoot route through water, mirrors and body-scale art.',
    ),
    duration: LText('2–2,5 saat', '2–2.5 hours'),
    arrivalBuffer:
        LText('Slotundan 20–30 dk önce', '20–30 min before the slot'),
    bookingWindow: LText('3–4 hafta önce', '3–4 weeks ahead'),
    bestFor: LText(
      'İlk teamLab, fotoğraf ve fiziksel/duyusal deneyim',
      'A first teamLab, photography and a physical sensory route',
    ),
    ticketSteps: [
      LText(
        'Resmî mağazadan tarih ve 30 dakikalık giriş aralığı seç; bu süre içeride kalma limiti değildir.',
        'Choose a date and 30-minute entry window; it is not your time limit inside.',
      ),
      LText(
        'QR bileti çevrimdışı kaydet; gişeden bilet alma seçeneğine güvenme.',
        'Save the QR ticket offline; do not rely on buying at a ticket counter.',
      ),
      LText(
        'Paçası diz üstüne kıvrılan kıyafet giy; su yetişkinlerde diz hizasına çıkabilir.',
        'Wear clothes that roll above the knee; water can reach adult knee height.',
      ),
      LText(
        'Büyük çanta ve ayakkabıyı locker’a bırak; havlu su bölümünün çıkışında verilir.',
        'Leave large bags and shoes in lockers; towels are provided after the water area.',
      ),
    ],
    timeline: [
      ExperienceTimelineStop(
        time: '-30 dk',
        title: LText('Shin-Toyosu', 'Shin-Toyosu'),
        detail: LText(
          'İstasyondan 1 dk; giriş kuyruğu yoğunlukta 30–60 dk sürebilir.',
          'It is 1 minute from the station; entry can still take 30–60 minutes when busy.',
        ),
      ),
      ExperienceTimelineStop(
        time: '0:00–0:20',
        title: LText('Locker + çıplak ayak', 'Locker + barefoot start'),
        detail: LText(
          'Telefonunu güvenli tut, gevşek eşyaları bırak ve karanlığa gözünü alıştır.',
          'Secure your phone, store loose items and let your eyes adjust to the dark.',
        ),
      ),
      ExperienceTimelineStop(
        time: '0:20–1:20',
        title: LText('Su ve beden alanları', 'Water and body spaces'),
        detail: LText(
          'Rotayı tersine çeviremezsin; fotoğraf kadar deneyime de vakit ayır.',
          'The route is directional; spend time experiencing it, not only taking photos.',
        ),
      ),
      ExperienceTimelineStop(
        time: '1:20–2:30',
        title: LText('Bahçe ve final', 'Garden and finale'),
        detail: LText(
          'Mevsim ve yoğunluğa göre eserler değişebilir; çıkışta kurulanıp giyin.',
          'Works can vary by season and crowding; dry off and get dressed at the exit.',
        ),
      ),
    ],
    highlights: [
      ExperienceHighlight(
        title: LText('Water Area', 'Water Area'),
        duration: LText('30–45 dk', '30–45 min'),
        strategy: LText(
          'Çocuk için yedek kıyafet taşı; su bölümü için dolambaçlı alternatif rota sorulabilir.',
          'Bring spare clothes for children; staff can provide a detour around water areas.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Mirror rooms', 'Mirror rooms'),
        duration: LText('20–30 dk', '20–30 min'),
        strategy: LText(
          'Ayna zemin nedeniyle etek yerine pantolon tercih et.',
          'Choose trousers rather than a skirt because of mirrored floors.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Garden Area', 'Garden Area'),
        duration: LText('30–45 dk', '30–45 min'),
        strategy: LText(
          'Fotoğraf kuyruğu oluşursa tüm süreyi tek eserde tüketme.',
          'If a photo queue forms, do not spend the whole visit on one work.',
        ),
      ),
    ],
    tips: [
      LText(
        'Biletteki saat giriş aralığıdır; içeride katı süre sınırı yoktur.',
        'The printed time is an entry window; there is no strict time limit inside.',
      ),
      LText(
        'Resmî siteden alınan biletlerde koşullara bağlı olarak saat değişikliği yapılabilir.',
        'Official-store tickets may allow date/time changes under stated conditions.',
      ),
      LText(
        'Bebek arabası içeri alınmaz; dışarıda park alanı vardır.',
        'Strollers are not allowed inside; parking is available outside.',
      ),
    ],
    officialUrl: 'https://teamlabplanets.dmm.com/en',
    appUrl: 'https://teamlabplanets.dmm.com/en/guide',
    reminderWindowId: 'teamlab-planets',
  ),
  ExperienceGuide(
    id: 'teamlab-borderless',
    kind: ExperienceGuideKind.digitalArt,
    emoji: '✨',
    title: 'teamLab Borderless',
    city: 'Azabudai Hills, Tokyo',
    tagline: LText(
      'Haritasız, odaları birbirine akan ve keşfettikçe büyüyen dijital müze.',
      'A mapless digital museum whose artworks flow between rooms.',
    ),
    duration: LText('2,5–4 saat', '2.5–4 hours'),
    arrivalBuffer: LText('Slotundan 20 dk önce', '20 min before the slot'),
    bookingWindow: LText('3–4 hafta önce', '3–4 weeks ahead'),
    bestFor: LText(
      'Daha büyük sergi, serbest keşif ve tekrar ziyaret',
      'A larger museum, free exploration and repeat visits',
    ),
    ticketSteps: [
      LText(
        'Saatli Entrance Pass seç; aynı gün bilet kalabilir ama tükenme riski vardır.',
        'Choose a timed Entrance Pass; same-day tickets may exist but can sell out.',
      ),
      LText(
        'QR bileti indir. Yerinde satın alma daha pahalı olabilir.',
        'Download the QR ticket. On-site purchase can cost more.',
      ),
      LText(
        'teamLab uygulamasını eser açıklamaları ve etkileşimler için önceden kur.',
        'Install the teamLab app in advance for artwork context and interactions.',
      ),
      LText(
        'İçeride harita yok; kaybolmak tasarımın parçası. Birleşme noktası belirle.',
        'There is no map; getting lost is intentional. Agree on a meeting point.',
      ),
    ],
    timeline: [
      ExperienceTimelineStop(
        time: '-20 dk',
        title: LText('Azabudai Hills B1', 'Azabudai Hills B1'),
        detail: LText(
          'Kamiyacho Exit 5’ten tabelaları izle; yeraltından ulaşılabilir.',
          'Follow signs from Kamiyacho Exit 5; the route can stay underground.',
        ),
      ),
      ExperienceTimelineStop(
        time: '0:00–1:00',
        title: LText('İlk keşif', 'First exploration'),
        detail: LText(
          'Tek bir doğru rota arama; hareket eden eserleri takip ederek yan odaları aç.',
          'Do not seek one correct route; follow moving art into side rooms.',
        ),
      ),
      ExperienceTimelineStop(
        time: '1:00–2:30',
        title: LText('Ana dünyalar', 'Core worlds'),
        detail: LText(
          'Athletics Forest ve Light Sculpture gibi büyük alanlara uzun blok ayır.',
          'Give major spaces such as Athletics Forest and Light Sculpture a long block.',
        ),
      ),
      ExperienceTimelineStop(
        time: '2:30–4:00',
        title: LText('Kayıp odalar + çay', 'Hidden rooms + tea'),
        detail: LText(
          'Kaçırdığın koridorlara dön; EN TEA HOUSE için ayrıca süre bırak.',
          'Return to missed corridors and leave extra time for EN TEA HOUSE.',
        ),
      ),
    ],
    highlights: [
      ExperienceHighlight(
        title: LText('Borderless World', 'Borderless World'),
        duration: LText('90+ dk', '90+ min'),
        strategy: LText(
          'Eserler odalar arasında gezer; aynı koridora sonra dönmek farklı görüntü verebilir.',
          'Works travel between rooms; revisiting a corridor can reveal something new.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Athletics Forest', 'Athletics Forest'),
        duration: LText('30–45 dk', '30–45 min'),
        strategy: LText(
          'Hareketli ve dengesiz zeminler vardır; rahat ayakkabı seç.',
          'Expect moving and uneven surfaces; wear comfortable shoes.',
        ),
      ),
      ExperienceHighlight(
        title: LText('EN TEA HOUSE', 'EN TEA HOUSE'),
        duration: LText('30–45 dk ekle', 'Add 30–45 min'),
        strategy: LText(
          'Müzeden erken çıkış sanma; içeride ayrı deneyim ve kişi başı içecek siparişi gerekir.',
          'It is a separate in-museum experience and requires one drink order per person.',
        ),
      ),
    ],
    tips: [
      LText(
        'İçeride kalış süresi sınırlı değildir fakat yeniden giriş yoktur.',
        'There is no stay limit, but re-entry is not permitted.',
      ),
      LText(
        'Flaş, tripod ve uzun selfie çubuğu yasaktır; ticari çekim izin gerektirir.',
        'Flash, tripods and long selfie sticks are prohibited; commercial filming requires permission.',
      ),
      LText(
        'Ayna zeminler vardır; gerekirse mekândan bel örtüsü ödünç alınabilir.',
        'There are mirrored floors; wrap skirts can be borrowed where needed.',
      ),
    ],
    officialUrl: 'https://www.teamlab.art/e/tokyo/',
    appUrl: 'https://www.teamlab.art/e/tokyo/#app',
    reminderWindowId: 'teamlab-borderless',
  ),
  ExperienceGuide(
    id: 'teamlab-botanical',
    kind: ExperienceGuideKind.digitalArt,
    emoji: '🌿',
    title: 'teamLab Botanical Garden',
    city: 'Nagai, Osaka',
    tagline: LText(
      'Bitkiler, göl, rüzgâr ve ışığın birleştiği açık hava gece müzesi.',
      'An open-air night museum of plants, lake, wind and light.',
    ),
    duration: LText('1,5–2 saat', '1.5–2 hours'),
    arrivalBuffer: LText('Girişten 20 dk önce', '20 min before entry'),
    bookingWindow: LText('1–2 hafta önce', '1–2 weeks ahead'),
    bestFor: LText(
      'Osaka akşamı, açık hava yürüyüşü ve sakin tempo',
      'An Osaka evening, outdoor walking and a calmer pace',
    ),
    ticketSteps: [
      LText(
        'Tarihli QR bileti resmî siteden al; yerinde yalnız aynı gün bileti bulunabilir ve tükenebilir.',
        'Buy a dated QR ticket online; the venue only offers same-day sales when available.',
      ),
      LText(
        'Saatler gün batımına göre mevsimsel değişir; aynı gün son giriş saatini kontrol et.',
        'Hours shift seasonally with sunset; check the final-entry time on the day.',
      ),
      LText(
        'Yağmur ve kuvvetli rüzgâr bazı eserleri kapatabilir; resmî duyuruyu aç.',
        'Rain and strong wind can suspend some works; check the official notice.',
      ),
      LText(
        'Rahat, suya dayanıklı ayakkabı; yazın sivrisinek koruması ve su hazırla.',
        'Wear comfortable weather-ready shoes and bring water and insect protection in summer.',
      ),
    ],
    timeline: [
      ExperienceTimelineStop(
        time: '-20 dk',
        title: LText('Nagai Park', 'Nagai Park'),
        detail: LText(
          'Metro Nagai Exit 3’ten yaklaşık 10 dk yürü; park içinde girişe devam et.',
          'Walk about 10 minutes from Metro Nagai Exit 3, then continue inside the park.',
        ),
      ),
      ExperienceTimelineStop(
        time: '0:00–0:30',
        title: LText('Gözün karanlığa alışsın', 'Let your eyes adjust'),
        detail: LText(
          'İlk eserlerde acele etme; gece görüşü oturdukça ışık detayları belirginleşir.',
          'Do not rush the first works; details emerge as your night vision settles.',
        ),
      ),
      ExperienceTimelineStop(
        time: '0:30–1:20',
        title: LText('Orman ve göl', 'Forest and lake'),
        detail: LText(
          'Resonating Trees ve göl eserlerini rota yerine hava durumuna göre sırala.',
          'Order the forest and lake works around conditions rather than a fixed route.',
        ),
      ),
      ExperienceTimelineStop(
        time: '1:20–2:00',
        title: LText('Yavaş final', 'Slow finale'),
        detail: LText(
          'Aynı eser rüzgâr ve insanlarla değişir; ikinci kez bakıp çıkışa dön.',
          'Works change with wind and people; revisit one before heading out.',
        ),
      ),
    ],
    highlights: [
      ExperienceHighlight(
        title: LText('Resonating Trees', 'Resonating Trees'),
        duration: LText('30–40 dk', '30–40 min'),
        strategy: LText(
          'Işığın başka ziyaretçiler ve hayvanlarla yayılmasını izlemek için durup bekle.',
          'Pause and watch light propagate through visitors and wildlife.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Oike Lake', 'Oike Lake'),
        duration: LText('20–30 dk', '20–30 min'),
        strategy: LText(
          'Göl kenarında zemine dikkat et; flaş yerine gece modunu kullan.',
          'Watch your footing near the lake and use night mode rather than flash.',
        ),
      ),
      ExperienceHighlight(
        title: LText('Mevsimsel eserler', 'Seasonal works'),
        duration:
            LText('Programı aynı gün kontrol et', 'Check the day’s program'),
        strategy: LText(
          'Çiçeklenme, rüzgâr ve yağmur hangi eserin görünür olduğunu değiştirir.',
          'Bloom, wind and rain change which works are available.',
        ),
      ),
    ],
    tips: [
      LText(
        'Bu kapalı müze değildir; sıcak, yağmur ve yürüyüş temposunu ciddiye al.',
        'This is not an indoor museum; plan for heat, rain and walking.',
      ),
      LText(
        'Son giriş saati mevsimsel değişir ve geç kalana giriş verilmez.',
        'Final entry changes by season and late arrival is not admitted.',
      ),
      LText(
        'Nagai Park otoparkı yoğun olabilir; toplu taşıma daha güvenlidir.',
        'Nagai Park parking can be busy; public transport is more reliable.',
      ),
    ],
    officialUrl: 'https://www.teamlab.art/e/botanicalgarden/',
    reminderWindowId: 'teamlab-botanical',
  ),
];
