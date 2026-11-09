do $$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from information_schema.tables
  where table_schema in ('core', 'safety', 'analytics', 'audit')
    and table_type = 'BASE TABLE';
  if v_count <> 49 then
    raise exception 'Expected 49 application tables, found %', v_count;
  end if;

  if (select count(*) from core.users) <> 50 then raise exception 'Aditya user fixture count mismatch'; end if;
  if (select count(*) from core.user_contacts) <> 50 then raise exception 'Aditya contact fixture count mismatch'; end if;
  if (select count(*) from core.user_verifications) <> 50 then raise exception 'Aditya verification fixture count mismatch'; end if;

  select count(*) into v_count
  from pg_catalog.pg_tables
  where schemaname in ('core', 'safety', 'analytics', 'audit')
    and not rowsecurity;
  if v_count <> 0 then
    raise exception 'Found % application tables without RLS', v_count;
  end if;

  if has_schema_privilege('anon', 'core', 'USAGE')
     or has_schema_privilege('authenticated', 'core', 'USAGE') then
    raise exception 'Client-facing roles unexpectedly have core schema access';
  end if;
end $$;

select 'schema_contract_ok' as result;
