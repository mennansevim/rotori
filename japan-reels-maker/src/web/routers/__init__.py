"""FastAPI router paketi — domain bazında bölünmüş route'lar.

Yaklaşım: strangler pattern. app.py hâlâ ana route dosyası; her PR'da
küçük bir grup taşınıyor. Yeni router'lar burada kayıtlı olur ve app.py
`include_router(...)` ile bağlar.

Sözleşme değişmez: taşınan bir route'un URL'i, HTTP metodu, request/
response şeması aynen kalır. Contract testler (tests/) bunu kilitler.
"""
