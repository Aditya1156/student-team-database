import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function body(file) {
  return fs.readFileSync(path.join(root, file), 'utf8')
    .split(/\r?\n/)
    .filter((line) => !/^\s*(begin|commit);\s*$/i.test(line))
    .join('\n')
    .trim();
}

const tables = [
  'audit.audit_product_event',
  'safety.report_evidence', 'safety.legal_holds', 'safety.moderation_appeals',
  'safety.moderation_actions', 'safety.reports', 'safety.report_category_subcategories',
  'safety.admin_users',
  'analytics.discovery_impressions', 'analytics.product_events',
  'core.media_deletion_jobs', 'core.account_data_job_steps', 'core.account_data_jobs',
  'core.notifications', 'core.outbox_events', 'core.message_read_cursors', 'core.messages',
  'core.conversation_participants', 'core.conversations', 'core.acknowledgements',
  'core.discovery_dismissals', 'core.relations', 'core.connections', 'core.device_tokens',
  'core.notification_category_preferences', 'core.connection_closed_reasons',
  'core.notification_category_channels', 'core.notification_categories', 'core.profile_media',
  'core.user_pseudonyms', 'core.blocks', 'core.connection_requests', 'core.connection_intents',
  'core.user_languages', 'core.notification_preferences', 'core.profile_prompts',
  'core.user_interests', 'core.profiles', 'core.prompt_catalogue', 'core.interests',
  'core.interest_subcategories', 'core.interest_categories', 'core.user_status_history',
  'core.auth_sessions', 'core.user_consents', 'core.policy_versions', 'core.user_otp_challenges', 'core.user_verifications',
  'core.user_contacts', 'core.auth_identities', 'core.users'
];

const moduleSql = String.raw`
-- Every non-reference record below derives from the same 50 core.users rows.
do $$
begin
  if (select count(*) from core.users) <> 50 then
    raise exception 'Full-team fixture requires exactly 50 synthetic users';
  end if;
end $$;

insert into core.profile_media
  (media_id,user_id,storage_bucket,object_key,media_type,moderation_status,lifecycle_status,sort_order,created_at,deleted_at,purge_after,purged_at)
select extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000001'::uuid, 'media-'||n),
       user_id,
       case when n % 7 = 0 then 'quarantine-profile-media' else 'user-profile-media-prod' end,
       'synthetic/users/'||lpad(n::text,2,'0')||'/profile-'||n||'.bin',
       (array['image','video','audio'])[((n-1)%3)+1],
       (array['pending','approved','rejected','quarantined'])[((n-1)%4)+1],
       (array['active','deleted','purged'])[((n-1)%3)+1],
       0,
       clock_timestamp()-interval '90 days'+n*interval '1 hour',
       case when n%3=1 then null else clock_timestamp()-interval '30 days' end,
       case when n%3=1 then null else clock_timestamp()+interval '60 days' end,
       case when n%3=0 then clock_timestamp()-interval '1 day' else null end
from (select user_id,row_number() over(order by id)::int n from core.users) u;

insert into core.profiles
  (user_id,display_name,handle,bio,city,state,country,visibility_status,profile_media_id,profile_completeness,created_at,updated_at,deleted_at)
select u.user_id,
       'Synthetic Member '||lpad(u.n::text,2,'0'),
       'synthetic_member_'||lpad(u.n::text,2,'0'),
       case when u.n%5=0 then null else 'Fictional profile for testing interest, discovery, messaging, and safety workflows.' end,
       (array['Bengaluru','Mysuru','Mangaluru','Hubballi','Belagavi'])[((u.n-1)%5)+1],
       'Karnataka','India',
       (array['visible','hidden'])[((u.n-1)%2)+1],
       m.media_id,
       ((u.n*13)%101)::smallint,
       clock_timestamp()-interval '89 days'+u.n*interval '1 hour',
       clock_timestamp()-interval '1 day',
       case when u.n%10=0 then clock_timestamp()-interval '2 hours' else null end
from (select user_id,row_number() over(order by id)::int n from core.users) u
join core.profile_media m on m.user_id=u.user_id;

insert into core.user_interests(user_id,interest_id,is_primary)
select u.user_id, i.id, x.k=1
from (select user_id,row_number() over(order by id)::int n from core.users) u
cross join generate_series(1,3) x(k)
join lateral (
  select id from core.interests
  order by id
  offset ((u.n-1)*3+x.k-1) % (select count(*) from core.interests)
  limit 1
) i on true;

insert into core.profile_prompts(user_id,prompt_code,answer,status,block_prompt_code,created_at,updated_at)
select u.user_id,p.prompt_code,
       jsonb_build_object('version',1,'response','Synthetic answer '||u.n||'-'||x.k),
       (array['active','hidden','removed'])[((u.n+x.k-2)%3)+1],
       case when ((u.n+x.k-2)%3)+1=3 then 'synthetic_policy_block' else null end,
       clock_timestamp()-interval '40 days'+(u.n+x.k)*interval '1 minute',clock_timestamp()-interval '1 day'
from (select user_id,row_number() over(order by id)::int n from core.users) u
cross join generate_series(1,2) x(k)
join lateral (select prompt_code from core.prompt_catalogue order by id offset ((u.n-1)*2+x.k-1)%100 limit 1) p on true;

insert into core.notification_preferences
  (user_id,in_app_enabled,push_enabled,email_enabled,marketing_enabled,marketing_consent_at,quiet_hours_start,quiet_hours_end,quiet_hours_timezone)
select user_id,true,n%2=0,n%3=0,n%4=0,
       case when n%4=0 then clock_timestamp()-interval '60 days' end,
       case when n%3=0 then time '22:00' end,
       case when n%3=0 then time '07:00' end,
       case when n%3=0 then 'Asia/Kolkata' end
from (select user_id,row_number() over(order by id)::int n from core.users) u;

insert into core.user_languages(user_id,language_id,proficiency_level,learning_intent)
select u.user_id,l.id,
       (array['beginner','intermediate','advanced','native'])[((u.n-1)%4)+1],
       (array['want_to_learn','willing_to_teach','conversational_practice','cultural_interest','language_exchange',null])
         [((u.n-1)%6)+1]
from (select user_id,row_number() over(order by id)::int n from core.users) u
join lateral (
  select i.id from core.interests i
  join core.interest_subcategories s on s.id=i.subcategory_id
  join core.interest_categories c on c.id=s.category_id
  where c.name='Languages' order by i.id offset (u.n-1)%(select count(*) from core.interests i2 join core.interest_subcategories s2 on s2.id=i2.subcategory_id join core.interest_categories c2 on c2.id=s2.category_id where c2.name='Languages') limit 1
) l on true;

insert into core.user_pseudonyms(pseudonym_id,user_id,handle,scope,status,is_default,created_at,rotated_at)
select extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000002'::uuid,'pseudonym-'||n),user_id,
       'reviewer_'||lpad(n::text,2,'0'),
       (array['anonymous_feedback','blind_recruiting','community_forum','public_networking','private_group'])[((n-1)%5)+1],
       (array['active','rotated','revoked','dormant'])[((n-1)%4)+1],
       ((n-1)%4)=0,
       clock_timestamp()-interval '80 days',
       case when ((n-1)%4)+1=2 then clock_timestamp()-interval '10 days' end
from (select user_id,row_number() over(order by id)::int n from core.users) u;

insert into core.notification_category_preferences
  (user_id,channel,category,enabled,priority_level,preferred_notification_period,snoozed_from,snoozed_until)
select u.user_id,c.channel,c.category_code,u.n%5<>0,
       (array['critical','high','normal','low'])[((u.n-1)%4)+1],
       (array['anytime','morning','afternoon','evening',null])[((u.n-1)%5)+1],
       case when u.n%7=0 then clock_timestamp()-interval '1 day' end,
       case when u.n%7=0 then clock_timestamp()+interval '1 day' end
from (select user_id,row_number() over(order by id)::int n from core.users) u
join lateral (select channel,category_code from core.notification_category_channels order by category_code,channel offset (u.n-1)%(select count(*) from core.notification_category_channels) limit 1) c on true;

insert into core.device_tokens
  (user_id,provider,platform,token_ciphertext,token_nonce,token_key_version,token_fingerprint,status,created_at,expired_at,revoked_at,invalidated_at)
select user_id,
       (array['fcm','apns','apns','apns','wns','webpush'])[((n-1)%6)+1],
       (array['android','ios','ipados','macos','windows','web'])[((n-1)%6)+1],
       extensions.digest('ciphertext-'||n,'sha256'),
       substring(extensions.digest('nonce-'||n,'sha256') from 1 for 12),'synthetic-k1',
       extensions.digest('fingerprint-'||n,'sha256'),
       (array['active','revoked','invalid','expired'])[((n-1)%4)+1],
       clock_timestamp()-interval '30 days',
       case when ((n-1)%4)+1=4 then clock_timestamp()+interval '1 day' end,
       case when ((n-1)%4)+1=2 then clock_timestamp()-interval '1 day' end,
       case when ((n-1)%4)+1=3 then clock_timestamp()-interval '1 day' end
from (select user_id,row_number() over(order by id)::int n from core.users) u;

insert into core.auth_sessions
  (session_id,session_family_id,user_id,auth_identity_id,refresh_token_hash,refresh_token_version,device_id,ip_hmac,user_agent_hash,status,created_at,last_seen_at,expires_at,idle_expires_at,revoked_at,revocation_reason,updated_at)
select extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000012'::uuid,'session-'||u.n),
       extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000013'::uuid,'family-'||u.n),
       u.user_id,i.id,extensions.digest('refresh-token-'||u.n,'sha256'),1,'synthetic-device-'||u.n,
       extensions.digest('session-ip-'||u.n,'sha256'),extensions.digest('agent-'||u.n,'sha256'),
       s.session_status,
       clock_timestamp()-interval '5 days',clock_timestamp()-interval '1 day',
       case when s.session_status='expired' then clock_timestamp()-interval '1 day' else clock_timestamp()+interval '25 days' end,
       case when s.session_status='expired' then clock_timestamp()-interval '2 days' else clock_timestamp()+interval '6 days' end,
       case when s.session_status<>'active' then clock_timestamp()-interval '1 day' end,
       case when s.session_status<>'active' then (array['user_logout','security_event','absolute_expiry'])[((u.n-1)%3)+1] end,
       clock_timestamp()-interval '1 hour'
from (select user_id,row_number() over(order by id)::int n from core.users) u
join lateral(select id,status from core.auth_identities where user_id=u.user_id order by id limit 1)i on true
join lateral(select case when i.status<>'active' then 'revoked' else (array['active','revoked','expired','compromised'])[((u.n-1)%4)+1] end session_status)s on true;

insert into core.connection_requests
  (sender_user_id,recipient_user_id,category,intent_code,source_context,status,reason_text,idempotency_key,created_at,responded_at,expires_at,cooldown_until)
select a.user_id,b.user_id,
       (array['collaboration','colleague','friendship','mentorship','networking'])[((a.n-1)%5)+1],
       i.intent_code,
       (array['events','mutual_connections','profile','search','suggestions'])[((a.n-1)%5)+1],
       case when a.n<=25 then 'accepted' else (array['pending','declined','withdrawn','cancelled','expired'])[((a.n-26)%5)+1] end,
       'Synthetic request scenario '||a.n,'team-request-'||a.n,
       clock_timestamp()-interval '35 days'+a.n*interval '1 minute',
       case when a.n<=25 or ((a.n-26)%5)+1 in (2,3,4) then clock_timestamp()-interval '34 days'+a.n*interval '1 minute' end,
       clock_timestamp()+interval '30 days',
       case when a.n>25 and ((a.n-26)%5)+1 in (2,3,4) then clock_timestamp()+interval '7 days' end
from (select user_id,row_number() over(order by id)::int n from core.users) a
join (select user_id,row_number() over(order by id)::int n from core.users) b on b.n=(a.n%50)+1
join lateral (select intent_code from core.connection_intents order by sort_order offset (a.n-1)%110 limit 1) i on true;

insert into core.blocks
  (blocker_user_id,blocked_user_id,block_type,reason_code,source,source_context,created_at,expires_at,removed_at)
select a.user_id,b.user_id,(array['dms_only','full','mute','soft_block'])[((a.n-1)%4)+1],
       (array['spam','harassment','privacy','safety',null])[((a.n-1)%5)+1],
       (array['user','moderator'])[((a.n-1)%2)+1],
       (array['comments','direct_message','group_chat','profile_page','search_results'])[((a.n-1)%5)+1],
       clock_timestamp()-interval '20 days',
       case when a.n%3=0 then clock_timestamp()+interval '10 days' end,
       case when a.n%4=0 then clock_timestamp()-interval '2 days' end
from (select user_id,row_number() over(order by id)::int n from core.users) a
join (select user_id,row_number() over(order by id)::int n from core.users) b on b.n=((a.n+7-1)%50)+1;

insert into core.connections
  (user_low_id,user_high_id,status,created_from_request_id,connection_source,created_at,closed_at,closed_reason,closed_by_type,closed_by_user_id,last_interaction_at,interaction_count)
select least(r.sender_user_id,r.recipient_user_id),greatest(r.sender_user_id,r.recipient_user_id),
       case when r.rn<=3 then 'closed' else 'active' end,r.id,r.source_context,
       r.created_at,
       case when r.rn<=3 then r.created_at+interval '10 days' end,
       case when r.rn<=3 then cr.code end,
       case when r.rn<=3 then (array['user','admin','system'])[r.rn] end,
       case when r.rn=1 then least(r.sender_user_id,r.recipient_user_id) end,
       r.created_at+interval '5 days',r.rn*3
from (select q.*,row_number() over(order by id)::int rn from core.connection_requests q where status='accepted') r
left join lateral (
  select code from core.connection_closed_reasons
  where closed_by_type=(array['user','admin','system'])[r.rn]
  order by code limit 1
) cr on r.rn<=3;

insert into core.relations
  (actor_user_id,target_user_id,profile_prompt_id,relation_source,reaction_type,status,idempotency_key,created_at,expires_at,undone_at)
select a.user_id,b.user_id,
       case when a.n%2=0 then p.id end,
       (array['profile','prompt_answer','search','mutual_connections','suggestions'])[((a.n-1)%5)+1],
       (array['like','wave','endorse','react'])[((a.n-1)%4)+1],
       (array['active','undone','hidden','expired'])[((a.n-1)%4)+1],
       'team-relation-'||a.n,clock_timestamp()-interval '15 days',
       case when ((a.n-1)%4)+1=4 then clock_timestamp()+interval '15 days' end,
       case when ((a.n-1)%4)+1=2 then clock_timestamp()-interval '5 days' end
from (select user_id,row_number() over(order by id)::int n from core.users) a
join (select user_id,row_number() over(order by id)::int n from core.users) b on b.n=((a.n+11-1)%50)+1
left join lateral (select id from core.profile_prompts where user_id=b.user_id order by id limit 1) p on true;

insert into core.discovery_dismissals
  (viewer_user_id,candidate_user_id,scope,reason_code,created_at,expires_at,category_code,reversed_at)
select a.user_id,b.user_id,(array['temporary','all','category'])[((a.n-1)%3)+1],
       (array['not_relevant','already_known','not_interested',null])[((a.n-1)%4)+1],clock_timestamp()-interval '10 days',
       case when ((a.n-1)%3)+1=1 then clock_timestamp()+interval '20 days' end,
       case when ((a.n-1)%3)+1=3 then 'professional' end,
       case when a.n%5=0 then clock_timestamp()-interval '1 day' end
from (select user_id,row_number() over(order by id)::int n from core.users) a
join (select user_id,row_number() over(order by id)::int n from core.users) b on b.n=((a.n+13-1)%50)+1;

insert into core.acknowledgements
  (actor_user_id,target_user_id,category,subcategory,status,idempotency_key,created_at,undone_at)
select a.user_id,b.user_id,
       (array['gratitude_appreciation','love_affection','joy_celebration','encouragement_motivation','care_concern','empathy_support','respect_admiration','friendship_belonging','apology_forgiveness','hope_wellbeing'])[((a.n-1)%10)+1],
       'synthetic_acknowledgement',(array['active','undone','hidden','expired'])[((a.n-1)%4)+1],
       'team-ack-'||a.n,clock_timestamp()-interval '9 days',
       case when ((a.n-1)%4)+1=2 then clock_timestamp()-interval '1 day' end
from (select user_id,row_number() over(order by id)::int n from core.users) a
join (select user_id,row_number() over(order by id)::int n from core.users) b on b.n=((a.n+17-1)%50)+1;

insert into core.conversations(connection_id,status,last_message_at,created_at,closed_at,updated_at)
select id,(array['active','restricted','closed'])[((row_number() over(order by id)-1)%3)+1],
       created_at+interval '3 days',created_at+interval '1 day',
       case when ((row_number() over(order by id)-1)%3)+1=3 then created_at+interval '4 days' end,
       clock_timestamp()-interval '1 day'
from core.connections;

insert into core.conversation_participants
  (conversation_id,user_id,status,joined_at,left_at,removed_by_user_id,created_at)
select c.id,x.user_id,
       case when c.status='closed' then (array['left','removed','banned'])[((c.id+x.side-2)%3)+1] else 'active' end,
       c.created_at,
       case when c.status='closed' then c.created_at+interval '2 days' end,
       case when c.status='closed' and ((c.id+x.side-2)%3)+1 in (2,3) then x.other_user_id end,
       c.created_at
from core.conversations c
join core.connections n on n.id=c.connection_id
cross join lateral (values (n.user_low_id,n.user_high_id,1),(n.user_high_id,n.user_low_id,2)) x(user_id,other_user_id,side);

insert into core.messages
  (conversation_id,conversation_seq,sender_user_id,client_message_id,message_type,content,status,created_at,edited_at,deleted_at,public_id)
select c.id,x.seq,
       case when x.seq=1 then n.user_low_id else n.user_high_id end,
       'team-msg-'||c.id||'-'||x.seq,
       case when ((c.id+x.seq-2)%4)+1=3 or (c.id+x.seq)%5=0 then 'system' else 'text' end,
       case when ((c.id+x.seq-2)%4)+1=3 then '{}'::jsonb
            when (c.id+x.seq)%5=0 then jsonb_build_object('event','synthetic_notice')
            else jsonb_build_object('text','Synthetic message '||c.id||'-'||x.seq) end,
       (array['sent','hidden','removed','quarantined'])[((c.id+x.seq-2)%4)+1],
       c.created_at+x.seq*interval '1 hour',
       case when x.seq=2 and ((c.id+x.seq-2)%4)+1<>3 then c.created_at+interval '3 hours' end,
       case when ((c.id+x.seq-2)%4)+1=3 then c.created_at+interval '4 hours' end,
       extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000003'::uuid,'message-'||c.id||'-'||x.seq)
from core.conversations c join core.connections n on n.id=c.connection_id cross join generate_series(1,2) x(seq)
where c.status='active';

insert into core.message_read_cursors(conversation_id,user_id,last_read_message_id,last_read_at)
select c.id,p.user_id,m.id,m.created_at+interval '1 hour'
from core.conversations c
join core.conversation_participants p on p.conversation_id=c.id
join lateral (select id,created_at from core.messages where conversation_id=c.id order by conversation_seq desc limit 1) m on true;

insert into core.outbox_events
  (aggregate_type,aggregate_id,aggregate_sequence,event_type,payload,created_at,published_at,status,attempt_count,next_attempt_at,last_error_code,event_key,lease_token,dead_lettered_at,lease_owner,lease_expires_at)
select 'user',user_id::text,n,'user.synthetic_reviewed',jsonb_build_object('schema_version',1,'reviewer_number',n),
       clock_timestamp()-interval '8 days',
       case when ((n-1)%4)+1=3 then clock_timestamp()-interval '7 days' end,
       (array['pending','processing','published','dead_letter'])[((n-1)%4)+1],n%4,
       case when ((n-1)%4)+1 in (1,2) then clock_timestamp()+interval '1 hour' end,
       case when ((n-1)%4)+1=4 then 'synthetic_delivery_failure' end,'team-event-'||n,
       case when ((n-1)%4)+1=2 then extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000004'::uuid,'lease-'||n) end,
       case when ((n-1)%4)+1=4 then clock_timestamp()-interval '6 days' end,
       case when ((n-1)%4)+1=2 then 'synthetic-worker' end,
       case when ((n-1)%4)+1=2 then clock_timestamp()+interval '10 minutes' end
from (select user_id,row_number() over(order by id)::int n from core.users) u;

insert into core.notifications
  (recipient_user_id,notification_type,dedupe_key,source_event_id,payload,status,created_at,delivered_at,read_at,updated_at)
select u.user_id,c.category_code,'team-notification-'||u.n,o.id,
       jsonb_build_object('schema_version',1,'synthetic',true),
       (array['queued','delivered','read','suppressed','failed'])[((u.n-1)%5)+1],
       clock_timestamp()-interval '6 days',
       case when ((u.n-1)%5)+1 in (2,3) then clock_timestamp()-interval '5 days' end,
       case when ((u.n-1)%5)+1=3 then clock_timestamp()-interval '4 days' end,
       clock_timestamp()-interval '1 day'
from (select user_id,row_number() over(order by id)::int n from core.users) u
join lateral (select category_code from core.notification_categories order by category_code offset (u.n-1)%38 limit 1) c on true
join core.outbox_events o on o.aggregate_id=u.user_id::text;

insert into core.account_data_jobs
  (user_id,job_type,status,requested_at,started_at,completed_at,export_object_key,export_expires_at,attempt_count,error_code,execute_after,idempotency_key,lease_expires_at,worker_id,lease_token,updated_at)
select user_id,(array['export','deletion'])[((n-1)%2)+1],
       (array['queued','processing','completed','failed','cancelled'])[((n-1)%5)+1],
       clock_timestamp()-interval '12 days',
       case when ((n-1)%5)+1 in (2,3,4) then clock_timestamp()-interval '11 days' end,
       case when ((n-1)%5)+1=3 then clock_timestamp()-interval '10 days' end,
       case when ((n-1)%2)+1=1 then 'synthetic/exports/'||n||'.zip' end,
       case when ((n-1)%2)+1=1 then clock_timestamp()+interval '7 days' end,n%3,
       case when ((n-1)%5)+1=4 then 'synthetic_job_failure' end,
       case when ((n-1)%5)+1=1 then clock_timestamp()+interval '1 hour' end,
       'team-data-job-'||n,
       case when ((n-1)%5)+1=2 then clock_timestamp()+interval '10 minutes' end,
       case when ((n-1)%5)+1=2 then 'synthetic-worker' end,
       case when ((n-1)%5)+1=2 then extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000005'::uuid,'job-lease-'||n) end,
       clock_timestamp()-interval '1 day'
from (select user_id,row_number() over(order by id)::int n from core.users) u;

insert into core.account_data_job_steps
  (job_id,step_code,status,attempt_count,next_attempt_at,lease_token,lease_expires_at,last_error_code,started_at,completed_at,updated_at)
select j.id,'synthetic_step_'||x.k,
       (array['pending','processing','succeeded','retryable_failure','terminal_failure','skipped_by_policy'])[((j.id+x.k-2)%6)+1],
       (j.id+x.k)%4,
       case when ((j.id+x.k-2)%6)+1 in (1,4) then clock_timestamp()+interval '1 hour' end,
       case when ((j.id+x.k-2)%6)+1=2 then extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000006'::uuid,'step-lease-'||j.id||'-'||x.k) end,
       case when ((j.id+x.k-2)%6)+1=2 then clock_timestamp()+interval '10 minutes' end,
       case when ((j.id+x.k-2)%6)+1 in (4,5) then 'synthetic_step_failure' end,
       case when ((j.id+x.k-2)%6)+1 in (2,3,5,6) then clock_timestamp()-interval '2 days' end,
       case when ((j.id+x.k-2)%6)+1 in (3,5,6) then clock_timestamp()-interval '1 day' end,
       clock_timestamp()-interval '1 hour'
from core.account_data_jobs j cross join generate_series(1,2) x(k);

insert into core.media_deletion_jobs
  (profile_media_id,object_key,status,attempt_count,next_attempt_at,lease_expires_at,last_error_code,created_at,completed_at,lease_owner,lease_token,dead_lettered_at,updated_at)
select media_id,object_key,
       (array['pending','processing','completed','retry_wait','dead_letter'])[((row_number() over(order by media_id)-1)%5)+1],
       (row_number() over(order by media_id))::int%4,
       case when ((row_number() over(order by media_id)-1)%5)+1 in (1,4) then clock_timestamp()+interval '1 hour' end,
       case when ((row_number() over(order by media_id)-1)%5)+1=2 then clock_timestamp()+interval '10 minutes' end,
       case when ((row_number() over(order by media_id)-1)%5)+1 in (4,5) then 'synthetic_media_failure' end,
       clock_timestamp()-interval '5 days',
       case when ((row_number() over(order by media_id)-1)%5)+1=3 then clock_timestamp()-interval '1 day' end,
       case when ((row_number() over(order by media_id)-1)%5)+1=2 then 'synthetic-worker' end,
       case when ((row_number() over(order by media_id)-1)%5)+1=2 then extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000007'::uuid,'media-lease-'||row_number() over(order by media_id)) end,
       case when ((row_number() over(order by media_id)-1)%5)+1=5 then clock_timestamp()-interval '1 day' end,
       clock_timestamp()-interval '1 hour'
from core.profile_media;

insert into safety.admin_users(external_identity_id,role,status,mfa_enforced,created_at,last_login_at,deactivated_at)
select extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000008'::uuid,'admin-'||n),
       (array['moderator','support_admin','appeals_admin','security_admin'])[((n-1)%4)+1],
       (array['active','suspended','revoked'])[((n-1)%3)+1],true,
       clock_timestamp()-interval '120 days',clock_timestamp()-interval '2 days',
       case when ((n-1)%3)+1 in (2,3) then clock_timestamp()-interval '1 day' end
from generate_series(1,8) n;

insert into safety.reports
  (reporter_user_id,reported_user_id,category,subcategory,description,status,assigned_admin_id,created_at,resolved_at)
select a.user_id,b.user_id,t.category,t.subcategory,'Synthetic safety report '||a.n,
       (array['new','under_review','action_taken','no_violation','closed'])[((a.n-1)%5)+1],
       case when ((a.n-1)%5)+1=2 then ad.id end,
       clock_timestamp()-interval '25 days',
       case when ((a.n-1)%5)+1 in (3,4,5) then clock_timestamp()-interval '20 days' end
from (select user_id,row_number() over(order by id)::int n from core.users) a
join (select user_id,row_number() over(order by id)::int n from core.users) b on b.n=((a.n+19-1)%50)+1
join lateral (select category,subcategory from safety.report_category_subcategories order by category,subcategory offset (a.n-1)%219 limit 1) t on true
join lateral (select id from safety.admin_users where status='active' order by id offset (a.n-1)%3 limit 1) ad on true;

insert into safety.moderation_actions
  (target_user_id,admin_user_id,report_id,action_type,reason_code,status,created_at,expires_at,reversed_at,reversed_by_admin_id)
select r.reported_user_id,a.id,r.id,x.action_type,'synthetic_policy_reason',
       case when x.action_type<>'permanent_suspension' and r.id%3=0 then 'expired' when r.id%3=1 then 'reversed' else 'active' end,
       clock_timestamp()-interval '18 days',
       case when x.action_type in ('temporary_suspension','feature_access_pause','read_only_restriction','comment_lock') or (x.action_type<>'permanent_suspension' and r.id%3=0) then clock_timestamp()+interval '12 days' end,
       case when r.id%3=1 then clock_timestamp()-interval '5 days' end,
       case when r.id%3=1 then a2.id end
from safety.reports r
join lateral (select id from safety.admin_users where status='active' and role<>'appeals_admin' order by id offset (r.id-1)%2 limit 1) a on true
join lateral (select id from safety.admin_users where status='active' and role<>'appeals_admin' order by id offset r.id%2 limit 1) a2 on true
join lateral (select (array['warning','content_removal','temporary_suspension','account_restriction','permanent_suspension','content_restriction','comment_removal','message_restriction','profile_restriction','feature_restriction','access_revocation','content_flagging','content_visibility_limit','comment_lock','reply_restriction','direct_message_limit','contact_block','forced_password_reset','session_revocation','feature_access_pause','age_gate','final_warning','read_only_restriction','specialist_referral','education_notice'])[((r.id-1)%25)+1] action_type) x on true;

insert into safety.moderation_appeals
  (moderation_action_id,appellant_user_id,status,statement,reviewer_admin_id,decision_reason_code,created_at,decided_at)
select m.id,m.target_user_id,(array['submitted','under_review','approved','rejected'])[((m.id-1)%4)+1],
       'Synthetic appeal statement '||m.id,
       case when ((m.id-1)%4)+1<>1 then a.id end,
       case when ((m.id-1)%4)+1=3 then 'appeal_accepted' when ((m.id-1)%4)+1=4 then 'original_action_upheld' end,
       clock_timestamp()-interval '14 days',
       case when ((m.id-1)%4)+1 in (3,4) then clock_timestamp()-interval '7 days' end
from safety.moderation_actions m
join lateral (select id from safety.admin_users where status='active' and role='appeals_admin' order by id limit 1) a on true;

insert into safety.legal_holds
  (user_id,case_reference,scope,restricted_actions,status,imposed_by_admin_id,reason_code,reason_note,imposed_at,effective_until,released_at,released_by_admin_id,release_reason_code)
select u.user_id,'LH-'||(2030+(u.n%10))||'-'||lpad(u.n::text,4,'0'),
       (array['specified_user_accounts','specified_content_items','specified_communications','access_and_security_logs','transaction_records','moderation_and_appeal_history'])[((u.n-1)%6)+1],
       case ((u.n-1)%6)+1
         when 1 then array['block_account_erasure']::text[]
         when 2 then array['block_content_deletion','preserve_audit_logs']::text[]
         when 3 then array['block_message_deletion']::text[]
         when 4 then array['block_media_deletion']::text[]
         when 5 then array['block_data_job_purge']::text[]
         else array['preserve_moderation_records','freeze_account_status_change']::text[]
       end,
       (array['active','released','expired'])[((u.n-1)%3)+1],a.id,
       case when u.n%10=0 then 'other' else 'legal_request' end,
       case when u.n%10=0 then 'Synthetic legal-review scenario.' end,
       clock_timestamp()-interval '60 days',
       case when ((u.n-1)%3)+1=3 then clock_timestamp()-interval '1 day' else clock_timestamp()+interval '60 days' end,
       case when ((u.n-1)%3)+1=2 then clock_timestamp()-interval '5 days' end,
       case when ((u.n-1)%3)+1=2 then a.id end,
       case when ((u.n-1)%3)+1=2 then 'matter_closed' end
from (select user_id,row_number() over(order by id)::int n from core.users) u
join lateral (select id from safety.admin_users where status='active' and role='security_admin' order by id limit 1) a on true;

insert into safety.report_evidence
  (report_id,evidence_type,source_entity_type,source_entity_id,snapshot_payload,reporting_user_behavior,reported_user_behavior,relation,connection_source,captured_at,retention_until,purged_at,evidence_file_hash,verification_status,reviewed_by_admin_id,reviewed_at,redaction_status,access_level)
select r.id,
       (array['screenshot','screen_recording','post_snapshot','comment_snapshot','chat_snapshot','profile_snapshot','audio_recording','video_recording','document','system_log'])[((r.id-1)%10)+1],
       case when r.id%2=0 then 'message' end,case when r.id%2=0 then 'synthetic-'||r.id end,
       jsonb_build_object('schema_version',1,'synthetic',true),jsonb_build_object('signal','reporter_context'),jsonb_build_object('signal','reported_context'),
       (array['stranger','follower','mutual_friend','collaborator',null])[((r.id-1)%5)+1],
       (array['qr_scan','direct_search','shared_group','algorithmic_suggestion',null])[((r.id-1)%5)+1],
       clock_timestamp()-interval '20 days',clock_timestamp()+interval '365 days',
       case when r.id%11=0 then clock_timestamp()-interval '1 day' end,
       encode(extensions.digest('evidence-'||r.id,'sha256'),'hex'),
       (array['pending','verified','rejected'])[((r.id-1)%3)+1],
       case when ((r.id-1)%3)+1 in (2,3) then a.id end,
       case when ((r.id-1)%3)+1 in (2,3) then clock_timestamp()-interval '10 days' end,
       (array['not_redacted','partially_redacted','fully_redacted'])[((r.id-1)%3)+1],
       (array['moderators','security_admins','legal_only'])[((r.id-1)%3)+1]
from safety.reports r
join lateral (select id from safety.admin_users where status='active' order by id offset (r.id-1)%3 limit 1) a on true;

insert into analytics.product_events
  (event_type,actor_pseudonym_id,aggregate_type,aggregate_id,event_time,ingested_at,properties,source_outbox_event_id,event_idempotency_key,event_source,session_id)
select (array['profile_viewed','connection_requested','message_sent','notification_opened','report_submitted'])[((u.n-1)%5)+1],
       p.pseudonym_id,'user',u.user_id::text,clock_timestamp()-interval '3 days',clock_timestamp()-interval '2 days',
       jsonb_build_object('schema_version',1,'synthetic',true),o.id,
       extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000009'::uuid,'event-'||u.n),
       (array['web','android','ios','api','system'])[((u.n-1)%5)+1],
       extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000010'::uuid,'session-'||u.n)
from (select user_id,row_number() over(order by id)::int n from core.users) u
join core.user_pseudonyms p on p.user_id=u.user_id
join core.outbox_events o on o.aggregate_id=u.user_id::text;

insert into analytics.discovery_impressions
  (request_id,viewer_pseudonym_id,candidate_pseudonym_id,position,reason_codes,mode,content_category,subcategory,decay_factor,impression_week,created_at)
select extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000011'::uuid,'discovery-'||a.n),a.pseudonym_id,b.pseudonym_id,1,
       array['shared_interest','same_city'],(array['default','explore','professional'])[((a.n-1)%3)+1],
       case when a.n%2=0 then 'interest' end,case when a.n%2=0 then 'synthetic' end,
       round((1.0-(a.n%10)*0.05)::numeric,3),'2026-W45',clock_timestamp()-interval '1 day'
from (select pseudonym_id,row_number() over(order by user_id)::int n from core.user_pseudonyms) a
join (select pseudonym_id,row_number() over(order by user_id)::int n from core.user_pseudonyms) b on b.n=(a.n%50)+1;

insert into audit.audit_product_event
  (event_timestamp,actor_type,user_id,admin_user_id,action_type,event_category,target_user_id,request_id,event_status,failure_reason,event_source,ip_hmac,device_id,authentication_method,data_modified,previous_value,new_value,metadata)
select clock_timestamp()-interval '1 day',x.actor_type,
       case when x.actor_type='user' then u.user_id end,
       case when x.actor_type in ('admin','support') then a.id end,
       (array['profile_updated','connection_created','message_reviewed','notification_delivered','safety_actioned'])[((u.n-1)%5)+1],
       (array['authentication','identity','profile','connection','messaging','notification','safety','privacy','security','data_job','system'])[((u.n-1)%11)+1],
       t.user_id,'team-request-'||u.n,
       case when u.n%5=0 then 'failure' else 'success' end,
       case when u.n%5=0 then 'synthetic_validation_failure' end,
       (array['web','android','ios','api','worker','admin_console','system'])[((u.n-1)%7)+1],
       extensions.digest('ip-'||u.n,'sha256'),'synthetic-device-'||u.n,
       (array['email_otp','phone_otp','google','apple','staff_sso','service'])[((u.n-1)%6)+1],
       u.n%2=0,
       case when u.n%2=0 then jsonb_build_object('state','before') end,
       case when u.n%2=0 then jsonb_build_object('state','after') end,
       jsonb_build_object('schema_version',1,'synthetic',true)
from (select user_id,row_number() over(order by id)::int n from core.users) u
join (select user_id,row_number() over(order by id)::int n from core.users) t on t.n=(u.n%50)+1
join lateral (select (array['user','admin','support','system'])[((u.n-1)%4)+1] actor_type) x on true
join lateral (select id from safety.admin_users where status='active' order by id offset (u.n-1)%3 limit 1) a on true;
`;

const validationSql = String.raw`
do $$
declare
  r record;
  v_rows bigint;
begin
  if (select count(*) from core.users) <> 50
     or (select min(id) from core.users) <> 1
     or (select max(id) from core.users) <> 50 then
    raise exception 'User fixture must contain IDs 1 through 50';
  end if;

  for r in
    select split_part(name,'.',1) schemaname,split_part(name,'.',2) tablename
    from unnest(array[${tables.map((name) => `'${name}'`).join(',')}]) name
    order by name
  loop
    execute format('select count(*) from %I.%I',r.schemaname,r.tablename) into v_rows;
    if v_rows=0 then
      raise exception 'Full-team fixture left %.% empty',r.schemaname,r.tablename;
    end if;
  end loop;

  if (select count(*) from core.interests) <> 962
     or (select count(*) from core.prompt_catalogue) <> 100
     or (select count(*) from core.connection_intents) <> 110
     or (select count(*) from safety.report_category_subcategories) <> 219
     or (select count(*) from core.notification_categories) <> 38
     or (select count(*) from core.connection_closed_reasons) <> 41 then
    raise exception 'Workbook catalog count mismatch';
  end if;

  if (select count(*) from core.profiles) <> 50
     or (select count(*) from core.profile_media) <> 50
     or (select count(*) from core.notification_preferences) <> 50
     or (select count(*) from core.user_languages) <> 50
     or (select count(*) from core.user_pseudonyms) <> 50
     or (select count(*) from core.device_tokens) <> 50 then
    raise exception 'Per-user profile or preference count mismatch';
  end if;

  if (select count(*) from core.user_interests) <> 150
     or (select count(*) from core.profile_prompts) <> 100
     or (select count(*) from core.connection_requests) <> 50
     or (select count(*) from core.connections) <> 25
     or (select count(*) from core.conversations) <> 25
     or (select count(*) from core.conversation_participants) <> 50
     or (select count(*) from core.messages) <> 18 then
    raise exception 'Profile, connection, or messaging count mismatch';
  end if;

  if (select count(*) from core.outbox_events) <> 50
     or (select count(*) from core.notifications) <> 50
     or (select count(*) from core.account_data_jobs) <> 50
     or (select count(*) from core.account_data_job_steps) <> 100
     or (select count(*) from core.media_deletion_jobs) <> 50 then
    raise exception 'Notification or background-job count mismatch';
  end if;

  if (select count(*) from safety.reports) <> 50
     or (select count(*) from safety.moderation_actions) <> 50
     or (select count(*) from safety.moderation_appeals) <> 50
     or (select count(*) from safety.legal_holds) <> 50
     or (select count(*) from safety.report_evidence) <> 50
     or (select count(*) from analytics.product_events) <> 50
     or (select count(*) from analytics.discovery_impressions) <> 50
     or (select count(*) from core.auth_sessions) <> 50
     or (select count(*) from core.policy_versions) <> 6
     or (select count(*) from audit.audit_product_event) < 50 then
    raise exception 'Safety, analytics, or audit count mismatch';
  end if;

  if (select count(distinct status) from core.connection_requests) <> 6
     or (select count(distinct status) from core.relations) <> 4
     or (select count(distinct status) from core.notifications) <> 5
     or (select count(distinct status) from core.account_data_jobs) <> 5
     or (select count(distinct status) from core.account_data_job_steps) <> 6
     or (select count(distinct status) from core.media_deletion_jobs) <> 5 then
    raise exception 'Core workflow status coverage mismatch';
  end if;

  if (select count(distinct status) from safety.reports) <> 5
     or (select count(distinct action_type) from safety.moderation_actions) <> 25
     or (select count(distinct status) from safety.moderation_actions) <> 3
     or (select count(distinct status) from safety.moderation_appeals) <> 4
     or (select count(distinct status) from safety.legal_holds) <> 3
     or (select count(distinct evidence_type) from safety.report_evidence) <> 10
     or (select count(distinct verification_status) from safety.report_evidence) <> 3 then
    raise exception 'Safety workflow value coverage mismatch';
  end if;
end $$;
`;

const rollbackOnly = process.argv.includes('--rollback');
const sql = [
  '-- Generated by scripts/generate-full-team-review.mjs. All personal data is fictional.',
  '-- Rebuilds the complete 50-user team review dataset and all workbook catalogs.',
  'begin;',
  `truncate table\n  ${tables.join(',\n  ')}\nrestart identity cascade;`,
  body('supabase/seed.sql'),
  String.raw`insert into core.policy_versions(consent_type,policy_version,content_sha256,document_uri,published_at,effective_at,retired_at)
select t,v,extensions.digest('synthetic-review-policy:'||t||':'||v,'sha256'),'https://policies.example.test/'||t||'/'||v,
  published_at,effective_at,retired_at
from (values
  ('terms_of_service','v1.0',timestamptz '2026-01-01 00:00:00+00',timestamptz '2026-01-15 00:00:00+00',timestamptz '2026-11-09 14:27:40+00'),
  ('terms_of_service','v1.1',timestamptz '2026-11-09 14:00:00+00',timestamptz '2026-11-09 14:27:40+00',null::timestamptz),
  ('privacy_notice','v1.0',timestamptz '2026-01-01 00:00:00+00',timestamptz '2026-01-15 00:00:00+00',timestamptz '2026-11-09 14:27:40+00'),
  ('privacy_notice','v1.1',timestamptz '2026-11-09 14:00:00+00',timestamptz '2026-11-09 14:27:40+00',null::timestamptz),
  ('kyc_verification','v1.0',timestamptz '2026-01-01 00:00:00+00',timestamptz '2026-01-15 00:00:00+00',null::timestamptz),
  ('marketing','v1.0',timestamptz '2026-01-01 00:00:00+00',timestamptz '2026-01-15 00:00:00+00',null::timestamptz)
) p(t,v,published_at,effective_at,retired_at);`,
  body('supabase/synthetic_review_data.sql'),
  moduleSql.trim(),
  validationSql.trim(),
  rollbackOnly ? 'rollback;' : 'commit;',
  ''
].join('\n\n');

const output = rollbackOnly
  ? path.join(os.tmpdir(), 'full-team-review-rollback.sql')
  : path.join(root, 'supabase', 'full_team_review_data.sql');
fs.writeFileSync(output, sql, 'utf8');
console.log(JSON.stringify({ users: 50, applicationTables: tables.length, output, rollbackOnly }, null, 2));
