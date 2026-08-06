/// Gün içi rota/aktivite zaman penceresi (yerel duvar saati dakikaları).
///
/// Not: Uçuş/otel gibi sabit ve kilitli aktiviteler bu pencerenin dışında
/// kalabilir; bu sınır esnek aktivite/rota optimizasyonu için kullanılır.
const int kRouteStartHour = 9;
const int kRouteEndHour = 20;

const int kRouteStartMinuteOfDay = kRouteStartHour * 60;
const int kRouteEndMinuteOfDay = kRouteEndHour * 60;
