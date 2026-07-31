-- Kullanıcıların planlama hatalarını güvenli ve moderasyonlanabilir biçimde
-- gönderebilmesi için destek kayıtları.
create table if not exists public.bug_reports (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references auth.users(id) on delete cascade,
    plan_id       uuid references public.plans(id) on delete set null,
    category      text not null,
    message       text not null check (char_length(message) between 3 and 4000),
    contact_email text,
    context       jsonb not null default '{}'::jsonb,
    status        text not null default 'new'
                  check (status in ('new', 'triaged', 'resolved', 'ignored')),
    created_at    timestamptz not null default now()
);

create index if not exists bug_reports_created_idx
  on public.bug_reports (created_at desc);
create index if not exists bug_reports_user_idx
  on public.bug_reports (user_id, created_at desc);

alter table public.bug_reports enable row level security;

drop policy if exists "bug_reports_authenticated_insert" on public.bug_reports;
create policy "bug_reports_authenticated_insert"
  on public.bug_reports for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "bug_reports_own_select" on public.bug_reports;
create policy "bug_reports_own_select"
  on public.bug_reports for select
  to authenticated
  using (auth.uid() = user_id);
