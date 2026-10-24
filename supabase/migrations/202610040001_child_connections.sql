-- Applied 2026-10-04. Child capabilities never expose the guardian snapshot API.
begin;
create table if not exists public.child_connections (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid not null,
  created_by uuid not null references auth.users(id),
  token_hash text not null unique,
  pin_hash text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  revoked_at timestamptz,
  failed_attempts integer not null default 0,
  locked_until timestamptz
);
alter table public.child_connections enable row level security;
revoke all on public.child_connections from public, anon, authenticated;

create or replace function public.create_child_connection(p_family_id uuid,p_child_id uuid,p_pin text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare token text; connection_id uuid;
begin
  if not public.is_family_guardian(p_family_id) then
    raise exception 'Parent sign-in required' using errcode='42501';
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{6,8}$' then
    raise exception 'Choose a child passcode with 6 to 8 digits' using errcode='22023';
  end if;
  if not exists(select 1 from public.family_snapshots s,
    lateral jsonb_array_elements(s.state->'children') c
    where s.family_id=p_family_id and (c->>'id')::uuid=p_child_id and c->>'status'='active') then
    raise exception 'Child not found' using errcode='22023';
  end if;
  -- Serialize creation for a family so concurrent calls cannot bypass the hourly cap.
  perform 1 from public.families where id=p_family_id for update;
  if (select count(*) from public.child_connections where created_by=auth.uid()
      and created_at>now()-interval '1 hour')>=10 then
    raise exception 'Please wait before making more invitations' using errcode='54000';
  end if;
  token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.child_connections(family_id,child_id,created_by,token_hash,pin_hash)
    values(p_family_id,p_child_id,auth.uid(),encode(extensions.digest(token,'sha256'),'hex'),
      extensions.crypt(p_pin,extensions.gen_salt('bf',10))) returning id into connection_id;
  return jsonb_build_object('id',connection_id,'token',token,'expiresAt',now()+interval '30 days');
end; $$;

create or replace function public.revoke_child_connections(p_family_id uuid,p_child_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.is_family_guardian(p_family_id) then
    raise exception 'Parent sign-in required' using errcode='42501';
  end if;
  update public.child_connections set revoked_at=now()
    where family_id=p_family_id and child_id=p_child_id and revoked_at is null;
end; $$;

-- Authenticated by an unguessable parent-issued capability AND a separate PIN.
-- Return errors as data so failed-attempt counters commit rather than roll back.
create or replace function public.read_child_connection(p_token text,p_pin text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare link public.child_connections%rowtype; snapshot public.family_snapshots%rowtype;
  s jsonb; scoped jsonb; assignments jsonb; items jsonb; children jsonb;
  own_field text; own_array jsonb;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' or p_pin is null or char_length(p_pin)>8 then
    return jsonb_build_object('error','Invitation or passcode not accepted');
  end if;
  select * into link from public.child_connections
    where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
  if link.id is null or link.revoked_at is not null or link.expires_at<=now() then
    return jsonb_build_object('error','Invitation or passcode not accepted');
  end if;
  if link.locked_until>now() then
    return jsonb_build_object('error','Please wait a minute before trying again');
  end if;
  if extensions.crypt(p_pin,link.pin_hash)<>link.pin_hash then
    update public.child_connections set
      failed_attempts=case when failed_attempts>=4 then 0 else failed_attempts+1 end,
      locked_until=case when failed_attempts>=4 then now()+interval '1 minute' else null end
      where id=link.id;
    return jsonb_build_object('error','Invitation or passcode not accepted');
  end if;
  update public.child_connections set failed_attempts=0,locked_until=null where id=link.id;
  select * into snapshot from public.family_snapshots where family_id=link.family_id;
  s:=snapshot.state;
  select coalesce(jsonb_agg(c),'[]'::jsonb) into children from jsonb_array_elements(s->'children') c
    where (c->>'id')::uuid=link.child_id and c->>'status'='active';
  if jsonb_array_length(children)<>1 then return jsonb_build_object('error','This profile is unavailable'); end if;
  select coalesce(jsonb_agg(a),'[]'::jsonb) into assignments from jsonb_array_elements(s->'assignments') a
    where (a->>'childId')::uuid=link.child_id or
      (a->>'childId' is null and a->>'status'='available' and exists(
        select 1 from jsonb_array_elements(s->'workItems') w where w->>'id'=a->>'workItemId'
          and w->>'type'='gig' and w->>'claimable'='true' and w->>'lifecycleStatus'='active'));
  select coalesce(jsonb_agg(w),'[]'::jsonb) into items from jsonb_array_elements(s->'workItems') w
    where exists(select 1 from jsonb_array_elements(assignments) a where a->>'workItemId'=w->>'id');
  scoped:=jsonb_build_object('family',jsonb_build_object('id',s->'family'->'id','name',s->'family'->'name',
      'currency',s->'family'->'currency','locale',s->'family'->'locale','timezone',s->'family'->'timezone'),
    'children',children,'assignments',assignments,'workItems',items,'schedule',s->'schedule',
    'users','[]'::jsonb,'members','[]'::jsonb,'notifications','[]'::jsonb,'audit','[]'::jsonb);
  foreach own_field in array array['splits','earnings','ledger','goals','paydayLines','matchRules','submissions'] loop
    select coalesce(jsonb_agg(v),'[]'::jsonb) into own_array from jsonb_array_elements(s->own_field) v
      where (v->>'childId')::uuid=link.child_id;
    scoped:=jsonb_set(scoped,array[own_field],own_array);
  end loop;
  select coalesce(jsonb_agg(d),'[]'::jsonb) into own_array from jsonb_array_elements(s->'decisions') d
    where exists(select 1 from jsonb_array_elements(scoped->'submissions') sub where sub->>'id'=d->>'submissionId');
  scoped:=jsonb_set(scoped,'{decisions}',own_array);
  -- Family payday totals reveal sibling earnings, so replace them with this child's totals.
  select coalesce(jsonb_agg(p || jsonb_build_object(
    'totalEarningsCents',(select coalesce(sum((l->>'grossCents')::bigint),0) from jsonb_array_elements(scoped->'paydayLines') l where l->>'paydayId'=p->>'id'),
    'totalMatchCents',(select coalesce(sum((l->>'matchCents')::bigint),0) from jsonb_array_elements(scoped->'paydayLines') l where l->>'paydayId'=p->>'id'))),'[]'::jsonb)
    into own_array from jsonb_array_elements(s->'paydays') p where exists(
      select 1 from jsonb_array_elements(scoped->'paydayLines') l where l->>'paydayId'=p->>'id');
  scoped:=jsonb_set(scoped,'{paydays}',own_array);
  return jsonb_build_object('family_id',snapshot.family_id,'revision',snapshot.revision,'state',scoped,'child_id',link.child_id);
end; $$;

revoke all on function public.create_child_connection(uuid,uuid,text) from public,anon;
revoke all on function public.revoke_child_connections(uuid,uuid) from public,anon;
revoke all on function public.read_child_connection(text,text) from public;
grant execute on function public.create_child_connection(uuid,uuid,text) to authenticated;
grant execute on function public.revoke_child_connections(uuid,uuid) to authenticated;
grant execute on function public.read_child_connection(text,text) to anon,authenticated;
commit;
