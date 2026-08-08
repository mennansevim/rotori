-- Fiyat etiketi tarayıcı günlük kullanım limiti.
--
-- Her kullanıcı günlük tarama sayısı burada tutulur.
-- Free user: 10/gün, Premium user: limitsiz (Edge Function'da kontrol).
-- INSERT yalnızca Edge Function (service_role) üzerinden yapılır,
-- böylece istemci limiti bypass edemez.
create table if not exists public.daily_scans (
    user_id     uuid        not null,
    scan_date   date        not null default current_date,
    scan_count  integer     not null default 1,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    primary key (user_id, scan_date)
);

create index if not exists daily_scans_date_idx
  on public.daily_scans (scan_date desc);

alter table public.daily_scans enable row level security;

-- Herkes kendi günlük limitini okuyabilir.
drop policy if exists "daily_scans_self_read" on public.daily_scans;
create policy "daily_scans_self_read"
  on public.daily_scans for select
  to authenticated
  using (auth.uid() = user_id);

-- INSERT/UPDATE yalnızca Edge Function (service_role bypass) üzerinden.
-- İstemci DML politikası tanımlanmaz → default deny.

-- Kullanıcı premium mu?
create or replace function public.is_premium(_user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select coalesce(
    (select (raw_user_meta_data->>'premium')::boolean
     from auth.users
     where id = _user_id),
    false
  );
$$;

-- Günlük limit kontrolü: free 10, premium 100.
-- Edge Function tarafından çağrılır; service_role ile çalışır.
create or replace function public.check_daily_scan_limit(
  _user_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  _today        date := current_date;
  _is_premium   boolean;
  _current      integer;
  _max_free     integer := 10;
  _max_premium  integer := 100;
  _max          integer;
  _allowed      boolean;
begin
  select public.is_premium(_user_id) into _is_premium;

  _max := case when _is_premium then _max_premium else _max_free end;

  select scan_count into _current
  from public.daily_scans
  where user_id = _user_id and scan_date = _today;

  if _current is null then
    _current := 0;
  end if;

  _allowed := _current < _max;

  return jsonb_build_object(
    'allowed', _allowed,
    'remaining', greatest(0, _max - _current),
    'premium', _is_premium,
    'max', _max,
    'scannedToday', _current
  );
end;
$$;

-- Tarama sayısını arttır. Sadece check geçtikten sonra çağrılır.
create or replace function public.increment_scan_count(_user_id uuid)
returns void
language sql
security definer
as $$
  insert into public.daily_scans (user_id, scan_date, scan_count)
  values (_user_id, current_date, 1)
  on conflict (user_id, scan_date)
  do update set
    scan_count = public.daily_scans.scan_count + 1,
    updated_at = now();
$$;

-- Cache: aynı model aynı gün tekrar taranırsa API çağrısı yapma.
create table if not exists public.tag_cache (
    product_model   text        not null,
    normalized_key  text        not null,
    result_json     jsonb       not null,
    source          text        not null default 'llm',
    created_at      timestamptz not null default now(),
    primary key (normalized_key)
);

alter table public.tag_cache enable row level security;

drop policy if exists "tag_cache_public_read" on public.tag_cache;
create policy "tag_cache_public_read"
  on public.tag_cache for select
  to authenticated, anon
  using (true);
