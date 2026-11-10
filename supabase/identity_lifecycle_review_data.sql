-- Synthetic-only session coverage for the existing 50 review users.
begin;
insert into core.auth_sessions
  (session_id,session_family_id,user_id,auth_identity_id,refresh_token_hash,refresh_token_version,device_id,ip_hmac,user_agent_hash,status,created_at,last_seen_at,expires_at,idle_expires_at,revoked_at,revocation_reason,updated_at)
select extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000012'::uuid,'session-'||u.n),
       extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000013'::uuid,'family-'||u.n),
       u.user_id,i.id,extensions.digest('refresh-token-'||u.n,'sha256'),1,'synthetic-device-'||u.n,
       extensions.digest('session-ip-'||u.n,'sha256'),extensions.digest('agent-'||u.n,'sha256'),s.session_status,
       clock_timestamp()-interval '5 days',clock_timestamp()-interval '1 day',
       case when s.session_status='expired' then clock_timestamp()-interval '1 day' else clock_timestamp()+interval '25 days' end,
       case when s.session_status='expired' then clock_timestamp()-interval '2 days' else clock_timestamp()+interval '6 days' end,
       case when s.session_status<>'active' then clock_timestamp()-interval '1 day' end,
       case when s.session_status<>'active' then (array['user_logout','security_event','absolute_expiry'])[((u.n-1)%3)+1] end,
       clock_timestamp()-interval '1 hour'
from (select user_id,row_number() over(order by id)::int n from core.users) u
join lateral(select id,status from core.auth_identities where user_id=u.user_id order by id limit 1)i on true
join lateral(select case when i.status<>'active' then 'revoked' else (array['active','revoked','expired','compromised'])[((u.n-1)%4)+1] end session_status)s on true
on conflict(session_id) do nothing;

do $$
begin
  if (select count(*) from core.auth_sessions)<>50 then raise exception 'Expected 50 synthetic auth sessions'; end if;
  if exists(
    select 1 from core.auth_sessions s join core.auth_identities i on i.id=s.auth_identity_id
    where s.status='active' and i.status<>'active'
  ) then raise exception 'Active session is linked to an inactive identity'; end if;
  if (select count(distinct status) from core.auth_sessions)<>4 then raise exception 'Session state coverage mismatch'; end if;
end $$;
commit;
