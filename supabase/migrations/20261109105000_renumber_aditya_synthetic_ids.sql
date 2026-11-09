-- Synthetic review convenience only. Reset application data and identity
-- sequences; the approved Aditya-only fixture is loaded immediately afterward.
-- Production logic must never depend on identity values being gap-free.
do $$
declare
  v_tables text;
  v_count integer;
begin
  select count(*),
         string_agg(format('%I.%I', schemaname, tablename), ', ' order by schemaname, tablename)
    into v_count, v_tables
  from pg_catalog.pg_tables
  where schemaname in ('core', 'safety', 'analytics', 'audit');

  if v_count <> 49 then
    raise exception 'Safety check failed: expected 49 application tables, found %', v_count;
  end if;

  execute 'truncate table ' || v_tables || ' restart identity';
end $$;
