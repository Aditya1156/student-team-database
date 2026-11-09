-- Synthetic-only review fixtures. All names, contact details, and identifiers are fictional.
begin;

insert into core.users (user_id, date_of_birth, gender, timezone) values
  ('7e65c188-8d8f-4ab3-b203-02cb57f15b23', date '1996-01-15', 'female', 'Asia/Kolkata'),
  ('55d7d556-8ecf-4aa3-a79b-abc3273a1bbe', date '1995-02-16', 'male', 'Asia/Kolkata'),
  ('f606248b-c0d2-4c5c-867c-76250ee3c5fa', date '1997-03-17', 'non_binary', 'Asia/Kolkata'),
  ('97547258-839d-446c-90e4-11dd514ed93b', date '1994-04-18', 'female', 'Asia/Kolkata'),
  ('7ce422ba-50c0-4c77-b186-419a351bd996', date '1998-05-19', 'male', 'Asia/Kolkata'),
  ('5d6e6546-692f-4c60-8ba1-ed6bb31202cb', date '1993-06-20', 'prefer_not_to_say', 'Asia/Kolkata'),
  ('f24cbe95-3925-4c40-892c-d4bc9b93df09', date '1999-07-21', 'female', 'Asia/Kolkata'),
  ('8e328710-5af2-4512-b412-5a3f044890c7', date '1992-08-22', 'male', 'Asia/Kolkata')
on conflict (user_id) do nothing;

insert into core.user_contacts (user_id, email, phone_number) values
  ('7e65c188-8d8f-4ab3-b203-02cb57f15b23', 'ananya@example.test', '+919000000001'),
  ('55d7d556-8ecf-4aa3-a79b-abc3273a1bbe', 'arjun@example.test', '+919000000002'),
  ('f606248b-c0d2-4c5c-867c-76250ee3c5fa', 'kiran@example.test', '+919000000003'),
  ('97547258-839d-446c-90e4-11dd514ed93b', 'meera@example.test', '+919000000004'),
  ('7ce422ba-50c0-4c77-b186-419a351bd996', 'rohan@example.test', '+919000000005'),
  ('5d6e6546-692f-4c60-8ba1-ed6bb31202cb', 'samar@example.test', '+919000000006'),
  ('f24cbe95-3925-4c40-892c-d4bc9b93df09', 'tara@example.test', '+919000000007'),
  ('8e328710-5af2-4512-b412-5a3f044890c7', 'vikram@example.test', '+919000000008')
on conflict (user_id) do nothing;

insert into core.profiles (user_id, display_name, handle, bio, city, state, profile_completeness) values
  ('7e65c188-8d8f-4ab3-b203-02cb57f15b23', 'Ananya Demo', 'ananya_demo', 'Synthetic design student interested in music and collaboration.', 'Bengaluru', 'Karnataka', 80),
  ('55d7d556-8ecf-4aa3-a79b-abc3273a1bbe', 'Arjun Demo', 'arjun_demo', 'Synthetic engineering student exploring mentorship.', 'Mysuru', 'Karnataka', 75),
  ('f606248b-c0d2-4c5c-867c-76250ee3c5fa', 'Kiran Demo', 'kiran_demo', 'Synthetic language learner and community volunteer.', 'Hyderabad', 'Telangana', 70),
  ('97547258-839d-446c-90e4-11dd514ed93b', 'Meera Demo', 'meera_demo', 'Synthetic writer and performing arts enthusiast.', 'Chennai', 'Tamil Nadu', 85),
  ('7ce422ba-50c0-4c77-b186-419a351bd996', 'Rohan Demo', 'rohan_demo', 'Synthetic sports and open-source enthusiast.', 'Pune', 'Maharashtra', 65),
  ('5d6e6546-692f-4c60-8ba1-ed6bb31202cb', 'Samar Demo', 'samar_demo', 'Synthetic cooking and cultural exchange profile.', 'Kochi', 'Kerala', 60),
  ('f24cbe95-3925-4c40-892c-d4bc9b93df09', 'Tara Demo', 'tara_demo', 'Synthetic mentor profile for database review.', 'Mumbai', 'Maharashtra', 90),
  ('8e328710-5af2-4512-b412-5a3f044890c7', 'Vikram Demo', 'vikram_demo', 'Synthetic learner profile for workflow testing.', 'Delhi', 'Delhi', 55)
on conflict (user_id) do update set display_name = excluded.display_name, bio = excluded.bio, city = excluded.city, state = excluded.state, profile_completeness = excluded.profile_completeness;

insert into core.notification_preferences (user_id, in_app_enabled, push_enabled, email_enabled)
select user_id, true, false, false from core.users
where user_id in (
  '7e65c188-8d8f-4ab3-b203-02cb57f15b23', '55d7d556-8ecf-4aa3-a79b-abc3273a1bbe',
  'f606248b-c0d2-4c5c-867c-76250ee3c5fa', '97547258-839d-446c-90e4-11dd514ed93b',
  '7ce422ba-50c0-4c77-b186-419a351bd996', '5d6e6546-692f-4c60-8ba1-ed6bb31202cb',
  'f24cbe95-3925-4c40-892c-d4bc9b93df09', '8e328710-5af2-4512-b412-5a3f044890c7'
)
on conflict (user_id) do nothing;

insert into core.user_interests (user_id, interest_id, is_primary)
select u.user_id, i.id, true
from (values
  ('7e65c188-8d8f-4ab3-b203-02cb57f15b23'::uuid, 1),
  ('55d7d556-8ecf-4aa3-a79b-abc3273a1bbe'::uuid, 2),
  ('f606248b-c0d2-4c5c-867c-76250ee3c5fa'::uuid, 3),
  ('97547258-839d-446c-90e4-11dd514ed93b'::uuid, 4),
  ('7ce422ba-50c0-4c77-b186-419a351bd996'::uuid, 5),
  ('5d6e6546-692f-4c60-8ba1-ed6bb31202cb'::uuid, 6),
  ('f24cbe95-3925-4c40-892c-d4bc9b93df09'::uuid, 7),
  ('8e328710-5af2-4512-b412-5a3f044890c7'::uuid, 8)
) u(user_id, ordinal)
join lateral (select id from core.interests where status = 'active' order by id offset u.ordinal - 1 limit 1) i on true
on conflict (user_id, interest_id) do nothing;

insert into core.connection_requests
  (sender_user_id, recipient_user_id, category, intent_code, source_context, reason_text, idempotency_key)
select '7e65c188-8d8f-4ab3-b203-02cb57f15b23', '55d7d556-8ecf-4aa3-a79b-abc3273a1bbe',
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
  where sender_user_id = '7e65c188-8d8f-4ab3-b203-02cb57f15b23'
    and idempotency_key = 'synthetic-request-001';
  select id into v_connection_id from core.connections where created_from_request_id = v_request_id;
  if v_connection_id is null then
    v_connection_id := core.accept_connection_request(v_request_id, '55d7d556-8ecf-4aa3-a79b-abc3273a1bbe');
  end if;
  v_conversation_id := core.ensure_direct_conversation(v_connection_id);
  perform core.send_text_message(v_conversation_id, '7e65c188-8d8f-4ab3-b203-02cb57f15b23',
    'synthetic-message-001', 'Hello! This is synthetic review data.');
end $$;

commit;
