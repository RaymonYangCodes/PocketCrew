begin;
create or replace function public.family_money_command(s jsonb,actor uuid,action text,d jsonb,command_id uuid,stamp text)
returns jsonb language plpgsql set search_path='' as $$
#variable_conflict use_column
declare
  f uuid:=(s->'family'->>'id')::uuid; kid uuid; base jsonb; c jsonb; rule jsonb; matchrule jsonb;
  idx integer; g jsonb; tx jsonb; e jsonb; a jsonb; ids jsonb; lines jsonb:='[]';
  gross bigint; saving bigint; giving bigint; spending bigint; matching bigint; cap bigint;
  total bigint:=0; totalmatch bigint:=0; amount bigint; remaining bigint; reduction bigint;
  jar text; reason text; pid uuid:=gen_random_uuid(); part record; nextdate timestamptz;
begin
  base:=jsonb_build_object('id',gen_random_uuid(),'createdAt',stamp,'updatedAt',stamp,'createdBy',actor);
  if action in ('record','editChild','addGoal') then
    kid:=(d->>'childId')::uuid;
    select value into c from jsonb_array_elements(s->'children') where (value->>'id')::uuid=kid and value->>'status'='active';
    if c is null then raise exception 'Choose an active child'; end if;
  end if;
  if action='editChild' then
    if length(trim(coalesce(d->>'name','')))=0 or length(d->>'name')>40 then raise exception 'Enter a name under 40 characters'; end if;
    if coalesce(d->'split'->>'spend','')!~'^\d+$' or coalesce(d->'split'->>'save','')!~'^\d+$' or coalesce(d->'split'->>'give','')!~'^\d+$' then raise exception 'Percentages must be whole numbers'; end if;
    spending:=(d->'split'->>'spend')::bigint;saving:=(d->'split'->>'save')::bigint;giving:=(d->'split'->>'give')::bigint;
    if spending+saving+giving<>100 or greatest(spending,saving,giving)>100 then raise exception 'Spend + Save + Give must equal 100%%'; end if;
    select (ordinality-1)::integer into idx from jsonb_array_elements(s->'children') with ordinality where (value->>'id')::uuid=kid;
    s:=jsonb_set(s,array['children',idx::text],c||jsonb_build_object('name',trim(d->>'name'),'updatedAt',stamp));
    select value,(ordinality-1)::integer into rule,idx from jsonb_array_elements(s->'splits') with ordinality where (value->>'childId')::uuid=kid;
    if rule is null then raise exception 'Split rule not found'; end if;
    s:=jsonb_set(s,array['splits',idx::text],rule||jsonb_build_object('spendPercent',spending,'savePercent',saving,'givePercent',giving,'updatedAt',stamp));
  elsif action='addGoal' then
    if length(trim(coalesce(d->>'title','')))=0 or length(d->>'title')>80 or coalesce(d->>'target','')!~'^\d+$' then raise exception 'Enter a goal name and target in cents'; end if;
    amount:=(d->>'target')::bigint;if amount<1 or amount>10000000 then raise exception 'Choose a valid target';end if;
    for g,idx in select value,(ordinality-1)::integer from jsonb_array_elements(s->'goals') with ordinality where (value->>'childId')::uuid=kid loop
      s:=jsonb_set(s,array['goals',idx::text],g||jsonb_build_object('featured',false,'updatedAt',stamp));
    end loop;
    s:=jsonb_set(s,'{goals}',(s->'goals')||jsonb_build_array(base||jsonb_build_object('familyId',f,'childId',kid,'title',trim(d->>'title'),'icon','star.fill','targetCents',amount,'allocatedCents',0,'priority',0,'featured',true,'status','active')));
  elsif action='record' then
    jar:=d->>'jar'; reason:=trim(coalesce(d->>'reason',''));
    if jar is null or jar not in ('spend','save','give') or length(reason)=0 or length(reason)>150 or coalesce(d->>'amount','')!~'^\d+$' then raise exception 'Choose a jar, amount and reason';end if;
    amount:=(d->>'amount')::bigint;
    if amount<1 or amount>10000000 then raise exception 'Choose a valid amount';end if;
    if (select coalesce(sum((v->>'amountCents')::bigint),0) from jsonb_array_elements(s->'ledger') v where (v->>'childId')::uuid=kid and v->>'jar'=jar)<amount then raise exception 'There is not enough in this jar. Nothing was deducted.';end if;
    s:=jsonb_set(s,'{ledger}',(s->'ledger')||jsonb_build_array(base||jsonb_build_object('familyId',f,'childId',kid,'jar',jar,'amountCents',-amount,'category',jar,'description',reason)));
    if jar='save' then
      remaining:=amount;
      for g,idx in select value,(ordinality-1)::integer from jsonb_array_elements(s->'goals') with ordinality where (value->>'childId')::uuid=kid and value->>'status' in ('active','completed') loop
        reduction:=least(remaining,(g->>'allocatedCents')::bigint);remaining:=remaining-reduction;
        s:=jsonb_set(s,array['goals',idx::text],g||jsonb_build_object('allocatedCents',(g->>'allocatedCents')::bigint-reduction,'status',case when reduction>0 then 'active' else g->>'status' end,'updatedAt',stamp));
        exit when remaining=0;
      end loop;
    end if;
  elsif action='schedule' then
    if d->>'frequency'='custom' then
      if coalesce(d->>'customDays','') !~ '^[0-9]{1,3}$' then raise exception 'Enter a whole number from 1 to 365 days'; end if;
      if (d->>'customDays')::integer not between 1 and 365 then raise exception 'Enter a whole number from 1 to 365 days'; end if;
    end if;
    if coalesce(d->>'date','')!~'^\d{4}-\d{2}-\d{2}$' or coalesce(d->>'frequency','weekly') not in ('weekly','biweekly','twiceMonthly','monthly','custom') then raise exception 'Choose a payday date and frequency';end if;
    s:=jsonb_set(s,'{schedule}',s->'schedule'||jsonb_build_object('frequency',coalesce(d->>'frequency','weekly'),'customDays',case when d->>'frequency'='custom' then (d->>'customDays')::integer else null end,'nextPaydayAt',to_char(((d->>'date')::date+time '17:00') at time zone (s->'family'->>'timezone') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'updatedAt',stamp));
  elsif action='payday' then
    if coalesce(d->>'confirmed','false')<>'true' then raise exception 'Confirm payday first';end if;
    if exists(select 1 from jsonb_array_elements(s->'paydays') p where p->>'idempotencyKey'=command_id::text) then return s;end if;
    if (s->'schedule'->>'nextPaydayAt')::timestamptz>now() and coalesce(d->>'earlyConfirmed','false')<>'true' then raise exception 'Please confirm this early payday';end if;
    if exists(select 1 from jsonb_array_elements(s->'earnings') e where e->>'status'='approvedUnpaid' and (e->>'paydayId' is not null or not exists(select 1 from jsonb_array_elements(s->'children') c where (c->>'id')::uuid=(e->>'childId')::uuid and c->>'status'='active'))) then raise exception 'An earning needs parent attention before payday';end if;
    for c in select value from jsonb_array_elements(s->'children') where value->>'status'='active' loop
      kid:=(c->>'id')::uuid;
      select coalesce(sum((v->>'amountCents')::bigint),0),coalesce(jsonb_agg(v->'id'),'[]'::jsonb) into gross,ids from jsonb_array_elements(s->'earnings') v where (v->>'childId')::uuid=kid and v->>'status'='approvedUnpaid';
      if jsonb_array_length(ids)=0 then continue;end if;
      if gross<1 or gross>1000000000 then raise exception 'Invalid earnings total';end if;
      select value into rule from jsonb_array_elements(s->'splits') where (value->>'childId')::uuid=kid;
      if rule is null or (rule->>'spendPercent')::integer+(rule->>'savePercent')::integer+(rule->>'givePercent')::integer<>100 or least((rule->>'spendPercent')::integer,(rule->>'savePercent')::integer,(rule->>'givePercent')::integer)<0 then raise exception 'Split must total 100%%';end if;
      saving:=gross*(rule->>'savePercent')::bigint/100;giving:=gross*(rule->>'givePercent')::bigint/100;spending:=gross-saving-giving;
      select value into matchrule from jsonb_array_elements(s->'matchRules') where (value->>'childId')::uuid=kid and value->>'enabled'='true';
      matching:=0;
      if matchrule is not null then
        if (matchrule->>'percent')::bigint not between 0 and 1000 then raise exception 'Invalid match percentage';end if;
        matching:=saving*(matchrule->>'percent')::bigint/100;
        if matchrule->>'capCents' is not null then cap:=(matchrule->>'capCents')::bigint;if cap<0 then raise exception 'Invalid savings cap';end if;matching:=least(matching,cap);end if;
      end if;
      total:=total+gross;totalmatch:=totalmatch+matching;
      lines:=lines||jsonb_build_array(base||jsonb_build_object('id',gen_random_uuid(),'paydayId',pid,'childId',c->'id','earningIds',ids,'grossCents',gross,'spendCents',spending,'saveCents',saving,'giveCents',giving,'matchCents',matching));
      for part in select * from (values ('spend',spending,'Payday deposit · Spend'),('save',saving,'Payday deposit · Save'),('give',giving,'Payday deposit · Give'),('save',matching,'Parent savings match')) as amounts(jar,amount,description) loop
        if part.amount>0 then s:=jsonb_set(s,'{ledger}',(s->'ledger')||jsonb_build_array(base||jsonb_build_object('id',gen_random_uuid(),'familyId',f,'childId',c->'id','jar',part.jar,'amountCents',part.amount,'category','payday','description',part.description,'paydayId',pid)));end if;
      end loop;
      select value,(ordinality-1)::integer into g,idx from jsonb_array_elements(s->'goals') with ordinality where (value->>'childId')::uuid=kid and value->>'featured'='true' and value->>'status'='active' limit 1;
      if g is not null then
        amount:=least((g->>'targetCents')::bigint,(g->>'allocatedCents')::bigint+saving+matching);
        s:=jsonb_set(s,array['goals',idx::text],g||jsonb_build_object('allocatedCents',amount,'updatedAt',stamp,'status',case when amount=(g->>'targetCents')::bigint then 'completed' else 'active' end));
      end if;
    end loop;
    if total=0 then raise exception 'No approved earnings are ready';end if;
    for e,idx in select value,(ordinality-1)::integer from jsonb_array_elements(s->'earnings') with ordinality where value->>'status'='approvedUnpaid' loop
      s:=jsonb_set(s,array['earnings',idx::text],e||jsonb_build_object('status','paid','paydayId',pid,'updatedAt',stamp));
    end loop;
    for a,idx in select aa.value,(aa.ordinality-1)::integer from jsonb_array_elements(s->'assignments') with ordinality as aa(value,ordinality) where exists(select 1 from jsonb_array_elements(s->'earnings') e where (e->>'assignmentId')::uuid=(aa.value->>'id')::uuid and (e->>'paydayId')::uuid=pid) loop
      s:=jsonb_set(s,array['assignments',idx::text],a||jsonb_build_object('status','paid','updatedAt',stamp));
    end loop;
    s:=jsonb_set(s,'{paydayLines}',(s->'paydayLines')||lines);
    s:=jsonb_set(s,'{paydays}',(s->'paydays')||jsonb_build_array(base||jsonb_build_object('id',pid,'familyId',f,'scheduledFor',s->'schedule'->'nextPaydayAt','processedAt',stamp,'status','processed','idempotencyKey',command_id::text,'totalEarningsCents',total,'totalMatchCents',totalmatch,'early',(s->'schedule'->>'nextPaydayAt')::timestamptz>now())));
    nextdate:=(s->'schedule'->>'nextPaydayAt')::timestamptz;
    -- Preserve the family's local hour across daylight-saving changes.
    loop
      if s->'schedule'->>'frequency'='monthly' then nextdate:=((nextdate at time zone (s->'family'->>'timezone'))+interval '1 month') at time zone (s->'family'->>'timezone');
      elsif s->'schedule'->>'frequency'='twiceMonthly' then
        if extract(day from nextdate at time zone (s->'family'->>'timezone'))<15 then nextdate:=(date_trunc('month',nextdate at time zone (s->'family'->>'timezone'))+interval '14 days 17 hours') at time zone (s->'family'->>'timezone');
        else nextdate:=(date_trunc('month',nextdate at time zone (s->'family'->>'timezone'))+interval '1 month 17 hours') at time zone (s->'family'->>'timezone');end if;
      elsif s->'schedule'->>'frequency'='custom' then
        if coalesce(s->'schedule'->>'customDays','') !~ '^[0-9]{1,3}$' then raise exception 'Invalid custom payday interval'; end if;
        if (s->'schedule'->>'customDays')::integer not between 1 and 365 then raise exception 'Invalid custom payday interval'; end if;
        nextdate:=((nextdate at time zone (s->'family'->>'timezone'))+make_interval(days => (s->'schedule'->>'customDays')::integer)) at time zone (s->'family'->>'timezone');
      else nextdate:=((nextdate at time zone (s->'family'->>'timezone'))+case when s->'schedule'->>'frequency'='biweekly' then interval '14 days' else interval '7 days' end) at time zone (s->'family'->>'timezone');end if;
      exit when nextdate>now();
    end loop;
    s:=jsonb_set(s,'{schedule}',s->'schedule'||jsonb_build_object('nextPaydayAt',to_char(nextdate at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'updatedAt',stamp));
  else raise exception 'Unsupported money action';
  end if;
  return s;
end; $$;
revoke all on function public.family_money_command(jsonb,uuid,text,jsonb,uuid,text) from public,anon,authenticated;
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
    if p_action not in ('add','cart','remove','goal','featureGoal') then raise exception 'A parent needs to do this'; end if;
  else
    guardian:=public.is_family_guardian(p_family_id);
    if not guardian then raise exception 'Parent sign-in required'; end if;
    actor:=auth.uid();
    if p_action not in ('add','cart','remove','goal','price','approve','gift','decline','reviewGoal','featureGoal') then raise exception 'Unknown shopping action'; end if;
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
  if p_action='featureGoal' then
    select value into goal from jsonb_array_elements(s->'goals') where (value->>'id')::uuid=(p_data->>'id')::uuid;
    if goal is null or goal->>'status' is distinct from 'active' then raise exception 'Choose an approved active goal'; end if;
    kid:=(goal->>'childId')::uuid;
    if not guardian and kid<>actor then raise exception 'Choose your own goal'; end if;
    if not exists(select 1 from jsonb_array_elements(s->'children') c where (c->>'id')::uuid=kid and c->>'status'='active') then raise exception 'Child is not active'; end if;
    s:=jsonb_set(s,'{goals}',(select jsonb_agg(case when (g->>'childId')::uuid=kid then g||jsonb_build_object('featured',g->>'id'=goal->>'id','updatedAt',stamp) else g end order by n) from jsonb_array_elements(s->'goals') with ordinality as a(g,n)));
  elsif p_action='reviewGoal' then
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
commit;
