-- Replace the visibly sequential review-fixture IDs with realistic UUIDv4 values.
-- Production users already use core.users.user_id DEFAULT extensions.gen_random_uuid().
create temporary table synthetic_user_id_map (
  old_id uuid primary key,
  new_id uuid not null unique
) on commit drop;

insert into synthetic_user_id_map (old_id, new_id) values
  ('00000000-0000-4000-8000-000000000001', '7e65c188-8d8f-4ab3-b203-02cb57f15b23'),
  ('00000000-0000-4000-8000-000000000002', '55d7d556-8ecf-4aa3-a79b-abc3273a1bbe'),
  ('00000000-0000-4000-8000-000000000003', 'f606248b-c0d2-4c5c-867c-76250ee3c5fa'),
  ('00000000-0000-4000-8000-000000000004', '97547258-839d-446c-90e4-11dd514ed93b'),
  ('00000000-0000-4000-8000-000000000005', '7ce422ba-50c0-4c77-b186-419a351bd996'),
  ('00000000-0000-4000-8000-000000000006', '5d6e6546-692f-4c60-8ba1-ed6bb31202cb'),
  ('00000000-0000-4000-8000-000000000007', 'f24cbe95-3925-4c40-892c-d4bc9b93df09'),
  ('00000000-0000-4000-8000-000000000008', '8e328710-5af2-4512-b412-5a3f044890c7');

-- Remove the small synthetic messaging workflow before changing both sides of
-- its canonical user pair. The seed recreates it with the new IDs.
delete from core.message_read_cursors
where conversation_id in (
  select cv.id from core.conversations cv
  join core.connections cn on cn.id = cv.connection_id
  join core.connection_requests cr on cr.id = cn.created_from_request_id
  where cr.idempotency_key = 'synthetic-request-001'
);
delete from core.messages
where conversation_id in (
  select cv.id from core.conversations cv
  join core.connections cn on cn.id = cv.connection_id
  join core.connection_requests cr on cr.id = cn.created_from_request_id
  where cr.idempotency_key = 'synthetic-request-001'
);
delete from core.conversation_participants
where conversation_id in (
  select cv.id from core.conversations cv
  join core.connections cn on cn.id = cv.connection_id
  join core.connection_requests cr on cr.id = cn.created_from_request_id
  where cr.idempotency_key = 'synthetic-request-001'
);
delete from core.conversations
where connection_id in (
  select cn.id from core.connections cn
  join core.connection_requests cr on cr.id = cn.created_from_request_id
  where cr.idempotency_key = 'synthetic-request-001'
);
delete from core.outbox_events
where event_key like 'message.sent:%'
   or event_key in (
     select 'connection.created:' || cn.id::text from core.connections cn
     join core.connection_requests cr on cr.id = cn.created_from_request_id
     where cr.idempotency_key = 'synthetic-request-001'
   );
delete from core.connections
where created_from_request_id in (
  select id from core.connection_requests where idempotency_key = 'synthetic-request-001'
);
delete from core.connection_requests where idempotency_key = 'synthetic-request-001';

insert into core.users (user_id, date_of_birth, gender, timezone)
select m.new_id, u.date_of_birth, u.gender, u.timezone
from synthetic_user_id_map m
join core.users u on u.user_id = m.old_id
on conflict (user_id) do nothing;

-- New user insertion creates these two child records. Retain the old fixture
-- records by moving them, so review history remains intact.
delete from core.user_verifications v using synthetic_user_id_map m where v.user_id = m.new_id;
alter table core.user_status_history disable trigger user_status_history_append_only_trg;
delete from core.user_status_history h using synthetic_user_id_map m where h.user_id = m.new_id;
alter table core.user_consents disable trigger user_consents_append_only_trg;
alter table core.user_contacts disable trigger user_contacts_before_write_trg;
alter table core.user_verifications disable trigger user_verifications_before_write_trg;

do $$
declare
  r record;
begin
  for r in
    select c.conrelid::regclass as table_name, a.attname as column_name
    from pg_catalog.pg_constraint c
    join lateral unnest(c.conkey) with ordinality ck(attnum, ord) on true
    join lateral unnest(c.confkey) with ordinality fk(attnum, ord) on fk.ord = ck.ord
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = ck.attnum
    join pg_catalog.pg_attribute ra on ra.attrelid = c.confrelid and ra.attnum = fk.attnum
    where c.contype = 'f'
      and c.confrelid = 'core.users'::regclass
      and ra.attname = 'user_id'
      and array_length(c.conkey, 1) = 1
  loop
    execute format(
      'update %s t set %I = m.new_id from synthetic_user_id_map m where t.%I = m.old_id',
      r.table_name, r.column_name, r.column_name
    );
  end loop;
end $$;

alter table core.user_consents enable trigger user_consents_append_only_trg;
alter table core.user_status_history enable trigger user_status_history_append_only_trg;
alter table core.user_contacts enable trigger user_contacts_before_write_trg;
alter table core.user_verifications enable trigger user_verifications_before_write_trg;

delete from core.users u using synthetic_user_id_map m where u.user_id = m.old_id;

do $$
begin
  if exists (
    select 1 from core.users
    where user_id::text like '00000000-0000-4000-8000-00000000000%'
  ) then
    raise exception 'Sequential synthetic user IDs remain after migration';
  end if;
end $$;
