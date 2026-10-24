create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.families (
  id uuid primary key,
  name text not null check (char_length(name) between 1 and 80),
  timezone text not null,
  currency text not null check (char_length(currency) = 3),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.family_guardians (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'guardian')),
  status text not null default 'active' check (status in ('active', 'removed')),
  joined_at timestamptz not null default now(),
  primary key (family_id, user_id)
);

create table if not exists public.family_snapshots (
  family_id uuid primary key references public.families(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  state jsonb not null,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.family_invites (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  email text not null,
  token_hash text not null unique,
  invited_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create unique index if not exists one_active_family_per_guardian_idx
  on public.family_guardians(user_id) where status = 'active';
create index if not exists family_invites_family_idx
  on public.family_invites(family_id, created_at desc);
create index if not exists family_invites_email_idx
  on public.family_invites(lower(email)) where accepted_at is null;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name')
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = coalesce(excluded.display_name, public.profiles.display_name),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of email, raw_user_meta_data on auth.users
  for each row execute function public.handle_new_auth_user();

create or replace function public.is_family_guardian(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.family_guardians fg
    where fg.family_id = target_family_id
      and fg.user_id = auth.uid()
      and fg.status = 'active'
  );
$$;

create or replace function public.is_family_owner(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.family_guardians fg
    where fg.family_id = target_family_id
      and fg.user_id = auth.uid()
      and fg.role = 'owner'
      and fg.status = 'active'
  );
$$;

alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_guardians enable row level security;
alter table public.family_snapshots enable row level security;
alter table public.family_invites enable row level security;

drop policy if exists "profile owner read" on public.profiles;
create policy "profile owner read" on public.profiles for select to authenticated
  using (auth.uid() = id);
drop policy if exists "profile owner update" on public.profiles;
create policy "profile owner update" on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "guardian family read" on public.families;
create policy "guardian family read" on public.families for select to authenticated
  using (public.is_family_guardian(id));
drop policy if exists "owner family update" on public.families;
create policy "owner family update" on public.families for update to authenticated
  using (public.is_family_owner(id)) with check (public.is_family_owner(id));

drop policy if exists "guardian membership read" on public.family_guardians;
create policy "guardian membership read" on public.family_guardians for select to authenticated
  using (public.is_family_guardian(family_id));

drop policy if exists "guardian snapshot read" on public.family_snapshots;
create policy "guardian snapshot read" on public.family_snapshots for select to authenticated
  using (public.is_family_guardian(family_id));

drop policy if exists "guardian invite read" on public.family_invites;
create policy "guardian invite read" on public.family_invites for select to authenticated
  using (public.is_family_guardian(family_id));

revoke all on public.profiles, public.families, public.family_guardians,
  public.family_snapshots, public.family_invites from anon;
revoke all on public.profiles, public.families, public.family_guardians,
  public.family_snapshots, public.family_invites from public;
revoke insert, delete on public.profiles from authenticated;
revoke insert, delete on public.families from authenticated;
revoke insert, update, delete on public.family_guardians from authenticated;
revoke insert, update, delete on public.family_snapshots from authenticated;
revoke insert, update, delete on public.family_invites from authenticated;
grant select, update on public.profiles to authenticated;
grant select, update on public.families to authenticated;
grant select on public.family_guardians, public.family_snapshots, public.family_invites
  to authenticated;

create or replace function public.create_family_account(
  p_family_id uuid,
  p_name text,
  p_timezone text,
  p_currency text,
  p_state jsonb
)
returns table(revision bigint)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.family_guardians
    where user_id = auth.uid() and status = 'active'
  ) then
    raise exception 'This account already belongs to a family' using errcode = '23505';
  end if;
  if nullif(trim(p_name), '') is null or char_length(p_name) > 80 then
    raise exception 'Invalid family name' using errcode = '22023';
  end if;
  if (p_state -> 'family' ->> 'id')::uuid is distinct from p_family_id then
    raise exception 'Family state does not match family id' using errcode = '22023';
  end if;

  insert into public.families(id, name, timezone, currency, created_by)
  values (p_family_id, trim(p_name), p_timezone, upper(p_currency), auth.uid());
  insert into public.family_guardians(family_id, user_id, role)
  values (p_family_id, auth.uid(), 'owner');
  insert into public.family_snapshots(family_id, revision, state, updated_by)
  values (p_family_id, 1, p_state, auth.uid());
  return query select 1::bigint;
end;
$$;

create or replace function public.save_family_snapshot(
  p_family_id uuid,
  p_expected_revision bigint,
  p_state jsonb
)
returns table(revision bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_revision bigint;
begin
  if not public.is_family_guardian(p_family_id) then
    raise exception 'Family access denied' using errcode = '42501';
  end if;
  if (p_state -> 'family' ->> 'id')::uuid is distinct from p_family_id then
    raise exception 'Family state does not match family id' using errcode = '22023';
  end if;

  update public.family_snapshots
  set state = p_state,
      revision = family_snapshots.revision + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where family_id = p_family_id and family_snapshots.revision = p_expected_revision
  returning family_snapshots.revision into next_revision;

  if next_revision is null then
    raise exception 'The family changed on another device. Reload before saving.'
      using errcode = '40001';
  end if;
  return query select next_revision;
end;
$$;

create or replace function public.accept_family_invite(p_token text)
returns table(revision bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite_row public.family_invites%rowtype;
  signed_in_email text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  signed_in_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  select * into invite_row
  from public.family_invites
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and accepted_at is null
    and expires_at > now()
  for update;
  if invite_row.id is null then
    raise exception 'Invitation is invalid or expired' using errcode = '22023';
  end if;
  if lower(invite_row.email) <> signed_in_email then
    raise exception 'Sign in with the invited email address' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.family_guardians
    where user_id = auth.uid() and status = 'active' and family_id <> invite_row.family_id
  ) then
    raise exception 'This account already belongs to another family' using errcode = '23505';
  end if;

  insert into public.family_guardians(family_id, user_id, role, status)
  values (invite_row.family_id, auth.uid(), 'guardian', 'active')
  on conflict (family_id, user_id) do update set status = 'active';
  update public.family_invites
  set accepted_at = now(), accepted_by = auth.uid()
  where id = invite_row.id;
  return query
    select fs.revision from public.family_snapshots fs where fs.family_id = invite_row.family_id;
end;
$$;

revoke all on function public.create_family_account(uuid, text, text, text, jsonb) from public;
revoke all on function public.save_family_snapshot(uuid, bigint, jsonb) from public;
revoke all on function public.accept_family_invite(text) from public;
revoke all on function public.is_family_guardian(uuid), public.is_family_owner(uuid) from public;
revoke all on function public.handle_new_auth_user() from public;
grant execute on function public.create_family_account(uuid, text, text, text, jsonb)
  to authenticated;
grant execute on function public.save_family_snapshot(uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.accept_family_invite(text) to authenticated;
grant execute on function public.is_family_guardian(uuid), public.is_family_owner(uuid)
  to authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'proof-images', 'proof-images', false, 8000000,
  array['image/jpeg', 'image/png', 'image/heic']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "family proof read" on storage.objects;
create policy "family proof read" on storage.objects for select to authenticated
using (
  bucket_id = 'proof-images'
  and public.is_family_guardian(((storage.foldername(name))[1])::uuid)
);
drop policy if exists "family proof insert" on storage.objects;
create policy "family proof insert" on storage.objects for insert to authenticated
with check (
  bucket_id = 'proof-images'
  and public.is_family_guardian(((storage.foldername(name))[1])::uuid)
);
drop policy if exists "family proof update" on storage.objects;
create policy "family proof update" on storage.objects for update to authenticated
using (
  bucket_id = 'proof-images'
  and public.is_family_guardian(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'proof-images'
  and public.is_family_guardian(((storage.foldername(name))[1])::uuid)
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'family_snapshots'
  ) then
    alter publication supabase_realtime add table public.family_snapshots;
  end if;
end;
$$;
