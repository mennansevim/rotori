-- Canlı fiyat çevirici için kur tablosu.
--
-- Normalizasyon: her satır `1 base_currency = rate target_currency`.
-- Bu üründe base her zaman 'JPY', target kullanıcı seçimidir (TRY/USD/...).
-- Değerleri güvenilir bir backend / Edge Function yazar; istemci YALNIZCA okur.
create table if not exists public.exchange_rates (
    base_currency   text        not null,
    target_currency text        not null,
    rate            numeric     not null check (rate > 0),
    source          text        not null default 'provider',
    fetched_at      timestamptz not null default now(),
    primary key (base_currency, target_currency)
);

create index if not exists exchange_rates_fetched_idx
  on public.exchange_rates (fetched_at desc);

alter table public.exchange_rates enable row level security;

-- Kur verisi herkese açık okunabilir (anon + authenticated). Kişisel veri
-- içermez; kamera ekranı offline'da bile son değeri alabilsin diye açık.
drop policy if exists "exchange_rates_public_read" on public.exchange_rates;
create policy "exchange_rates_public_read"
  on public.exchange_rates for select
  to anon, authenticated
  using (true);

-- Yazma yetkisi istemcide YOKtur. INSERT/UPDATE/DELETE için hiçbir politika
-- tanımlanmaz; yalnızca service_role (Edge Function) RLS'i baypas ederek yazar.
