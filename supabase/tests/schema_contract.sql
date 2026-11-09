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

  if (select count(*) from core.interest_categories) <> 11 then raise exception 'Interest category count mismatch'; end if;
  if (select count(*) from core.interest_subcategories) <> 60 then raise exception 'Interest subcategory count mismatch'; end if;
  if (select count(*) from core.interests) <> 962 then raise exception 'Interest count mismatch'; end if;
  if (select count(*) from core.prompt_catalogue) <> 100 then raise exception 'Prompt count mismatch'; end if;
  if (select count(*) from core.connection_intents) <> 110 then raise exception 'Connection-intent count mismatch'; end if;
  if (select count(*) from safety.report_category_subcategories) <> 219 then raise exception 'Safety taxonomy count mismatch'; end if;
  if (select count(*) from core.notification_categories) <> 38 then raise exception 'Notification-category count mismatch'; end if;
  if (select count(*) from core.connection_closed_reasons) <> 41 then raise exception 'Connection-close reason count mismatch'; end if;

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
