-- Hesap silme RPC — Apple App Store Guideline 5.1.1(v) uyumluluğu için.
--
-- Client `admin.deleteUser`'ı service_role key gerektirdiği için çağıramaz.
-- Onun yerine `security definer` bir Postgres fonksiyonu ile kullanıcı yalnızca
-- kendi (auth.uid()) hesabını silebilir. RLS bypass edilir çünkü siliş
-- kullanıcının kendi haklarıyla değil, fonksiyonun sahibi (postgres) haklarıyla
-- olur; ancak fonksiyon `auth.uid()` kontrolü yaparak yalnızca aktif kullanıcıyı
-- hedefler.
--
-- Silinen veriler:
--   - public.plans (owner_id = uid)  → CASCADE ile ilişkili checklist, reminders
--   - public.pre_departure_checklist (owner_id = uid)
--   - public.reminders (owner_id = uid, varsa)
--   - auth.users (id = uid) → tüm identity/session kayıtları
--
-- Kullanım (client):
--   final res = await _client.rpc('delete_current_user');
--   await _client.auth.signOut(); // lokal session temizle
--
-- Idempotent: aynı kullanıcı tekrar çağırırsa `auth.uid()` null döner → hata.

create or replace function public.delete_current_user()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'not authenticated' using errcode = 'PGRST';
  end if;

  -- Kullanıcının uygulama içi verilerini sil (varsa; tablolar yoksa geç).
  begin
    delete from public.plans where owner_id = uid;
  exception when undefined_table then null; end;

  begin
    delete from public.pre_departure_checklist where owner_id = uid;
  exception when undefined_table then null; end;

  begin
    delete from public.reminders where owner_id = uid;
  exception when undefined_table then null; end;

  -- Son olarak auth kullanıcı kaydını sil. auth.users foreign key cascade'i ile
  -- identity/session/mfa kayıtları da temizlenir.
  delete from auth.users where id = uid;
end;
$$;

-- Sadece giriş yapmış kullanıcılar çağırabilir.
revoke all on function public.delete_current_user() from public;
grant execute on function public.delete_current_user() to authenticated;

comment on function public.delete_current_user() is
  'Aktif kullanıcı kendi hesabını ve tüm verilerini siler (App Store 5.1.1(v)).';
