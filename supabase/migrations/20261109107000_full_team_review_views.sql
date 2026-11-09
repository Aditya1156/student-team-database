create or replace view review.team_module_counts
as
select 'identity'::text module, 'users'::text relation, count(*)::bigint row_count from core.users
union all select 'identity','auth_identities',count(*) from core.auth_identities
union all select 'identity','user_contacts',count(*) from core.user_contacts
union all select 'identity','user_verifications',count(*) from core.user_verifications
union all select 'identity','user_otp_challenges',count(*) from core.user_otp_challenges
union all select 'identity','user_consents',count(*) from core.user_consents
union all select 'identity','user_status_history',count(*) from core.user_status_history
union all select 'profile','profiles',count(*) from core.profiles
union all select 'profile','profile_media',count(*) from core.profile_media
union all select 'profile','user_interests',count(*) from core.user_interests
union all select 'profile','profile_prompts',count(*) from core.profile_prompts
union all select 'profile','notification_preferences',count(*) from core.notification_preferences
union all select 'profile','user_languages',count(*) from core.user_languages
union all select 'social','connection_requests',count(*) from core.connection_requests
union all select 'social','connections',count(*) from core.connections
union all select 'social','blocks',count(*) from core.blocks
union all select 'social','relations',count(*) from core.relations
union all select 'social','discovery_dismissals',count(*) from core.discovery_dismissals
union all select 'social','acknowledgements',count(*) from core.acknowledgements
union all select 'social','user_pseudonyms',count(*) from core.user_pseudonyms
union all select 'messaging','conversations',count(*) from core.conversations
union all select 'messaging','conversation_participants',count(*) from core.conversation_participants
union all select 'messaging','messages',count(*) from core.messages
union all select 'messaging','message_read_cursors',count(*) from core.message_read_cursors
union all select 'notifications','notification_category_preferences',count(*) from core.notification_category_preferences
union all select 'notifications','device_tokens',count(*) from core.device_tokens
union all select 'notifications','outbox_events',count(*) from core.outbox_events
union all select 'notifications','notifications',count(*) from core.notifications
union all select 'data_jobs','account_data_jobs',count(*) from core.account_data_jobs
union all select 'data_jobs','account_data_job_steps',count(*) from core.account_data_job_steps
union all select 'data_jobs','media_deletion_jobs',count(*) from core.media_deletion_jobs
union all select 'safety','admin_users',count(*) from safety.admin_users
union all select 'safety','reports',count(*) from safety.reports
union all select 'safety','moderation_actions',count(*) from safety.moderation_actions
union all select 'safety','moderation_appeals',count(*) from safety.moderation_appeals
union all select 'safety','legal_holds',count(*) from safety.legal_holds
union all select 'safety','report_evidence',count(*) from safety.report_evidence
union all select 'analytics','product_events',count(*) from analytics.product_events
union all select 'analytics','discovery_impressions',count(*) from analytics.discovery_impressions
union all select 'audit','audit_product_event',count(*) from audit.audit_product_event;

create or replace view review.synthetic_user_overview
as
select
  u.user_id,
  u.account_status,
  u.verification_status,
  u.age_eligibility_status,
  p.handle,
  p.visibility_status,
  p.profile_completeness,
  (select count(*) from core.user_interests ui where ui.user_id=u.user_id) as interest_count,
  u.id as reviewer_number,
  case
    when u.account_status='active' and u.verification_status='verified' then 'verified_active'
    when v.aadhaar_status='review_required' or v.pan_status='review_required' then 'manual_review'
    when v.aadhaar_status='pending' or v.pan_status='pending' then 'kyc_pending'
    when v.email_status='failed' or v.phone_status='failed' then 'contact_failed'
    when v.email_status='verified' and v.phone_status='verified' then 'contact_verified'
    else 'not_started'
  end as review_scenario,
  (select count(*) from core.profile_prompts pp where pp.user_id=u.user_id) as prompt_count,
  (select count(*) from core.connection_requests cr where cr.sender_user_id=u.user_id) as requests_sent,
  (select count(*) from core.connection_requests cr where cr.recipient_user_id=u.user_id) as requests_received,
  (select count(*) from core.connections c where u.user_id in (c.user_low_id,c.user_high_id)) as connection_count,
  (select count(*) from core.messages m where m.sender_user_id=u.user_id) as messages_sent,
  (select count(*) from core.notifications n where n.recipient_user_id=u.user_id) as notification_count,
  (select count(*) from safety.reports r where r.reporter_user_id=u.user_id) as reports_submitted,
  (select count(*) from safety.reports r where r.reported_user_id=u.user_id) as reports_received,
  (select count(*) from core.account_data_jobs j where j.user_id=u.user_id) as data_job_count
from core.users u
left join core.profiles p using (user_id)
join core.user_verifications v using (user_id);

grant select on review.team_module_counts,review.synthetic_user_overview to student_database_reviewer;

comment on view review.team_module_counts is 'Exact synthetic row counts for teammate review, excluding large reference catalogs.';
comment on view review.synthetic_user_overview is 'Sanitized per-user review surface spanning identity, profile, social, messaging, notification, safety, and data-job modules.';
