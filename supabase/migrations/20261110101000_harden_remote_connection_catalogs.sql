-- These catalog tables were added directly to the linked project outside the
-- repository migration history. Preserve their structure and data while
-- bringing them under the application's mandatory RLS baseline when present.
alter table if exists core.connection_modes enable row level security;
alter table if exists core.connection_mode_intents enable row level security;

do $$
declare v_table text;
begin
  foreach v_table in array array['connection_modes','connection_mode_intents'] loop
    if to_regclass('core.'||v_table) is not null then
      execute format('revoke all on table core.%I from anon,authenticated',v_table);
      execute format('grant all on table core.%I to service_role',v_table);
    end if;
  end loop;
end $$;
