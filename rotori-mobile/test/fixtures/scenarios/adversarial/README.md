# Adversarial regresyon senaryoları

Section B.5. Bu 7 senaryo her koşumda çalışır; birinin fail'i ilgili kural için
prompt patch'i gerektirir (`docs/ROUTE_OPT_TEST_PROMPT.md` Section 5).

Her dosya bir tam `RoutePlanScenario` JSON'udur; şu an boş stub — `activities`
ve `routeMatrix` içeriğiyle doldurulana kadar test runner "TODO: fixture"
olarak atlar.

| ID | Odak | Notlar |
|---|---|---|
| A1 | Kyoto kapanış vs. rezervasyon | 3 tapınak aynı cluster, 1 restoran 19:00 fixed, 1 tapınak 17:00 kapanış. Tapınak kapanış öncesi, akşam restorana. |
| A2 | Tokyo çift cluster | Shibuya + Asakusa; model cluster'ı bölmemeli. |
| A3 | Hakone gün trip | Odawara başlangıç, ryokan bitiş. Ropeway 17:00 kapanır, onsen 22:00 kapanır. Ropeway öğleden önce, onsen dinner sonrası. |
| A4 | Fizibilitesiz | 8 aktivite, gün toplam 6 saat. Model `dropped[]` üretmeli, tıkıştırmamalı. |
| A5 | Öğle yemeği yok | Yalnız 1 restoran ve o 20:00. Model synthetic:meal 12:00–13:00 eklemeli ya da warnings ile bildirmeli. |
| A6 | Metro aksaklığı | Bazı legler `reliability < 0.6`; taksi alternatifi varsa taksi tercih edilmeli. |
| A7 | Erken kapanış | `dayEnd = 20:00`; dinner 18:00–19:45 arasına sıkışmalı. |
