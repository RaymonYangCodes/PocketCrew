begin;
do $update$
declare s text;
begin
  select pg_get_functiondef(oid) into s from pg_proc where oid='public.family_shopping_command(uuid,bigint,uuid,text,jsonb,text,text)'::regprocedure;
  if (select md5(prosrc) from pg_proc where oid='public.family_shopping_command(uuid,bigint,uuid,text,jsonb,text,text)'::regprocedure)<>'f39d4cac2243a899510bce43f487ebd4' then raise exception 'Unexpected shopping function version; no changes made'; end if;
  s:=replace(s,$a$'featureGoal')$a$,$a$'featureGoal','archiveGoal')$a$);
  s:=replace(s,$a$  if p_action='featureGoal' then$a$,$a$  if p_action='archiveGoal' then
    select value,(ordinality-1)::integer into goal,idx from jsonb_array_elements(s->'goals') with ordinality where (value->>'id')::uuid=(p_data->>'id')::uuid;
    if goal is null or goal->>'status'='archived' then raise exception 'Goal is no longer available'; end if;
    kid:=(goal->>'childId')::uuid;
    if not guardian and kid<>actor then raise exception 'You can only remove your own goals'; end if;
    if not exists(select 1 from jsonb_array_elements(s->'children') c where (c->>'id')::uuid=kid and c->>'status'='active') then raise exception 'Child is not active'; end if;
    s:=jsonb_set(s,array['goals',idx::text],goal||jsonb_build_object('status','archived','featured',false,'updatedAt',stamp));
  elsif p_action='featureGoal' then$a$);
  execute s;
end;
$update$;
commit;
