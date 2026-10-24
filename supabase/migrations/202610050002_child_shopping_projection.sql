begin;
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
  foreach own_field in array array['splits','earnings','ledger','goals','paydayLines','matchRules','submissions','shoppingEntries'] loop
    select coalesce(jsonb_agg(v),'[]'::jsonb) into own_array from jsonb_array_elements(case when jsonb_typeof(s->own_field)='array' then s->own_field else '[]'::jsonb end) v
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

commit;

