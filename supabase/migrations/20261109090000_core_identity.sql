create extension if not exists pgcrypto with schema extensions;

create schema if not exists core;
create schema if not exists safety;
create schema if not exists analytics;
create schema if not exists audit;
create schema if not exists review;

comment on schema core is 'Application identity, profiles, social graph, messaging, notifications, and jobs.';
comment on schema safety is 'Safety reporting, moderation, appeals, evidence, and legal holds.';
comment on schema analytics is 'Pseudonymous product and discovery telemetry.';
comment on schema audit is 'Append-only security and operational audit events.';
comment on schema review is 'Read-only metadata and synthetic-data review surfaces.';

create or replace function core.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create table core.users (
  id bigint generated always as identity primary key,
  user_id uuid not null default extensions.gen_random_uuid(),
  account_status text not null default 'limited',
  verification_status text not null default 'pending',
  timezone text not null default 'Asia/Kolkata',
  age_eligibility_status text not null default 'unknown',
  age_verified_at timestamptz,
  date_of_birth date,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  gender text not null default 'prefer_not_to_say',
  constraint users_user_id_uq unique (user_id),
  constraint users_account_status_ck check (account_status in ('limited','active','suspended','deactivated','deletion_pending','deleted')),
  constraint users_verification_status_ck check (verification_status in ('pending','verified','rejected','review_required')),
  constraint users_age_status_ck check (age_eligibility_status in ('unknown','eligible','ineligible','review_required')),
  constraint users_gender_ck check (gender in ('male','female','transgender_man','transgender_woman','non_binary','genderqueer','genderfluid','agender','other','prefer_not_to_say')),
  constraint users_dob_range_ck check (date_of_birth is null or date_of_birth >= date '1900-01-01'),
  constraint users_age_consistency_ck check (
    (age_eligibility_status = 'unknown' and age_verified_at is null)
    or (age_eligibility_status <> 'unknown')
  ),
  constraint users_deleted_ck check ((account_status = 'deleted') = (deleted_at is not null)),
  constraint users_deleted_time_ck check (deleted_at is null or deleted_at >= created_at),
  constraint users_updated_time_ck check (updated_at >= created_at)
);

create table core.auth_identities (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  provider text not null,
  provider_subject text not null,
  status text not null default 'active',
  linked_at timestamptz not null default clock_timestamp(),
  last_login_at timestamptz,
  unlinked_at timestamptz,
  unlink_reason text,
  updated_at timestamptz not null default clock_timestamp(),
  constraint auth_identities_provider_ck check (provider in ('email_otp','phone_otp','google','apple')),
  constraint auth_identities_subject_nonblank_ck check (btrim(provider_subject) <> ''),
  constraint auth_identities_provider_subject_uq unique (provider, provider_subject),
  constraint auth_identities_status_ck check (status in ('active','unlinked','revoked')),
  constraint auth_identities_unlink_reason_ck check (unlink_reason is null or unlink_reason in ('user_request','security','admin_action','provider_revoked')),
  constraint auth_identities_unlink_consistency_ck check (
    (status = 'active' and unlinked_at is null and unlink_reason is null)
    or (status in ('unlinked','revoked') and unlinked_at is not null and unlink_reason is not null)
  ),
  constraint auth_identities_times_ck check (
    (last_login_at is null or last_login_at >= linked_at)
    and (unlinked_at is null or unlinked_at >= linked_at)
  )
);

create unique index auth_identities_one_active_provider_uq
  on core.auth_identities(user_id, provider) where status = 'active';
create index auth_identities_user_ix on core.auth_identities(user_id);

create table core.user_contacts (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  email text not null,
  phone_number text not null,
  contact_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint user_contacts_user_uq unique (user_id),
  constraint user_contacts_email_uq unique (email),
  constraint user_contacts_phone_uq unique (phone_number),
  constraint user_contacts_email_normalized_ck check (email = lower(btrim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  constraint user_contacts_phone_ck check (phone_number ~ '^\+[1-9][0-9]{7,14}$'),
  constraint user_contacts_version_ck check (contact_version >= 1)
);

create table core.user_verifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  email_status text not null default 'not_started',
  email_verified_at timestamptz,
  phone_status text not null default 'not_started',
  phone_verified_at timestamptz,
  aadhaar_status text not null default 'not_started',
  aadhaar_failure_reason text,
  aadhaar_attempt_count smallint not null default 0,
  aadhaar_verified_at timestamptz,
  aadhaar_masked text,
  aadhaar_provider text,
  aadhaar_provider_ref text,
  age_eligible boolean,
  pan_status text not null default 'not_started',
  pan_failure_reason text,
  pan_attempt_count smallint not null default 0,
  pan_verified_at timestamptz,
  pan_masked text,
  pan_provider text,
  pan_provider_ref text,
  aadhaar_hash bytea,
  pan_hash bytea,
  hash_key_version smallint not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint user_verifications_user_uq unique (user_id),
  constraint uv_email_status_ck check (email_status in ('not_started','pending','verified','failed')),
  constraint uv_phone_status_ck check (phone_status in ('not_started','pending','verified','failed')),
  constraint uv_aadhaar_status_ck check (aadhaar_status in ('not_started','pending','verified','failed','review_required')),
  constraint uv_pan_status_ck check (pan_status in ('not_started','pending','verified','failed','review_required')),
  constraint uv_email_result_ck check ((email_status = 'verified') = (email_verified_at is not null)),
  constraint uv_phone_result_ck check ((phone_status = 'verified') = (phone_verified_at is not null)),
  constraint uv_aadhaar_reason_ck check (aadhaar_failure_reason is null or aadhaar_failure_reason in (
    'wrong_otp','otp_attempts_exceeded','otp_limit_exceeded','otp_expired','mobile_not_linked','invalid_aadhaar_number',
    'aadhaar_not_found','aadhaar_inactive','aadhaar_locked','name_mismatch','dob_mismatch','already_used',
    'user_cancelled','consent_denied','provider_error','too_many_attempts')),
  constraint uv_pan_reason_ck check (pan_failure_reason is null or pan_failure_reason in (
    'invalid_pan_format','pan_not_found','pan_inactive','pan_not_individual','pan_not_linked_to_aadhaar',
    'name_mismatch','dob_mismatch','aadhaar_pan_name_mismatch','already_used','user_cancelled','consent_denied',
    'provider_error','too_many_attempts')),
  constraint uv_aadhaar_reason_rule_ck check (
    (aadhaar_status in ('failed','review_required')) = (aadhaar_failure_reason is not null)
    and (aadhaar_status <> 'review_required' or aadhaar_failure_reason in ('name_mismatch','dob_mismatch'))
    and (aadhaar_failure_reason <> 'too_many_attempts' or aadhaar_attempt_count = 3)),
  constraint uv_pan_reason_rule_ck check (
    (pan_status in ('failed','review_required')) = (pan_failure_reason is not null)
    and (pan_status <> 'review_required' or pan_failure_reason in ('name_mismatch','dob_mismatch','aadhaar_pan_name_mismatch'))
    and (pan_failure_reason <> 'too_many_attempts' or pan_attempt_count = 3)),
  constraint uv_aadhaar_attempts_ck check (aadhaar_attempt_count between 0 and 3),
  constraint uv_pan_attempts_ck check (pan_attempt_count between 0 and 3),
  constraint uv_aadhaar_result_ck check (
    (aadhaar_status = 'verified') = (aadhaar_verified_at is not null)
    and (aadhaar_status = 'verified') = (aadhaar_masked is not null)
    and (aadhaar_status = 'verified') = (age_eligible is not null)),
  constraint uv_pan_result_ck check ((pan_status = 'verified') = (pan_verified_at is not null) and (pan_status = 'verified') = (pan_masked is not null)),
  constraint uv_aadhaar_masked_ck check (aadhaar_masked is null or aadhaar_masked ~ '^X{8}[0-9]{4}$'),
  constraint uv_pan_masked_ck check (pan_masked is null or pan_masked ~ '^XXXPX[0-9]{4}[A-Z]$'),
  constraint uv_aadhaar_provider_ck check (aadhaar_provider is null or aadhaar_provider in ('digilocker','kyc_vendor')),
  constraint uv_pan_provider_ck check (pan_provider is null or pan_provider in ('digilocker','protean','kyc_vendor')),
  constraint uv_aadhaar_started_ck check ((aadhaar_status = 'not_started') = (aadhaar_provider is null and aadhaar_provider_ref is null)),
  constraint uv_pan_started_ck check ((pan_status = 'not_started') = (pan_provider is null and pan_provider_ref is null)),
  constraint uv_pan_after_aadhaar_ck check (pan_status <> 'verified' or aadhaar_status = 'verified'),
  constraint uv_kyc_times_ck check (pan_verified_at is null or (aadhaar_verified_at is not null and pan_verified_at >= aadhaar_verified_at)),
  constraint uv_hash_len_ck check (
    (aadhaar_hash is null or octet_length(aadhaar_hash) = 32)
    and (pan_hash is null or octet_length(pan_hash) = 32)),
  constraint uv_hash_version_ck check (hash_key_version >= 1)
);

create unique index uv_aadhaar_provider_ref_uq on core.user_verifications(aadhaar_provider, aadhaar_provider_ref)
  where aadhaar_provider_ref is not null;
create unique index uv_pan_provider_ref_uq on core.user_verifications(pan_provider, pan_provider_ref)
  where pan_provider_ref is not null;
create unique index uv_aadhaar_hash_uq on core.user_verifications(aadhaar_hash) where aadhaar_hash is not null;
create unique index uv_pan_hash_uq on core.user_verifications(pan_hash) where pan_hash is not null;

create table core.user_otp_challenges (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  channel text not null,
  purpose text not null,
  destination_hash bytea,
  contact_version integer not null,
  otp_hmac bytea not null,
  status text not null default 'pending',
  attempt_count smallint not null default 0,
  sent_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  verified_at timestamptz,
  last_sent_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint uoc_channel_ck check (channel in ('email','phone')),
  constraint uoc_purpose_ck check (purpose in ('signup','login','contact_change','account_recovery')),
  constraint uoc_hash_len_ck check (octet_length(otp_hmac) = 32 and (destination_hash is null or octet_length(destination_hash) = 32)),
  constraint uoc_status_ck check (status in ('pending','verified','expired','locked','cancelled')),
  constraint uoc_attempts_ck check (attempt_count between 0 and 5),
  constraint uoc_locked_ck check (status <> 'locked' or attempt_count = 5),
  constraint uoc_times_ck check (
    last_sent_at >= sent_at and expires_at > last_sent_at
    and ((status = 'verified') = (verified_at is not null))
    and (verified_at is null or (verified_at >= sent_at and verified_at <= expires_at))),
  constraint uoc_contact_version_ck check (contact_version >= 1)
);

create unique index uoc_one_pending_uq on core.user_otp_challenges(user_id, channel, purpose) where status = 'pending';
create index uoc_user_created_ix on core.user_otp_challenges(user_id, created_at desc);
create index uoc_cleanup_ix on core.user_otp_challenges(created_at) where status <> 'pending';

create table core.user_consents (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  consent_type text not null,
  policy_version text not null,
  decision text not null,
  source text not null,
  captured_at timestamptz not null default clock_timestamp(),
  constraint uc_type_ck check (consent_type in ('terms_of_service','privacy_notice','kyc_verification','marketing')),
  constraint uc_version_ck check (policy_version ~ '^v[0-9]{1,3}\.[0-9]{1,3}$'),
  constraint uc_decision_ck check (decision in ('granted','declined','withdrawn')),
  constraint uc_source_ck check (source in ('signup_flow','settings','admin_console','api')),
  constraint user_consents_uq unique (user_id, consent_type, policy_version, captured_at)
);

create index user_consents_latest_ix on core.user_consents(user_id, consent_type, captured_at desc, id desc);

create table core.user_status_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  from_status text,
  to_status text not null,
  actor_type text not null,
  actor_id text,
  reason_code text not null,
  effective_until timestamptz,
  request_id text,
  created_at timestamptz not null default clock_timestamp(),
  constraint ush_from_status_ck check (from_status is null or from_status in ('limited','active','suspended','deactivated','deletion_pending','deleted')),
  constraint ush_to_status_ck check (to_status in ('limited','active','suspended','deactivated','deletion_pending','deleted')),
  constraint ush_actor_type_ck check (actor_type in ('user','admin','support','system')),
  constraint ush_actor_id_ck check (
    (actor_type = 'system' and actor_id is null)
    or (actor_type <> 'system' and actor_id is not null and actor_id ~ '^[A-Za-z0-9:_-]{1,100}$')),
  constraint ush_reason_ck check (reason_code in (
    'signup','verification_completed','verification_reset','policy_violation','fraud_suspected','report_upheld',
    'age_ineligible','appeal_accepted','suspension_expired','user_request','user_returned','deletion_cancelled',
    'grace_period_ended','inactivity','legal_request')),
  constraint ush_effective_until_ck check (
    (effective_until is null or to_status in ('suspended','deletion_pending'))
    and (to_status <> 'deletion_pending' or effective_until is not null)),
  constraint ush_request_id_ck check (request_id is null or request_id ~ '^[A-Za-z0-9:._-]{1,100}$')
);

create index user_status_history_user_created_ix on core.user_status_history(user_id, created_at desc, id desc);

comment on column core.users.user_id is 'Stable random business-user identifier used by every application FK.';
comment on column core.users.id is 'Internal numeric key; not used by application child tables.';
comment on column core.user_verifications.aadhaar_hash is 'Optional synthetic/pilot duplicate-detection HMAC; never stores a full Aadhaar number.';
comment on column core.user_otp_challenges.otp_hmac is 'Backend-produced HMAC-SHA-256; plaintext OTPs are never stored.';
