/// Dakika aritmetiği için paylaşılan yuvarlama sözleşmesi.
///
/// Saha modeli süreleri çarpan zinciriyle büyütür (trafik 1.30 × kalabalık
/// 1.15 × pass 1.20 …). İkili kayan noktada bu zincir hata biriktirir:
/// `100 * 1.10` → `110.00000000000001` ve düz `ceil()` 111 döner. Tek bir
/// dakikalık kayma, tampon hesabına ve testlere sızar.
///
/// Bu modül tek kuralı merkezîleştirir: **yukarı yuvarla, ama kayan nokta
/// gürültüsünü yut.** Süre tahmininde iyimserlik saha hatası üretir; bu yüzden
/// yuvarlama yönü her zaman yukarıdır.
library;

/// Kayan nokta gürültüsünü yutan yukarı yuvarlama toleransı.
///
/// Gerçek kesirlere (110.3) dokunmayacak kadar küçük, çarpan zinciri hatasını
/// (1e-14 mertebesi) yutacak kadar büyük.
const double kMinuteEpsilon = 1e-9;

/// Dakikayı yukarı yuvarlar; negatif ve sıfır girdide 0 döner.
int ceilMinutes(double value) {
  if (value <= 0) return 0;
  return (value - kMinuteEpsilon).ceil();
}

/// Bir süreyi çarpanla büyütür. Çarpan 1 veya altındaysa süre değişmez —
/// modeller süre **kısaltmaz**, yalnız gerçekçi biçimde uzatır.
int scaleMinutes(int minutes, double multiplier) {
  if (minutes <= 0 || multiplier <= 1) return minutes;
  final scaled = ceilMinutes(minutes * multiplier);
  return scaled > minutes ? scaled : minutes;
}
