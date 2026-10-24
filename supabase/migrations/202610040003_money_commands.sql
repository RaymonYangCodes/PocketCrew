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
    if coalesce(d->>'date','')!~'^\d{4}-\d{2}-\d{2}$' or coalesce(d->>'frequency','weekly') not in ('weekly','biweekly','twiceMonthly','monthly') then raise exception 'Choose a payday date and frequency';end if;
    s:=jsonb_set(s,'{schedule}',s->'schedule'||jsonb_build_object('frequency',coalesce(d->>'frequency','weekly'),'nextPaydayAt',to_char(((d->>'date')::date+time '17:00') at time zone (s->'family'->>'timezone') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'updatedAt',stamp));
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
      else nextdate:=((nextdate at time zone (s->'family'->>'timezone'))+case when s->'schedule'->>'frequency'='biweekly' then interval '14 days' else interval '7 days' end) at time zone (s->'family'->>'timezone');end if;
      exit when nextdate>now();
    end loop;
    s:=jsonb_set(s,'{schedule}',s->'schedule'||jsonb_build_object('nextPaydayAt',to_char(nextdate at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'updatedAt',stamp));
  else raise exception 'Unsupported money action';
  end if;
  return s;
end; $$;
revoke all on function public.family_money_command(jsonb,uuid,text,jsonb,uuid,text) from public,anon,authenticated;
commit;
