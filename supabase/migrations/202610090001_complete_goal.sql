begin;
do $update$
declare s text; old text;
begin
  select pg_get_functiondef('public.family_shopping_command(uuid,bigint,uuid,text,jsonb,text,text)'::regprocedure) into s;
  old:=s;
  s:=replace(s,'''reviewGoal''','''completeGoal'',''reviewGoal''');
  -- The replacement above also touches comparisons; restore that comparison.
  s:=replace(s,'p_action=''completeGoal'',''reviewGoal''','p_action=''reviewGoal''');
  if s=old then raise exception 'Shopping action guard not found'; end if;
  if position('  if p_action=''archiveGoal'' then' in s)=0 then raise exception 'Archive goal branch not found'; end if;
  s:=replace(s,$a$  if p_action='archiveGoal' then$a$,$a$  if p_action='completeGoal' then
    if not guardian then raise exception 'Parent sign-in required'; end if;
    select value,(ordinality-1)::integer into goal,idx from jsonb_array_elements(s->'goals') with ordinality where (value->>'id')::uuid=(p_data->>'id')::uuid;
    if goal is null or goal->>'status'<>'active' then raise exception 'Choose an active goal that has not already been completed'; end if;
    amount:=(goal->>'targetCents')::bigint;
    if amount<1 or coalesce(p_data->>'expectedPrice','')<>amount::text then raise exception 'The target changed. Review the goal again'; end if;
    kid:=(goal->>'childId')::uuid;
    s:=public.family_money_command(s,actor,'record',jsonb_build_object('childId',kid,'jar','spend','amount',amount,'reason','Goal completed · '||left(goal->>'title',125)),p_command_id,stamp);
    s:=jsonb_set(s,array['goals',idx::text],goal||jsonb_build_object('status','completed','featured',false,'updatedAt',stamp));
  elsif p_action='archiveGoal' then$a$);
  execute s;
  select pg_get_functiondef('public.family_money_command(jsonb,uuid,text,jsonb,uuid,text)'::regprocedure) into s;
  s:=replace(s,$a$case when amount=(g->>'targetCents')::bigint then 'completed' else 'active' end$a$,$a$'active'$a$);
  s:=replace(s,$a$case when reduction>0 then 'active' else g->>'status' end$a$,$a$g->>'status'$a$);
  execute s;
end;
$update$;
commit;
