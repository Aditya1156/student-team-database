-- Read-only metadata inspection. No application rows or secrets are selected.
select jsonb_build_object(
  'database_version', current_setting('server_version'),
  'schemas', coalesce((
    select jsonb_agg(nspname order by nspname)
    from pg_catalog.pg_namespace
    where nspname in ('core', 'safety', 'analytics', 'audit', 'public')
  ), '[]'::jsonb),
  'relations', coalesce((
    select jsonb_agg(jsonb_build_object(
      'schema', n.nspname,
      'name', c.relname,
      'kind', c.relkind,
      'rls_enabled', c.relrowsecurity
    ) order by n.nspname, c.relname)
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('core', 'safety', 'analytics', 'audit', 'public')
      and c.relkind in ('r', 'p', 'v', 'm')
  ), '[]'::jsonb)
) as schema_snapshot;
