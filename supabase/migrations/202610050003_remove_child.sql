-- Parent-only child removal; keeps historical records and blocks unsettled accounts.
begin;
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
    if guardian is not true then raise exception 'Parent sign-in required' using errcode='42501'; end if;
    actor:=auth.uid();
    if p_action not in ('createWork','review','dismissPresets','editChild','removeChild','addGoal','record','payday','schedule') then
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
  elsif p_action='removeChild' then
    kid:=(p_data->>'childId')::uuid;
    select value into w from jsonb_array_elements(s->'children') where (value->>'id')::uuid=kid;
    if w is null then raise exception 'This child has already been removed';end if;
    if jsonb_array_length(s->'children')<=1 then raise exception 'Keep at least one child in the family';end if;
    if exists(select 1 from jsonb_array_elements(s->'ledger') t where (t->>'childId')::uuid=kid group by t->>'jar' having sum((t->>'amountCents')::bigint)<>0)
      or exists(select 1 from jsonb_array_elements(s->'earnings') e where (e->>'childId')::uuid=kid and e->>'status'='approvedUnpaid')
    then raise exception 'Settle this child’s jar balances and pending earnings first';end if;
    if exists(select 1 from jsonb_array_elements(s->'assignments') assignment where (assignment->>'childId')::uuid=kid and assignment->>'status' not in ('approved','paid','rejected'))
    then raise exception 'Finish or review this child’s open work first';end if;
    if exists(select 1 from jsonb_array_elements(coalesce(s->'shoppingEntries','[]')) e where (e->>'childId')::uuid=kid and e->>'status'='awaitingApproval')
    then raise exception 'Review this child’s cart first';end if;
    s:=jsonb_set(s,'{archivedChildren}',coalesce(nullif(s->'archivedChildren','null'::jsonb),'[]')||jsonb_build_array(w));
    s:=jsonb_set(s,'{children}',(select jsonb_agg(c) from jsonb_array_elements(s->'children') c where (c->>'id')::uuid<>kid));
    s:=jsonb_set(s,'{members}',(select coalesce(jsonb_agg(m),'[]') from jsonb_array_elements(s->'members') m where (m->>'childId')::uuid is distinct from kid));
    -- read_child_connection checks active child membership on every access,
    -- so old links cannot read or act after this profile is removed.
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
