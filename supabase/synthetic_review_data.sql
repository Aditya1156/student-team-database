-- Synthetic-only review fixtures. All names, contact details, and identifiers are fictional.
begin;

insert into core.users (user_id, date_of_birth, gender, timezone) values
  ('00000000-0000-4000-8000-000000000001', date '1996-01-15', 'female', 'Asia/Kolkata'),
  ('00000000-0000-4000-8000-000000000002', date '1995-02-16', 'male', 'Asia/Kolkata'),
  ('00000000-0000-4000-8000-000000000003', date '1997-03-17', 'non_binary', 'Asia/Kolkata'),
  ('00000000-0000-4000-8000-000000000004', date '1994-04-18', 'female', 'Asia/Kolkata'),
  ('00000000-0000-4000-8000-000000000005', date '1998-05-19', 'male', 'Asia/Kolkata'),
  ('00000000-0000-4000-8000-000000000006', date '1993-06-20', 'prefer_not_to_say', 'Asia/Kolkata'),
  ('00000000-0000-4000-8000-000000000007', date '1999-07-21', 'female', 'Asia/Kolkata'),
  ('00000000-0000-4000-8000-000000000008', date '1992-08-22', 'male', 'Asia/Kolkata')
on conflict (user_id) do nothing;

insert into core.user_contacts (user_id, email, phone_number) values
  ('00000000-0000-4000-8000-000000000001', 'ananya@example.test', '+919000000001'),
  ('00000000-0000-4000-8000-000000000002', 'arjun@example.test', '+919000000002'),
  ('00000000-0000-4000-8000-000000000003', 'kiran@example.test', '+919000000003'),
  ('00000000-0000-4000-8000-000000000004', 'meera@example.test', '+919000000004'),
  ('00000000-0000-4000-8000-000000000005', 'rohan@example.test', '+919000000005'),
  ('00000000-0000-4000-8000-000000000006', 'samar@example.test', '+919000000006'),
  ('00000000-0000-4000-8000-000000000007', 'tara@example.test', '+919000000007'),
  ('00000000-0000-4000-8000-000000000008', 'vikram@example.test', '+919000000008')
on conflict (user_id) do nothing;

insert into core.profiles (user_id, display_name, handle, bio, city, state, profile_completeness) values
  ('00000000-0000-4000-8000-000000000001', 'Ananya Demo', 'ananya_demo', 'Synthetic design student interested in music and collaboration.', 'Bengaluru', 'Karnataka', 80),
  ('00000000-0000-4000-8000-000000000002', 'Arjun Demo', 'arjun_demo', 'Synthetic engineering student exploring mentorship.', 'Mysuru', 'Karnataka', 75),
  ('00000000-0000-4000-8000-000000000003', 'Kiran Demo', 'kiran_demo', 'Synthetic language learner and community volunteer.', 'Hyderabad', 'Telangana', 70),
  ('00000000-0000-4000-8000-000000000004', 'Meera Demo', 'meera_demo', 'Synthetic writer and performing arts enthusiast.', 'Chennai', 'Tamil Nadu', 85),
  ('00000000-0000-4000-8000-000000000005', 'Rohan Demo', 'rohan_demo', 'Synthetic sports and open-source enthusiast.', 'Pune', 'Maharashtra', 65),
  ('00000000-0000-4000-8000-000000000006', 'Samar Demo', 'samar_demo', 'Synthetic cooking and cultural exchange profile.', 'Kochi', 'Kerala', 60),
  ('00000000-0000-4000-8000-000000000007', 'Tara Demo', 'tara_demo', 'Synthetic mentor profile for database review.', 'Mumbai', 'Maharashtra', 90),
  ('00000000-0000-4000-8000-000000000008', 'Vikram Demo', 'vikram_demo', 'Synthetic learner profile for workflow testing.', 'Delhi', 'Delhi', 55)
on conflict (user_id) do update set display_name = excluded.display_name, bio = excluded.bio, city = excluded.city, state = excluded.state, profile_completeness = excluded.profile_completeness;

insert into core.notification_preferences (user_id, in_app_enabled, push_enabled, email_enabled)
select user_id, true, false, false from core.users
where user_id::text like '00000000-0000-4000-8000-00000000000%'
on conflict (user_id) do nothing;

insert into core.user_interests (user_id, interest_id, is_primary)
select u.user_id, i.id, true
from (values
  ('00000000-0000-4000-8000-000000000001'::uuid, 1),
  ('00000000-0000-4000-8000-000000000002'::uuid, 2),
  ('00000000-0000-4000-8000-000000000003'::uuid, 3),
  ('00000000-0000-4000-8000-000000000004'::uuid, 4),
  ('00000000-0000-4000-8000-000000000005'::uuid, 5),
  ('00000000-0000-4000-8000-000000000006'::uuid, 6),
  ('00000000-0000-4000-8000-000000000007'::uuid, 7),
  ('00000000-0000-4000-8000-000000000008'::uuid, 8)
) u(user_id, ordinal)
join lateral (select id from core.interests where status = 'active' order by id offset u.ordinal - 1 limit 1) i on true
on conflict (user_id, interest_id) do nothing;

insert into core.connection_requests
  (sender_user_id, recipient_user_id, category, intent_code, source_context, reason_text, idempotency_key)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002',
       'networking', intent_code, 'profile', 'Synthetic request for team review.', 'synthetic-request-001'
from core.connection_intents order by sort_order nulls last limit 1
on conflict (sender_user_id, idempotency_key) do nothing;

do $$
declare
  v_request_id bigint;
  v_connection_id bigint;
  v_conversation_id bigint;
begin
  select id into v_request_id from core.connection_requests
  where sender_user_id = '00000000-0000-4000-8000-000000000001'
    and idempotency_key = 'synthetic-request-001';
  select id into v_connection_id from core.connections where created_from_request_id = v_request_id;
  if v_connection_id is null then
    v_connection_id := core.accept_connection_request(v_request_id, '00000000-0000-4000-8000-000000000002');
  end if;
  v_conversation_id := core.ensure_direct_conversation(v_connection_id);
  perform core.send_text_message(v_conversation_id, '00000000-0000-4000-8000-000000000001',
    'synthetic-message-001', 'Hello! This is synthetic review data.');
end $$;

commit;
