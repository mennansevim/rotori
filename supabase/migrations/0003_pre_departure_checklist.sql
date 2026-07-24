-- ============================================================
-- Japan-Trip · Yolculuk öncesi hazırlık listesi
-- ============================================================
-- Amaç:
--   - Kullanıcı yolculuk tarihine yaklaştığında (varsayılan 7 gün önce)
--     "gitmeden önce" tarzı bir kontrol listesine ihtiyaç duyar. Preset
--     maddeler (pasaport, Visit Japan Web, powerbank, eSIM, JR Pass…) client
--     tarafında i18n anahtarlarıyla tanımlıdır (bkz. domain/pre_departure_checklist.dart);
--     bu tabloda YALNIZCA kullanıcı-durumu (checked/uncheck) + eklediği özel
--     maddeler + görünme eşiği (days_before) senkronlanır.
--
-- NOT (deploy):
--   Bu migration otomatik uygulanmaz — Supabase live projede
--   `supabase db push` (veya SQL editor) ile MANUEL uygulanır. Dosya
--   idempotent yazılmıştır; birden çok kez çalıştırmak güvenlidir.

-- ------------------------------------------------------------
-- 1) pre_departure_checklists — plan başına tek satır
-- ------------------------------------------------------------
create table if not exists public.pre_departure_checklists (
    id           uuid        primary key default gen_random_uuid(),
    trip_id      uuid        not null references public.plans(id) on delete cascade,
    -- items: [{ "id": "...", "emoji": "...", "label_tr": "...", "label_en": "...",
    --          "desc_tr": null, "desc_en": null, "checked": false, "custom": false }, ...]
    -- Preset maddelerde label/desc alanları client i18n sözlüğünden çözüleceği için
    -- boş bırakılabilir; custom=true satırlarda kullanıcı metni saklanır.
    items        jsonb       not null default '[]'::jsonb,
    days_before  integer     not null default 7 check (days_before between 1 and 30),
    updated_at   timestamptz not null default now(),
    unique (trip_id)
);

comment on table  public.pre_departure_checklists is
  'Plan bazlı yolculuk öncesi hazırlık listesi durumu (checked, custom maddeler, görünme eşiği).';
comment on column public.pre_departure_checklists.items is
  'JSON dizisi: {id, emoji, label_tr, label_en, desc_tr, desc_en, checked, custom}. Preset maddelerin metinleri client tarafında çözülür.';
comment on column public.pre_departure_checklists.days_before is
  'Bandın viewer üstünde belirmeye başladığı gün eşiği (1..30).';

-- Trip bazlı hızlı çekim
create index if not exists pdc_trip_idx
  on public.pre_departure_checklists (trip_id);

-- ------------------------------------------------------------
-- 2) updated_at trigger — mevcut public.touch_updated_at()
-- ------------------------------------------------------------
drop trigger if exists pdc_touch_updated_at on public.pre_departure_checklists;
create trigger pdc_touch_updated_at
  before update on public.pre_departure_checklists
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------
-- 3) RLS — yalnızca trip sahibi okur/yazar
-- ------------------------------------------------------------
alter table public.pre_departure_checklists enable row level security;

drop policy if exists pdc_owner_select on public.pre_departure_checklists;
drop policy if exists pdc_owner_insert on public.pre_departure_checklists;
drop policy if exists pdc_owner_update on public.pre_departure_checklists;
drop policy if exists pdc_owner_delete on public.pre_departure_checklists;

create policy pdc_owner_select
  on public.pre_departure_checklists for select
  using (
    exists (
      select 1 from public.plans p
      where p.id = pre_departure_checklists.trip_id
        and p.owner_id = auth.uid()
    )
  );

create policy pdc_owner_insert
  on public.pre_departure_checklists for insert
  with check (
    exists (
      select 1 from public.plans p
      where p.id = pre_departure_checklists.trip_id
        and p.owner_id = auth.uid()
    )
  );

create policy pdc_owner_update
  on public.pre_departure_checklists for update
  using (
    exists (
      select 1 from public.plans p
      where p.id = pre_departure_checklists.trip_id
        and p.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.plans p
      where p.id = pre_departure_checklists.trip_id
        and p.owner_id = auth.uid()
    )
  );

create policy pdc_owner_delete
  on public.pre_departure_checklists for delete
  using (
    exists (
      select 1 from public.plans p
      where p.id = pre_departure_checklists.trip_id
        and p.owner_id = auth.uid()
    )
  );

-- ------------------------------------------------------------
-- 4) Realtime yayınına ekle (diğer cihazlardan canlı senkron için)
-- ------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'pre_departure_checklists'
    ) then
      execute 'alter publication supabase_realtime add table public.pre_departure_checklists';
    end if;
  end if;
end $$;
