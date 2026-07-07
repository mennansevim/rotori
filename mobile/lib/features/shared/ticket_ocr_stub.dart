// Web/varsayılan fallback — OCR mevcut değil. Boş metin döner; çağıran taraf
// (place_detail_sheet) bunu "otomatik metin çıkarımı yalnızca cihazda çalışır"
// notuyla ele alır.
Future<String> extractTicketText(String imagePath) async => '';
