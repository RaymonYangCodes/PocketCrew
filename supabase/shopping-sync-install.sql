begin;
-- Shopping commands share the native snapshot, lock, revision and idempotency receipts.
-- Child capability authentication returns only the existing child-scoped projection.

create or replace function public.family_shopping_command(
  p_family_id uuid,p_revision bigint,p_command_id uuid,p_action text,p_data jsonb,
  p_child_token text default null,p_child_pin text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare
  snap public.family_snapshots%rowtype; previous public.family_commands%rowtype;
  s jsonb; identity jsonb; guardian boolean:=false; actor uuid; kid uuid;
  entry jsonb; product jsonb; goal jsonb; base jsonb; idx integer; amount bigint;
  oldprice bigint; note text; title text; status text; txid uuid; stamp text;
begin
  if p_family_id is null or p_revision is null or p_command_id is null or p_action is null
    or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>30000 then
    raise exception 'Invalid shopping request';
  end if;
  if p_child_token is not null then
    identity:=public.read_child_connection(p_child_token,p_child_pin);
    if identity ? 'error' then return identity; end if;
    if (identity->>'family_id')::uuid<>p_family_id then raise exception 'Family access denied'; end if;
    actor:=(identity->>'child_id')::uuid;
    if p_action not in ('add','cart','remove','goal') then raise exception 'A parent needs to do this'; end if;
  else
    guardian:=public.is_family_guardian(p_family_id);
    if not guardian then raise exception 'Parent sign-in required'; end if;
    actor:=auth.uid();
    if p_action not in ('add','cart','remove','goal','price','approve','gift','decline','reviewGoal') then raise exception 'Unknown shopping action'; end if;
  end if;
  select * into snap from public.family_snapshots where family_id=p_family_id for update;
  if not found then raise exception 'Family not found'; end if;
  select * into previous from public.family_commands where family_id=p_family_id and command_id=p_command_id;
  if found then
    if previous.actor_id<>actor or previous.action<>'shopping.'||p_action then raise exception 'Command already used'; end if;
    if guardian then return jsonb_build_object('family_id',p_family_id,'revision',snap.revision,'state',snap.state); end if;
    return public.read_child_connection(p_child_token,p_child_pin);
  end if;
  if snap.revision<>p_revision then raise exception 'Your family changed on another device. Close this form, refresh, and try again.'; end if;
  s:=snap.state;
  if jsonb_typeof(s->'shoppingEntries') is distinct from 'array' then s:=jsonb_set(s,'{shoppingEntries}','[]'); end if;
  stamp:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  base:=jsonb_build_object('id',gen_random_uuid(),'createdAt',stamp,'updatedAt',stamp,'createdBy',actor,'familyId',p_family_id);
  if p_action='reviewGoal' then
    select value,(ordinality-1)::integer into goal,idx from jsonb_array_elements(s->'goals') with ordinality where (value->>'id')::uuid=(p_data->>'id')::uuid;
    if goal is null or goal->>'status'<>'proposed' then raise exception 'Goal has already been reviewed'; end if;
    if coalesce(p_data->>'decision','') not in ('active','archived') then raise exception 'Choose approve or decline'; end if;
    goal:=goal||jsonb_build_object('status',p_data->>'decision','updatedAt',stamp,'featured',
      p_data->>'decision'='active' and not exists(select 1 from jsonb_array_elements(s->'goals') g where (g->>'childId')::uuid=(goal->>'childId')::uuid and g->>'status'='active' and g->>'featured'='true'));
    s:=jsonb_set(s,array['goals',idx::text],goal);
  else
    if p_action in ('add','goal') and nullif(p_data->>'id','') is null then
      kid:=(p_data->>'childId')::uuid;
      product:=p_data->'product';
    else
      select value,(ordinality-1)::integer into entry,idx from jsonb_array_elements(s->'shoppingEntries') with ordinality where (value->>'id')::uuid=(p_data->>'id')::uuid;
      if entry is null or entry->>'status' not in ('wishlist','awaitingApproval') then raise exception 'Only wishlist and pending cart items can be changed'; end if;
      kid:=(entry->>'childId')::uuid; product:=entry->'product';
    end if;
    if kid is null or not exists(select 1 from jsonb_array_elements(s->'children') c where (c->>'id')::uuid=kid and c->>'status'='active') then raise exception 'Choose an active child'; end if;
    if not guardian and kid<>actor then raise exception 'You can only change your own list'; end if;
    if p_action in ('add','goal') then
      if product is null or jsonb_typeof(product)<>'object'
        or length(trim(coalesce(product->>'title','')))=0 or length(product->>'title')>240
        or coalesce(product->>'priceCents','')!~'^\d+$' or coalesce(product->>'source','') not in ('googleShopping','pocketCrew','amazon')
        or length(coalesce(product->>'id','')) not between 1 and 200 then raise exception 'Choose a valid shopping item'; end if;
      amount:=(product->>'priceCents')::bigint;
      if amount<1 or amount>100000000 or coalesce(product->>'currencyCode',s->'family'->>'currency')<>s->'family'->>'currency' then raise exception 'Choose an item in your family currency'; end if;
      -- Store only native product fields, never caller-provided lifecycle/ledger fields.
      product:=jsonb_strip_nulls(jsonb_build_object('id',product->>'id','source',product->>'source','title',product->>'title',
        'detail',left(coalesce(product->>'detail',''),1000),'category','Shopping','symbol','shippingbox.fill','priceCents',amount,
        'currencyCode',s->'family'->>'currency','merchant',left(coalesce(product->>'merchant','Seller not provided'),100),
        'imageURL',case when product->>'imageURL' ~ '^https://([a-zA-Z0-9-]+\.)*(gstatic\.com|googleusercontent\.com|serpapi\.com)/' then product->>'imageURL' end,
        'productURL',case when product->>'productURL' ~ '^https://(www\.)?google\.com/(search\?|shopping/product/)' then product->>'productURL' end));
    end if;
    if p_action='add' then
      status:=p_data->>'destination';
      if status is null or status not in ('wishlist','awaitingApproval') then raise exception 'Choose Wishlist or Cart'; end if;
      if exists(select 1 from jsonb_array_elements(s->'shoppingEntries') e where (e->>'childId')::uuid=kid and e->'product'->>'id'=product->>'id' and e->>'status' in ('wishlist','awaitingApproval')) then raise exception 'This item is already on this child’s list'; end if;
      entry:=base||jsonb_build_object('childId',kid,'product',product,'status',status);
      s:=jsonb_set(s,'{shoppingEntries}',s->'shoppingEntries'||jsonb_build_array(entry));
    elsif p_action='goal' then
      title:=trim(coalesce(p_data->>'title',product->>'title'));
      if length(title) not between 1 and 240 or coalesce(p_data->>'target','')!~'^\d+$' then raise exception 'Enter a goal title and target'; end if;
      amount:=(p_data->>'target')::bigint;if amount<1 or amount>100000000 then raise exception 'Choose a positive target'; end if;
      if nullif(p_data->>'targetDate','') is not null and p_data->>'targetDate' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Choose a valid target date'; end if;
      if exists(select 1 from jsonb_array_elements(s->'goals') g where (g->>'childId')::uuid=kid and g->'shoppingProduct'->>'id'=product->>'id' and g->>'status' in ('active','proposed')) then raise exception 'This item already has a savings goal'; end if;
      goal:=base||jsonb_strip_nulls(jsonb_build_object('childId',kid,'title',title,'icon','🎯','targetCents',amount,'allocatedCents',0,
        'targetDate',case when nullif(p_data->>'targetDate','') is not null then to_char((p_data->>'targetDate')::date,'YYYY-MM-DD')||'T12:00:00Z' end,
        'priority',jsonb_array_length(s->'goals')+1,'featured',guardian and not exists(select 1 from jsonb_array_elements(s->'goals') g where (g->>'childId')::uuid=kid and g->>'status'='active' and g->>'featured'='true'),
        'status',case when guardian then 'active' else 'proposed' end,'shoppingProduct',product));
      s:=jsonb_set(s,'{goals}',s->'goals'||jsonb_build_array(goal));
    else
      note:=trim(coalesce(p_data->>'reason',''));
      if p_action='price' then
        if coalesce(p_data->>'priceCents','')!~'^\d+$' or length(note) not between 1 and 1000 then raise exception 'Enter a positive price and a reason'; end if;
        amount:=(p_data->>'priceCents')::bigint;
        if amount<1 or amount>100000000 then raise exception 'Choose a valid price'; end if;
        oldprice:=(product->>'priceCents')::bigint;
        entry:=entry||jsonb_build_object('product',product||jsonb_build_object('priceCents',amount),'parentNote','Price set by parent: '||note);
      elsif p_action='cart' then
        if entry->>'status'<>'wishlist' then raise exception 'This item is already in the cart'; end if;
        entry:=entry||jsonb_build_object('status','awaitingApproval');
      elsif p_action='approve' then
        if entry->>'status'<>'awaitingApproval' then raise exception 'Request a purchase first'; end if;
        if coalesce(p_data->>'expectedPrice','') !~ '^\d+$' or (p_data->>'expectedPrice')::bigint<>(product->>'priceCents')::bigint then raise exception 'The price changed. Refresh and review the new price before approving.'; end if;
        if coalesce(product->>'currencyCode',s->'family'->>'currency')<>s->'family'->>'currency' then raise exception 'Currency does not match'; end if;
        amount:=(product->>'priceCents')::bigint;
        if amount<1 or amount>100000000 then raise exception 'Invalid item price'; end if;
        -- Reuse overdraft/ledger safeguards; stores no real checkout or payment.
        s:=public.family_money_command(s,actor,'record',jsonb_build_object('childId',kid,'jar','spend','amount',amount,'reason','Shopping purchase · '||left(product->>'title',125)),p_command_id,stamp);
        txid:=(s->'ledger'->-1->>'id')::uuid;
        entry:=entry||jsonb_build_object('status','purchased','resolvedAt',stamp,'ledgerTransactionId',txid);
      elsif p_action='gift' then
        entry:=entry||jsonb_build_object('status','gifted','resolvedAt',stamp,'parentNote','Given by a parent — no Spend deducted.');
      elsif p_action='decline' then
        if length(note) not between 1 and 1000 then raise exception 'Add a kind reason'; end if;
        entry:=entry||jsonb_build_object('status','declined','resolvedAt',stamp,'parentNote',note);
      elsif p_action='remove' then
        entry:=entry||jsonb_build_object('status','removed','resolvedAt',stamp);
      end if;
      entry:=entry||jsonb_build_object('updatedAt',stamp);
      s:=jsonb_set(s,array['shoppingEntries',idx::text],entry);
    end if;
  end if;
  s:=jsonb_set(s,'{audit}',coalesce(s->'audit','[]')||jsonb_build_array(base||jsonb_build_object('id',gen_random_uuid(),'actorId',actor,'action','shopping.'||p_action,'entityType','FamilyCommand','entityId',p_command_id,'detail',case when oldprice is not null then oldprice||' → '||amount||' cents. '||note else note end)));
  insert into public.family_commands(family_id,command_id,actor_id,action) values(p_family_id,p_command_id,actor,'shopping.'||p_action);
  update public.family_snapshots set state=s,revision=revision+1,updated_at=now(),updated_by=case when guardian then actor else updated_by end where family_id=p_family_id returning * into snap;
  if guardian then return jsonb_build_object('family_id',p_family_id,'revision',snap.revision,'state',snap.state); end if;
  return public.read_child_connection(p_child_token,p_child_pin);
end; $$;
revoke all on function public.family_shopping_command(uuid,bigint,uuid,text,jsonb,text,text) from public;
grant execute on function public.family_shopping_command(uuid,bigint,uuid,text,jsonb,text,text) to anon,authenticated;

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


notify pgrst, 'reload schema';
commit;

