-- Deterministic catalog projection used by the DB-027 drift check.
with target_tables as (
  select c.oid, n.nspname as schema_name, c.relname as table_name
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r','p')
    and n.nspname in ('core','safety','analytics','audit')
),
catalog as (
  select 'table'::text as object_kind, t.schema_name, t.table_name,
    t.table_name::text as object_name, 'TABLE'::text as definition,
    null::text as parent_schema, null::text as parent_table,
    null::text as child_columns, null::text as parent_columns,
    null::text as delete_action
  from target_tables t

  union all

  select 'column', t.schema_name, t.table_name, a.attname,
    format('%s|nullable=%s|identity=%s|generated=%s|default=%s',
      format_type(a.atttypid, a.atttypmod),
      case when a.attnotnull then 'no' else 'yes' end,
      coalesce(nullif(a.attidentity::text, ''), 'none'),
      coalesce(nullif(a.attgenerated::text, ''), 'none'),
      coalesce(pg_get_expr(d.adbin, d.adrelid), '')),
    null, null, null, null, null
  from target_tables t
  join pg_attribute a on a.attrelid = t.oid
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attnum > 0 and not a.attisdropped

  union all

  select case when con.contype = 'f' then 'foreign_key' else 'constraint' end,
    t.schema_name, t.table_name, con.conname,
    pg_get_constraintdef(con.oid, true), pn.nspname, pc.relname,
    (select string_agg(a.attname, ',' order by k.ordinality)
       from unnest(con.conkey) with ordinality k(attnum, ordinality)
       join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum),
    (select string_agg(a.attname, ',' order by k.ordinality)
       from unnest(con.confkey) with ordinality k(attnum, ordinality)
       join pg_attribute a on a.attrelid = con.confrelid and a.attnum = k.attnum),
    case con.confdeltype
      when 'a' then 'no action' when 'r' then 'restrict' when 'c' then 'cascade'
      when 'n' then 'set null' when 'd' then 'set default' else null end
  from target_tables t
  join pg_constraint con on con.conrelid = t.oid and con.contype in ('p','u','c','x','f')
  left join pg_class pc on pc.oid = con.confrelid
  left join pg_namespace pn on pn.oid = pc.relnamespace

  union all

  select 'index', t.schema_name, t.table_name, i.relname,
    pg_get_indexdef(i.oid), null, null, null, null, null
  from target_tables t
  join pg_index x on x.indrelid = t.oid
  join pg_class i on i.oid = x.indexrelid
  left join pg_constraint con on con.conindid = i.oid
  where con.oid is null
)
select object_kind, schema_name, table_name, object_name, definition,
  parent_schema, parent_table, child_columns, parent_columns, delete_action
from catalog
order by schema_name, table_name,
  case object_kind when 'table' then 1 when 'column' then 2
    when 'constraint' then 3 when 'foreign_key' then 4 else 5 end,
  object_name;
