-- Bütçe tahmini için yıl bazlı birim maliyet tablosu.
--
-- Yapı: INI'nin aynısı — `section` + `key` + `value` (metin). Tüm tutarlar JPY.
-- Uygulama bu satırları çekip `section → {key: value}` haritası kurar ve
-- `UnitCostTable.fromSections` ile hesaplar (assets/data/unit_costs.ini ile
-- birebir uyumlu). Değerleri güvenilir backend/panel yazar; istemci YALNIZCA
-- okur. AI KULLANILMAZ.
create table if not exists public.unit_costs (
    section     text        not null,
    key         text        not null,
    value       text        not null,
    updated_at  timestamptz not null default now(),
    primary key (section, key)
);

alter table public.unit_costs enable row level security;

-- Birim maliyetler herkese açık okunabilir (anon + authenticated). Kişisel veri
-- içermez; bütçe ekranı offline'da bile son değeri (cache) kullanabilsin diye açık.
drop policy if exists "unit_costs_public_read" on public.unit_costs;
create policy "unit_costs_public_read"
  on public.unit_costs for select
  to anon, authenticated
  using (true);

-- Yazma yetkisi istemcide YOKtur. INSERT/UPDATE/DELETE için politika tanımlanmaz;
-- yalnızca service_role (panel/Edge Function) RLS'i baypas ederek yazar.

-- 2026 kalibrasyonu — assets/data/unit_costs.ini ile aynı değerlerle tohumlanır.
-- Çakışmada değeri günceller (idempotent seed).
insert into public.unit_costs (section, key, value) values
  ('meta', 'year', '2026'),
  ('meta', 'currency', 'JPY'),

  ('flight', 'adult_min', '85000'),
  ('flight', 'adult_max', '220000'),
  ('flight', 'child_min', '75000'),
  ('flight', 'child_max', '190000'),
  ('flight', 'oneway_factor', '0.70'),

  ('hotel', 'night_min', '11000'),
  ('hotel', 'night_max', '28000'),
  ('hotel', 'extra_person_min', '3000'),
  ('hotel', 'extra_person_max', '8000'),

  ('food', 'adult_min', '3500'),
  ('food', 'adult_max', '9000'),
  ('food', 'child_min', '2000'),
  ('food', 'child_max', '5500'),

  ('train', 'adult_base_min', '7000'),
  ('train', 'adult_base_max', '20000'),
  ('train', 'intercity_min', '9000'),
  ('train', 'intercity_max', '24000'),
  ('train', 'child_factor', '0.5'),

  ('taxi', 'day_min', '0'),
  ('taxi', 'day_max', '6000'),

  ('shopping', 'adult_min', '10000'),
  ('shopping', 'adult_max', '60000'),
  ('shopping', 'child_min', '5000'),
  ('shopping', 'child_max', '20000'),

  ('electronics', 'group_min', '0'),
  ('electronics', 'group_max', '150000'),

  ('attractions', 'adult_min', '1000'),
  ('attractions', 'adult_max', '5500'),
  ('attractions', 'child_min', '600'),
  ('attractions', 'child_max', '3500'),

  ('season', 'high_months', '3,4,5,10,11'),
  ('season', 'high_factor', '1.12'),
  ('season', 'default_factor', '1.0'),

  ('reference', 'ramen', '1200'),
  ('reference', 'sushi_set', '2800'),
  ('reference', 'konbini_meal', '850'),
  ('reference', 'coffee', '550'),
  ('reference', 'subway_ride', '210'),
  ('reference', 'taxi_start', '500'),
  ('reference', 'shinkansen_tokyo_kyoto', '14170'),
  ('reference', 'hotel_night_family', '22000'),
  ('reference', 'day_pass', '700'),
  ('reference', 'museum', '1500'),
  ('reference', 'theme_park', '10500'),
  ('reference', 'usj_1day', '8400'),
  ('reference', 'disney_1day', '10900')
on conflict (section, key) do update
  set value = excluded.value,
      updated_at = now();
