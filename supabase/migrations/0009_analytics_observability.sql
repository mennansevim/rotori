-- Rotori ürün analitiği ve rota üretim gözlemlenebilirliği.
--
-- Crash/stack trace Sentry'de tutulur. Bu tablolar yalnız Rotori'nin kendi
-- Supabase projesindeki düşük hassasiyetli ürün olayları ile gizlilikten
-- arındırılmış rota request/response JSON snapshot'larını saklar.

create table if not exists public.analytics_events (
    event_id      uuid primary key,
    user_id       uuid not null references auth.users(id) on delete cascade,
    session_id    uuid not null,
    event_name    text not null check (event_name ~ '^[a-z0-9_]{2,80}$'),
    screen        text check (screen is null or char_length(screen) <= 120),
    properties    jsonb not null default '{}'::jsonb
                  check (jsonb_typeof(properties) = 'object'),
    occurred_at   timestamptz not null,
    received_at   timestamptz not null default now()
);

create index if not exists analytics_events_name_time_idx
  on public.analytics_events (event_name, occurred_at desc);
create index if not exists analytics_events_user_time_idx
  on public.analytics_events (user_id, occurred_at desc);
create index if not exists analytics_events_session_idx
  on public.analytics_events (session_id, occurred_at);

create table if not exists public.route_generation_logs (
    event_id      uuid primary key,
    attempt_id    uuid not null,
    user_id       uuid not null references auth.users(id) on delete cascade,
    session_id    uuid not null,
    phase         text not null
                  check (phase in ('started', 'succeeded', 'failed')),
    request_json  jsonb not null check (jsonb_typeof(request_json) = 'object'),
    route_json    jsonb check (
                    route_json is null or jsonb_typeof(route_json) = 'object'
                  ),
    metrics       jsonb not null default '{}'::jsonb
                  check (jsonb_typeof(metrics) = 'object'),
    error_code    text check (
                    error_code is null or char_length(error_code) <= 120
                  ),
    occurred_at   timestamptz not null,
    received_at   timestamptz not null default now(),
    check (phase <> 'succeeded' or route_json is not null),
    unique (attempt_id, phase)
);

create index if not exists route_generation_logs_user_time_idx
  on public.route_generation_logs (user_id, occurred_at desc);
create index if not exists route_generation_logs_phase_time_idx
  on public.route_generation_logs (phase, occurred_at desc);
create index if not exists route_generation_logs_attempt_idx
  on public.route_generation_logs (attempt_id, occurred_at);

alter table public.analytics_events enable row level security;
alter table public.route_generation_logs enable row level security;

-- İstemci yalnız kendi kimliğiyle append yapabilir. Okuma, güncelleme ve silme
-- politikası yoktur; analiz Supabase Dashboard veya service_role ile yapılır.
drop policy if exists "analytics_events_self_insert"
  on public.analytics_events;
create policy "analytics_events_self_insert"
  on public.analytics_events for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "route_generation_logs_self_insert"
  on public.route_generation_logs;
create policy "route_generation_logs_self_insert"
  on public.route_generation_logs for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on table public.analytics_events from anon, authenticated;
revoke all on table public.route_generation_logs from anon, authenticated;
grant insert on table public.analytics_events to authenticated;
grant insert on table public.route_generation_logs to authenticated;
grant all on table public.analytics_events to service_role;
grant all on table public.route_generation_logs to service_role;

comment on table public.analytics_events is
  'Append-only first-party product events; no ad profiling or GPS payload.';
comment on table public.route_generation_logs is
  'Append-only route generation request/result snapshots. Hotels, tickets, flights, notes, contact fields, dietary contents and precise GPS are excluded by the client contract.';
