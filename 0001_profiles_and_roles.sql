-- Toolshed Rentals: roles (customer / staff / admin) with Row Level Security.
-- Run in the Supabase SQL editor (project ophgpdwzoeuheshcfrrc) or `supabase db push`.
-- Safe to run more than once.

-- 1. Role type -------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('customer', 'staff', 'admin');
  end if;
end $$;

-- 2. Profiles table --------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  role       public.app_role not null default 'customer',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- 3. Helpers: role checks ----------------------------------------------------
-- SECURITY DEFINER so policies can check the caller's role without recursing
-- into the profiles table's own RLS.
create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() = 'admin', false);
$$;

-- Staff includes admins. Use this for "staff or above" policies on future tables.
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() in ('staff', 'admin'), false);
$$;

revoke all on function public.current_app_role() from public;
revoke all on function public.is_admin()         from public;
revoke all on function public.is_staff()         from public;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.is_admin()         to authenticated;
grant execute on function public.is_staff()         to authenticated;

-- 4. Auto-create a profile when someone signs up ---------------------------
-- New accounts are ALWAYS 'customer'. Nobody can sign up as staff or admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'customer')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill profiles for accounts that already exist.
insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do nothing;

-- 5. RLS policies ----------------------------------------------------------
drop policy if exists "profiles_select_own"   on public.profiles;
drop policy if exists "profiles_select_admin" on public.profiles;
drop policy if exists "profiles_update_admin" on public.profiles;

-- Everyone can read their own profile.
create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

-- Admins can read every profile.
create policy "profiles_select_admin"
  on public.profiles for select
  to authenticated
  using (public.is_admin());

-- Only admins can update profiles (this is how roles get changed).
-- There is deliberately NO insert or delete policy: profiles are created by
-- the signup trigger and removed by cascade from auth.users.
create policy "profiles_update_admin"
  on public.profiles for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 6. Guard rails on role changes -------------------------------------------
-- Only an admin can change a role, and an admin cannot change their own role
-- (prevents locking everyone out). The SQL editor / service role has
-- auth.uid() = null and is allowed, which is how the first admin is made.
create or replace function public.protect_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role then
    if auth.uid() is null then
      return new;
    end if;

    if not public.is_admin() then
      raise exception 'Only an admin can change roles';
    end if;

    if old.id = auth.uid() then
      raise exception 'You cannot change your own role';
    end if;
  end if;

  -- id, email and created_at are managed by the system, never by clients.
  new.id := old.id;
  new.email := old.email;
  new.created_at := old.created_at;
  return new;
end;
$$;

drop trigger if exists profiles_protect_role_change on public.profiles;
create trigger profiles_protect_role_change
  before update on public.profiles
  for each row execute function public.protect_role_change();

-- 7. Lock down the Figma Make key-value table --------------------------------
-- Figma Make created kv_store_c1f42330 for its server function. The anon key
-- is public (it ships in the browser bundle), so without RLS anyone could read
-- or write that table directly. Enabling RLS with no policies blocks the
-- browser entirely; the Edge Function uses the service role, which bypasses RLS.
do $$
begin
  if to_regclass('public.kv_store_c1f42330') is not null then
    execute 'alter table public.kv_store_c1f42330 enable row level security';
  end if;
end $$;

-- 8. Make the FIRST admin (run once, by hand, after you have an account) -----
-- update public.profiles set role = 'admin' where email = 'you@email.com';
