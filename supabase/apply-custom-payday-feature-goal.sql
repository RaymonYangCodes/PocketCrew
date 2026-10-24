-- Guarded equivalent of 202610060001_custom_payday_feature_goal.sql.
begin;
do $update$
declare m text; s text;
begin
  select pg_get_functiondef(oid) into m from pg_proc where oid='public.family_money_command(jsonb,uuid,text,jsonb,uuid,text)'::regprocedure;
  if (select md5(prosrc) from pg_proc where oid='public.family_money_command(jsonb,uuid,text,jsonb,uuid,text)'::regprocedure)<>'db720b4078c31dae3d2b613779887eec' then raise exception 'Unexpected money function version; no changes made'; end if;
  select pg_get_functiondef(oid) into s from pg_proc where oid='public.family_shopping_command(uuid,bigint,uuid,text,jsonb,text,text)'::regprocedure;
  if (select md5(prosrc) from pg_proc where oid='public.family_shopping_command(uuid,bigint,uuid,text,jsonb,text,text)'::regprocedure)<>'e26450dcb4053e88c76f3ce198897dfb' then raise exception 'Unexpected shopping function version; no changes made'; end if;
  m:=replace(m,$a$('weekly','biweekly','twiceMonthly','monthly')$a$,$a$('weekly','biweekly','twiceMonthly','monthly','custom')$a$);
  m:=replace(m,$a$  elsif action='schedule' then$a$,$a$  elsif action='schedule' then
    if d->>'frequency'='custom' then
      if coalesce(d->>'customDays','') !~ '^[0-9]{1,3}$' then raise exception 'Enter a whole number from 1 to 365 days'; end if;
      if (d->>'customDays')::integer not between 1 and 365 then raise exception 'Enter a whole number from 1 to 365 days'; end if;
    end if;$a$);
  m:=replace(m,$a$'frequency',coalesce(d->>'frequency','weekly'),$a$,$a$'frequency',coalesce(d->>'frequency','weekly'),'customDays',case when d->>'frequency'='custom' then (d->>'customDays')::integer else null end,$a$);
  m:=replace(m,E'\n      else nextdate:=',$a$
      elsif s->'schedule'->>'frequency'='custom' then
        if coalesce(s->'schedule'->>'customDays','') !~ '^[0-9]{1,3}$' then raise exception 'Invalid custom payday interval'; end if;
        if (s->'schedule'->>'customDays')::integer not between 1 and 365 then raise exception 'Invalid custom payday interval'; end if;
        nextdate:=((nextdate at time zone (s->'family'->>'timezone'))+make_interval(days => (s->'schedule'->>'customDays')::integer)) at time zone (s->'family'->>'timezone');
      else nextdate:=$a$);
  s:=replace(s,$a$('add','cart','remove','goal')$a$,$a$('add','cart','remove','goal','featureGoal')$a$);
  s:=replace(s,$a$'decline','reviewGoal')$a$,$a$'decline','reviewGoal','featureGoal')$a$);
  s:=replace(s,$a$  if p_action='reviewGoal' then$a$,$a$  if p_action='featureGoal' then
    select value into goal from jsonb_array_elements(s->'goals') where (value->>'id')::uuid=(p_data->>'id')::uuid;
    if goal is null or goal->>'status' is distinct from 'active' then raise exception 'Choose an approved active goal'; end if;
    kid:=(goal->>'childId')::uuid;
    if not guardian and kid<>actor then raise exception 'Choose your own goal'; end if;
    if not exists(select 1 from jsonb_array_elements(s->'children') c where (c->>'id')::uuid=kid and c->>'status'='active') then raise exception 'Child is not active'; end if;
    s:=jsonb_set(s,'{goals}',(select jsonb_agg(case when (g->>'childId')::uuid=kid then g||jsonb_build_object('featured',g->>'id'=goal->>'id','updatedAt',stamp) else g end order by n) from jsonb_array_elements(s->'goals') with ordinality as a(g,n)));
  elsif p_action='reviewGoal' then$a$);
  execute m;
  execute s;
end;
$update$;
commit;
