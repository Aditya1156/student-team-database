-- Aditya: registration, authentication, and account-lifecycle verification
-- Run each query separately in the Supabase SQL Editor.
-- These are read-only queries. They do not change or delete any data.
-- Expected for every query: result = PASS and invalid_rows = 0.

-- ---------------------------------------------------------------------------
-- Question 1: Can a user register using every supported authentication method?
-- Verifies that all four supported providers are represented by an identity.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
with supported(provider) as (
  values ('email_otp'), ('phone_otp'), ('google'), ('apple')
)
select
  '01_supported_registration_methods' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from supported s
where not exists (
  select 1
  from core.auth_identities ai
  where ai.provider = s.provider
);

-- ---------------------------------------------------------------------------
-- Question 2: What happens if the same email or phone is used with another
-- authentication provider?
-- A user may link providers, but an email or phone cannot belong to two users.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
with duplicate_contacts as (
  select email as contact_value
  from core.user_contacts
  group by email
  having count(distinct user_id) > 1

  union all

  select phone_number as contact_value
  from core.user_contacts
  group by phone_number
  having count(distinct user_id) > 1
)
select
  '02_contact_cannot_belong_to_two_users' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from duplicate_contacts;

-- ---------------------------------------------------------------------------
-- Question 2 continued: one account can safely have multiple providers, but
-- it cannot have two active identities for the same provider.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
with duplicate_active_providers as (
  select user_id, provider
  from core.auth_identities
  where status = 'active'
  group by user_id, provider
  having count(*) > 1
)
select
  '03_one_active_identity_per_provider' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from duplicate_active_providers;

-- ---------------------------------------------------------------------------
-- Question 3: Can users change email or phone without losing account history?
-- Contact changes retain user_id and increase contact_version. This detects an
-- invalid version or a contact row whose user account no longer exists.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
select
  '04_contact_change_preserves_user' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.user_contacts c
left join core.users u on u.user_id = c.user_id
where u.user_id is null
   or c.contact_version < 1;

-- ---------------------------------------------------------------------------
-- Question 4: Are OTP expiry and successful-verification timestamps valid?
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
select
  '05_otp_expiry_and_verification_times' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.user_otp_challenges o
where o.expires_at <= o.last_sent_at
   or (o.status = 'verified' and o.verified_at is null)
   or (o.status <> 'verified' and o.verified_at is not null)
   or (o.verified_at is not null and
       (o.verified_at < o.sent_at or o.verified_at > o.expires_at));

-- ---------------------------------------------------------------------------
-- Question 4 continued: Are resend limits, incorrect attempts, locking, and
-- recovery purposes represented consistently?
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
select
  '06_otp_attempt_resend_and_recovery_rules' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.user_otp_challenges o
where o.attempt_count not between 0 and 5
   or o.resend_count not between 0 and 5
   or (o.status = 'locked' and
       (o.attempt_count <> 5 or o.locked_at is null))
   or (o.status <> 'locked' and o.locked_at is not null)
   or (o.purpose = 'account_recovery' and o.recovery_request_id is null);

-- ---------------------------------------------------------------------------
-- Question 5: Can sessions and refresh tokens be revoked securely?
-- Checks token hashes, session state, token version, and revocation details.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
select
  '07_session_and_refresh_token_rules' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.auth_sessions s
where octet_length(s.refresh_token_hash) <> 32
   or s.refresh_token_version < 1
   or (s.status = 'active' and
       (s.revoked_at is not null or s.revocation_reason is not null))
   or (s.status <> 'active' and
       (s.revoked_at is null or s.revocation_reason is null));

-- ---------------------------------------------------------------------------
-- Question 6: What happens when an account is suspended, deactivated, pending
-- deletion, or deleted?
-- Such accounts must not retain an active session.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
select
  '08_blocked_accounts_have_no_active_sessions' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.auth_sessions s
join core.users u using (user_id)
where u.account_status in (
        'suspended', 'deactivated', 'deletion_pending', 'deleted'
      )
  and s.status = 'active';

-- ---------------------------------------------------------------------------
-- Question 7: Is every account status change recorded with actor, reason, and
-- timestamp?
-- Checks required audit fields on every lifecycle-history row.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
select
  '09_status_history_has_full_audit_details' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.user_status_history h
where h.to_status is null
   or h.actor_type is null
   or (h.actor_type <> 'system' and h.actor_id is null)
   or h.reason_code is null
   or h.created_at is null;

-- ---------------------------------------------------------------------------
-- Question 7 continued: Does the latest history row match the user's current
-- account status?
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
with latest_history as (
  select distinct on (user_id)
    user_id, to_status
  from core.user_status_history
  order by user_id, created_at desc, id desc
)
select
  '10_latest_history_matches_account' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.users u
left join latest_history h using (user_id)
where h.user_id is null
   or h.to_status <> u.account_status;

-- ---------------------------------------------------------------------------
-- Question 8: Can consent be withdrawn?
-- A withdrawal must be the current decision only when its latest event says so;
-- the earlier consent events remain in the append-only history.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
with calculated_current as (
  select distinct on (user_id, consent_type)
    id, user_id, consent_type, policy_version, decision
  from core.user_consents
  order by user_id, consent_type, captured_at desc, id desc
)
select
  '11_current_consent_is_latest_event' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from calculated_current expected
full join core.user_consents_current actual
  on actual.id = expected.id
where expected.id is null
   or actual.id is null
   or actual.decision <> expected.decision
   or actual.policy_version <> expected.policy_version;

-- ---------------------------------------------------------------------------
-- Question 8 continued: Can the exact accepted policy version be retrieved?
-- Every consent event must point to an immutable policy version with its hash,
-- document URI, publication time, and effective time.
-- Expected output: PASS | 0
-- ---------------------------------------------------------------------------
select
  '12_consent_has_exact_policy_version' as test_name,
  count(*) as invalid_rows,
  case when count(*) = 0 then 'PASS' else 'FAIL' end as result
from core.user_consents c
left join core.policy_versions p
  on p.consent_type = c.consent_type
 and p.policy_version = c.policy_version
where p.policy_version is null
   or octet_length(p.content_sha256) <> 32
   or p.document_uri is null
   or p.published_at is null
   or p.effective_at is null;
