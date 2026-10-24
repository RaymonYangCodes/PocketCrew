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
-- Atomic, revision-checked commands. Never accept a replacement snapshot from a child.
begin;
create table if not exists public.family_commands (
  family_id uuid not null references public.families(id) on delete cascade,
  command_id uuid not null,
  actor_id uuid not null,
  action text not null,
  created_at timestamptz not null default now(),
  primary key(family_id,command_id)
);
alter table public.family_commands enable row level security;
revoke all on public.family_commands from public,anon,authenticated;

create or replace function public.family_work_command(
  p_family_id uuid,p_revision bigint,p_command_id uuid,p_action text,p_data jsonb,
  p_child_token text default null,p_child_pin text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  snap public.family_snapshots%rowtype; s jsonb; identity jsonb; a jsonb; w jsonb; sub jsonb;
  actor uuid; kid uuid; guardian boolean; idx integer; subidx integer; base jsonb;
  nowtext text:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  itemid uuid; assignid uuid; submissionid uuid; reward bigint; decision text; reason text;
  previous public.family_commands%rowtype; result jsonb;
begin
  if p_family_id is null or p_action is null or p_command_id is null or p_revision is null or p_data is null or jsonb_typeof(p_data)<>'object' then
    raise exception 'Invalid command' using errcode='22023';
  end if;
  guardian:=false;
  if p_child_token is not null then
    identity:=public.read_child_connection(p_child_token,p_child_pin);
    if identity ? 'error' then return identity; end if;
    if (identity->>'family_id')::uuid<>p_family_id then return jsonb_build_object('error','Family access denied'); end if;
    actor:=(identity->>'child_id')::uuid;
    if p_action not in ('start','submit') then return jsonb_build_object('error','A parent needs to do this'); end if;
  else
    guardian:=public.is_family_guardian(p_family_id);
    if not guardian then raise exception 'Parent sign-in required' using errcode='42501'; end if;
    actor:=auth.uid();
    if p_action not in ('createWork','review','dismissPresets','editChild','addGoal','record','payday','schedule') then
      raise exception 'Unsupported parent action' using errcode='22023';
    end if;
  end if;
  select * into snap from public.family_snapshots where family_id=p_family_id for update;
  if not found then raise exception 'Family not found'; end if;
  select * into previous from public.family_commands where family_id=p_family_id and command_id=p_command_id;
  if found then
    if previous.actor_id<>actor or previous.action<>p_action then raise exception 'Command already used'; end if;
    if guardian then return jsonb_build_object('family_id',p_family_id,'revision',snap.revision,'state',snap.state); end if;
    return public.read_child_connection(p_child_token,p_child_pin);
  end if;
  if snap.revision<>p_revision then raise exception 'Your family changed on another device. Refresh and try again.' using errcode='40001'; end if;
  s:=snap.state;
  base:=jsonb_build_object('id',gen_random_uuid(),'createdAt',nowtext,'updatedAt',nowtext,'createdBy',actor);
  if p_action='createWork' then
    if coalesce(p_data->>'type','') not in ('gig','responsibility') or length(trim(coalesce(p_data->>'title','')))=0 or length(p_data->>'title')>100 or length(coalesce(p_data->>'instructions',''))>1000 then raise exception 'Add a valid name, instructions and work type'; end if;
    kid:=nullif(p_data->>'childId','')::uuid;
    if kid is not null and not exists(select 1 from jsonb_array_elements(s->'children') c where (c->>'id')::uuid=kid and c->>'status'='active') then raise exception 'Choose an active child'; end if;
    if coalesce(p_data->>'reward','') !~ '^[0-9]+$' then raise exception 'Reward must be integer cents'; end if;
    reward:=(p_data->>'reward')::bigint;
    if reward>10000000 or (p_data->>'type'='gig' and reward<1) then raise exception 'Choose a valid reward'; end if;
    if p_data->>'type'='responsibility' then reward:=0; end if;
    if coalesce(p_data->>'due','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Choose a due date'; end if;
    itemid:=gen_random_uuid(); assignid:=gen_random_uuid();
    w:=base||jsonb_build_object('id',itemid,'familyId',p_family_id,'type',p_data->>'type','title',trim(p_data->>'title'),'instructions',coalesce(p_data->>'instructions',''),'category','Household','rewardCents',reward,'recurrence','once','proofRequired',false,'claimable',kid is null,'checklist','[]'::jsonb,'lifecycleStatus','active');
    a:=base||jsonb_build_object('id',assignid,'familyId',p_family_id,'workItemId',itemid,'dueAt',to_char(((p_data->>'due')::date+time '17:00') at time zone (s->'family'->>'timezone') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'rewardSnapshotCents',reward,'status',case when kid is null then 'available' else 'assigned' end,'checklistDone','[]'::jsonb);
    if kid is not null then a:=a||jsonb_build_object('childId',kid); end if;
    s:=jsonb_set(s,'{workItems}',(s->'workItems')||jsonb_build_array(w));
    s:=jsonb_set(s,'{assignments}',(s->'assignments')||jsonb_build_array(a));
  elsif p_action in ('start','submit','review') then
    select value,(ordinality-1)::integer into a,idx from jsonb_array_elements(s->'assignments') with ordinality where (value->>'id')::uuid=(p_data->>'id')::uuid;
    if a is null then raise exception 'Work not found'; end if;
    select value into w from jsonb_array_elements(s->'workItems') where (value->>'id')::uuid=(a->>'workItemId')::uuid;
    if w is null or w->>'lifecycleStatus'<>'active' then raise exception 'This work is paused or unavailable'; end if;
    if not guardian then
      if nullif(a->>'childId','') is not null and (a->>'childId')::uuid<>actor then raise exception 'This work belongs to another child' using errcode='42501'; end if;
      if a->>'childId' is null and not (a->>'status'='available' and w->>'type'='gig' and w->>'claimable'='true') then raise exception 'This work cannot be claimed'; end if;
    end if;
    if p_action='start' then
      if a->>'status' not in ('available','assigned','redoRequested') then raise exception 'This work has already started or been reviewed'; end if;
      a:=a||jsonb_build_object('childId',actor,'status','inProgress','updatedAt',nowtext);
    elsif p_action='submit' then
      if a->>'status' not in ('inProgress','redoRequested') or (a->>'childId')::uuid<>actor then raise exception 'Start your work before submitting'; end if;
      if w->>'proofRequired'='true' then raise exception 'This work needs a private proof photo. Submit it from the Mac app for now.'; end if;
      if length(coalesce(p_data->>'note',''))>1000 then raise exception 'Keep your note under 1,000 characters'; end if;
      if coalesce(p_data->>'checklistConfirmed','false')<>'true' and jsonb_array_length(w->'checklist')>0 then raise exception 'Check every step before submitting'; end if;
      submissionid:=gen_random_uuid();
      sub:=base||jsonb_build_object('id',submissionid,'assignmentId',a->'id','childId',actor,'submittedAt',nowtext,'note',trim(coalesce(p_data->>'note','')),'status','pending');
      s:=jsonb_set(s,'{submissions}',(s->'submissions')||jsonb_build_array(sub));
      a:=a||jsonb_build_object('status','awaitingApproval','updatedAt',nowtext,'checklistDone',w->'checklist');
    else
      if a->>'status'<>'awaitingApproval' then raise exception 'This work has already been reviewed'; end if;
      select value,(ordinality-1)::integer into sub,subidx from jsonb_array_elements(s->'submissions') with ordinality where (value->>'assignmentId')::uuid=(a->>'id')::uuid and value->>'status'='pending' order by ordinality desc limit 1;
      if sub is null then raise exception 'Pending submission not found'; end if;
      decision:=p_data->>'decision'; reason:=trim(coalesce(p_data->>'reason',''));
      if decision not in ('approved','redoRequested','rejected') or decision is null then raise exception 'Choose a review decision'; end if;
      if length(reason)>1000 or (decision<>'approved' and length(reason)=0) then raise exception 'Add a kind, specific reason under 1,000 characters'; end if;
      if decision='approved' and w->>'type'='gig' then
        if exists(select 1 from jsonb_array_elements(s->'earnings') e where (e->>'submissionId')::uuid=(sub->>'id')::uuid or ((e->>'assignmentId')::uuid=(a->>'id')::uuid and e->>'status'<>'reversed')) then raise exception 'Earnings already exist for this work'; end if;
        reward:=(a->>'rewardSnapshotCents')::bigint;
        if reward<1 or reward>10000000 then raise exception 'Invalid agreed reward'; end if;
        s:=jsonb_set(s,'{earnings}',(s->'earnings')||jsonb_build_array(base||jsonb_build_object('id',gen_random_uuid(),'familyId',p_family_id,'childId',sub->'childId','assignmentId',a->'id','submissionId',sub->'id','amountCents',reward,'status','approvedUnpaid')));
      end if;
      s:=jsonb_set(s,array['submissions',subidx::text],sub||jsonb_build_object('status',decision,'updatedAt',nowtext));
      s:=jsonb_set(s,'{decisions}',(s->'decisions')||jsonb_build_array(base||jsonb_build_object('id',gen_random_uuid(),'submissionId',sub->'id','guardianId',actor,'decision',decision,'reason',reason)));
      a:=a||jsonb_build_object('status',decision,'updatedAt',nowtext);
    end if;
    s:=jsonb_set(s,array['assignments',idx::text],a);
  elsif p_action='dismissPresets' then
    s:=jsonb_set(s,'{family,workPresetsDismissed}','true');
  else
    -- Separate helper is not exposed to browser roles.
    s:=public.family_money_command(s,actor,p_action,p_data,p_command_id,nowtext);
  end if;
  s:=jsonb_set(s,'{audit}',coalesce(s->'audit','[]'::jsonb)||jsonb_build_array(base||jsonb_build_object('id',gen_random_uuid(),'familyId',p_family_id,'actorId',actor,'action','cloud.'||p_action,'entityType','FamilyCommand','entityId',p_command_id)));
  insert into public.family_commands(family_id,command_id,actor_id,action) values(p_family_id,p_command_id,actor,p_action);
  update public.family_snapshots set state=s,revision=revision+1,updated_at=now(),updated_by=case when guardian then actor else updated_by end where family_id=p_family_id returning * into snap;
  if guardian then return jsonb_build_object('family_id',p_family_id,'revision',snap.revision,'state',snap.state); end if;
  return public.read_child_connection(p_child_token,p_child_pin);
end; $$;
revoke all on function public.family_work_command(uuid,bigint,uuid,text,jsonb,text,text) from public;
grant execute on function public.family_work_command(uuid,bigint,uuid,text,jsonb,text,text) to anon,authenticated;
commit;
