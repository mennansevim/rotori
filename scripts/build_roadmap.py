#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Japonya Reels içerik yol haritası + reels kataloğu üretici (Excel .xlsx)."""
import os
import csv

OUT_XLSX = os.path.join("content", "Japonya_Reels_Roadmap.xlsx")
OUT_CSV_DIR = os.path.join("content", "csv_fallback")

# ---------------------------------------------------------------------------
# 00 BAŞLA
# ---------------------------------------------------------------------------
INTRO_ROWS = [
    ["JAPONYA REELS – İÇERİK YOL HARİTASI & REELS KATALOĞU", ""],
    ["", ""],
    ["Bu dosya ne işe yarar?",
     "Yeni açılan Instagram/TikTok kanalını sıfırdan büyütmek için hazır bir üretim planı. "
     "Her sekme bir işi görür: hedefler, konu kategorileri, çekim fikirleri, haftalık takvim ve faz faz büyüme planı."],
    ["Nasıl kullanılır?",
     "1) '03 Reels Kataloğu' senin üretim havuzun. 2) 'Öncelik 1' + 'Elde çekim VAR' olanlardan başla. "
     "3) '04 Paylaşım Takvimi'ne göre haftalık çek/kurgula. 4) Durum sütununu güncelle. 5) '01 Hedefler'e göre ölç."],
    ["", ""],
    ["KANAL PROFİLİ", ""],
    ["Kişi", "Mennan – ailesiyle (eş + çocuklar) gezen Türk gezi içerik üreticisi"],
    ["Gezi", "Mayıs 2026, 13 gün Japonya: Tokyo 6 gece (Ikebukuro), Osaka üssü (Namba), Kyoto + Nara günübirlik"],
    ["Kitle", "20–40 yaş Türk gezi izleyicisi; 'biz gitmeden bilseydik' tüyoları arayan kesim"],
    ["Ton", "Birinci ağız, samimi ama otoriter; klişe yok, spesifik ve uygulanabilir"],
    ["Dil", "Türkçe"],
    ["Durum (kanal)", "YENİ kanal, 0 takipçi. Amaç: tutarlı, algoritma-dostu reels ile büyüme"],
    ["", ""],
    ["EFSANE / RENK & KOD AÇIKLAMALARI", ""],
    ["Öncelik 1", "Hemen üretilebilir; güçlü hook + mevcut çekim var. Önce bunları yayınla."],
    ["Öncelik 2", "Orta vadeli; kısmi çekim veya biraz kurgu/emek ister."],
    ["Öncelik 3", "İleri faz; ek çekim, iş birliği veya kanal olgunlaşınca."],
    ["Elde çekim: Var", "İlgili footage arşivde mevcut, bugün kurgulanabilir."],
    ["Elde çekim: Kısmi", "Biraz görsel var ama tamamlamak için ek klip/grafik gerekir."],
    ["Elde çekim: Çekilecek", "Yeni çekim gerektirir (Türkiye'de veya sonraki gezide)."],
    ["Elde çekim: Stok/Grafik", "Telifsiz stok görsel, harita, ekran kaydı veya metin kartı ile yapılır."],
    ["Durum akışı", "Fikir → Planlandı → Çekildi → Üretildi → Yayınlandı"],
    ["Format kısaltmaları", "Montaj / Tek Görsel+Not / Seslendirme (voiceover) / Talking-head"],
    ["", ""],
    ["MEVCUT ÇEKİM ENVANTERİ (klip sayısı)",
     "Tokyo Disneyland 73 • Nara Geyikleri 37 • Tokyo Havadan 37 • Kyoto 23 • Universal Studios Japan 21 • "
     "Osaka Havadan 12 • Kyoto Fushimi Inari 6 • Osaka Kalesi 6 • Tokyo Tower 5 • Pokemon Center 3 • "
     "Universal-Nintendo World 3 • Shinkansen & Fuji 2 • Tekli: Dotonbori, Konbini(7-Eleven), Uniqlo, "
     "Japon Tuvaletleri, Shibuya Meydanı, Kyoto Tapınakları"],
]

# ---------------------------------------------------------------------------
# 01 HEDEFLER & KPI
# ---------------------------------------------------------------------------
KPI_HEADERS = [
    "Faz", "Hedef Takipçi", "Zaman Aralığı (ay)", "Haftalık Paylaşım",
    "Hedef Ort. İzlenme", "Hedef Save/Share Oranı", "Ana KPI", "1 Cümlelik Strateji",
]
KPI_ROWS = [
    ["Faz 0 – Kurulum", "0 → 50", "0–0,5 ay (2 hafta)", "Hazırlık + 9'luk grid",
     "—", "—", "Profil, bio, seri kimliği, ilk 9 reel hazır",
     "Yayına 'boş profil' değil, hazır bir kimlik ve ilk seri ile çık."],
    ["Faz 1 – Format Bulma", "0 → 1.000", "1–2 ay", "5–7 reel",
     "3.000–8.000 izlenme", "Save %2+ / Share %1+", "Tutma oranı (ilk 3 sn) ve tamamlanma",
     "Tek bir güçlü formatı bul; hook + altyazı + tutarlılıkla tekrar et."],
    ["Faz 2 – İvme", "1.000 → 10.000", "2–4 ay", "6–7 reel",
     "15.000–50.000 izlenme", "Save %4+ / Share %2+", "Save + paylaşım + profil ziyareti",
     "Seri + trend ses + 'kaydet' değeri yüksek rehber reel'lere yüklen."],
    ["Faz 3 – Ölçek", "10.000 → 100.000", "4–9 ay", "5–7 reel + öne çıkanlar",
     "50.000–250.000 izlenme", "Save %5+ / Share %3+", "Tekrar izlenme, iş birliği, marka",
     "Kazanan formatları ölçekle; iş birlikleri ve öne çıkanlarla otorite kur."],
]

# ---------------------------------------------------------------------------
# 02 KATEGORİLER
# ---------------------------------------------------------------------------
CAT_HEADERS = [
    "Kategori", "Açıklama", "Hedef Kitle / Amaç", "Örnek Seri Adı",
    "Öncelik", "Elde Çekim Var mı?", "Not",
]
CAT_ROWS = [
    ["Japonya'ya Gidiş Rehberi",
     "Gidiş öncesi tüm hazırlık: vize, uçak bileti, bütçe, ne zaman gidilir, JR Pass, pocket wifi/eSIM, valiz.",
     "Gitmeyi planlayan; en yüksek arama/kaydetme hacmi", "Gitmeden Bil", 1, "Stok/Grafik",
     "Ekran kaydı, harita ve metin kartıyla üretilir; footage şart değil. Yüksek save potansiyeli."],
    ["Shinkansen Rehberi",
     "Hızlı tren mantığı: bilet alma, JR Pass mı tek bilet mi, rezerve/serbest vagon, bavul kuralı, Fuji manzarası tarafı.",
     "Şehirler arası ulaşacaklar", "Shinkansen 101", 2, "Kısmi",
     "Elde 'Shinkansen & Fuji' 2 klip var; ekran/grafikle güçlendir."],
    ["Varışta İlk Yapılacaklar",
     "İnince ilk 3 saat: Suica/IC kart, havalimanı→şehir transfer, konbini, ATM/para, pocket wifi teslim.",
     "Yeni inen; panik anını çözer", "İlk 3 Saat", 1, "Kısmi",
     "Konbini + Shibuya + havadan klipler destekler; kalanı grafik/ekran kaydı."],
    ["Konaklama",
     "Nerede kalınır: bölge seçimi (Ikebukuro/Namba), otel tipleri, kapsül, check-in kültürü, oda boyutu gerçeği.",
     "Rota kuranlar", "Nerede Kalmalı", 2, "Çekilecek",
     "Oda içi çekim yoksa stok + metin kartı; sonraki gezide çek."],
    ["Yeme-İçme & Konbini",
     "Konbini efsanesi (7-Eleven), gerçek fiyatlar, ne yenir, restoran adabı, vejetaryen/çocuk seçenekleri.",
     "Herkes; yüksek etkileşim", "Konbini Turu", 1, "Var",
     "Elde Konbini(7-Eleven) klibi var; Dotonbori ile beslenir."],
    ["Kültür & Görgü Kuralları",
     "Yapılmaz/yapılır: yürürken yemek, ses, sıra, bahşiş yok, tapınak adabı, çöp kuralı.",
     "Saygılı gezmek isteyen", "Yapma! (Japonya)", 1, "Kısmi",
     "Tapınak/sokak klipleriyle örneklenir; kalanı metin kartı."],
    ["Bütçe & Tasarruf",
     "13 günün gerçek maliyet mantığı, para tuzakları, ücretsiz aktiviteler, tax-free, IC kart avantajı.",
     "Bütçesini merak eden", "Kaç Paraya", 1, "Stok/Grafik",
     "Grafik + ekran kaydı; uydurma değil aralık/mantık ver."],
    ["Ulaşım & Metro",
     "Metro/JR karmaşası, doğru uygulama, IC kart, aktarma korkusu, son tren, taksiden kaçınma.",
     "İlk kez metro kullanacak", "Metroda Kaybolma", 1, "Kısmi",
     "Havadan + sokak klipleri + uygulama ekran kaydı."],
    ["Alışveriş & Tax-Free",
     "Nereden ne alınır, tax-free şartı, Uniqlo/Don Quijote, elektronik, hediyelik, valiz payı.",
     "Alışveriş odaklı", "Ne Alınır", 2, "Kısmi",
     "Uniqlo klibi var; ürün çekimi eklenebilir."],
    ["Aile ile Japonya",
     "Çocukla gezmek: mesafeler, bebek dostu yerler, tuvalet, yemek seçiciliği, tema parkı stratejisi.",
     "Ailece gidecekler (kanalın kimliği)", "Çocukla Japonya", 1, "Var",
     "Disney/Universal/Nara footage bol; kanalın en özgün açısı."],
    ["Tema Parkları (Disney/Universal)",
     "Disneyland & Universal (Nintendo World) tüyoları: bilet, sıra/erken giriş, hangi yaşa uygun, bütçe.",
     "Park planlayan aileler", "Park Günü", 1, "Var",
     "En zengin arşiv: Disneyland 73, USJ 21, Nintendo 3."],
    ["Şehir Rehberi: Tokyo",
     "Tokyo'yu bölgelerle çöz: Shibuya, Ikebukuro, kule, havadan siluet, 6 gecelik rota.",
     "Tokyo'ya gidecek", "Tokyo Rotası", 1, "Var",
     "Tokyo Havadan 37, Tower 5, Shibuya, Pokemon Center mevcut."],
    ["Şehir Rehberi: Osaka",
     "Osaka enerjisi: Dotonbori, Namba üssü, Osaka Kalesi, yemek şehri, günübirlik merkezi.",
     "Osaka'ya gidecek", "Osaka Rotası", 1, "Var",
     "Osaka Havadan 12, Kale 6, Dotonbori klibi var."],
    ["Şehir Rehberi: Kyoto & Nara",
     "Kyoto tapınakları + Fushimi Inari + Nara geyikleri; günübirlik nasıl planlanır.",
     "Kültür/tapınak gezecek", "Kyoto & Nara", 1, "Var",
     "Kyoto 23, Fushimi Inari 6, Nara Geyikleri 37 – çok güçlü."],
    ["Gizli Tüyolar",
     "Az bilinen pratik püf noktalar: ücretsiz bagaj dolabı, en iyi manzara noktası, sıra saatleri.",
     "Deneyim arayan", "Kimse Söylemiyor", 1, "Kısmi",
     "Kısa, çarpıcı; mevcut klip + metin kartı."],
    ["Uygulamalar & Teknoloji",
     "Olmazsa olmaz uygulamalar (harita, çeviri, ulaşım), eSIM vs pocket wifi, offline harita.",
     "Teknik hazırlık yapan", "Telefonuna Yükle", 1, "Stok/Grafik",
     "Telefon ekran kaydı; footage gerekmez, yüksek save."],
    ["Dil & İletişim",
     "Sıfır Japonca ile idare: 10 kelime, çeviri app, jestler, İngilizce nerede işe yarar.",
     "Dil endişesi olan", "10 Kelime", 2, "Çekilecek",
     "Talking-head veya metin kartı; kolay üretim."],
    ["Tapınaklar & Kültürel Alanlar",
     "Tapınak/türbe farkı, ziyaret adabı, arıtma ritüeli, fotoğraf kuralları, en etkileyici anlar.",
     "Kültür meraklısı", "Tapınak Adabı", 2, "Var",
     "Fushimi Inari, Kyoto Tapınakları klipleri mevcut."],
    ["Fotoğraf & İçerik Spotları",
     "En iyi kare noktaları, saat, açı; havadan siluetler; kalabalıktan kaçış saatleri.",
     "İçerik/foto çekecek gezginler", "Buradan Çek", 2, "Var",
     "Havadan + Tower + Shibuya klipleri ideal."],
    ["Japonya Mitleri & Yanlış Bilinenler",
     "Pahalı mı, tehlikeli mi, herkes İngilizce biliyor mu gibi klişeleri gerçekle çürüt.",
     "Kararsız / önyargılı izleyici", "Doğru mu Yanlış mı", 1, "Kısmi",
     "Çarpıcı hook; metin kartı + destek klip."],
]
