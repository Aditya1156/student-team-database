create table safety.admin_users (
  id bigint generated always as identity primary key,
  external_identity_id uuid not null,
  role varchar(30) not null default 'moderator',
  status varchar(20) not null default 'active',
  mfa_enforced boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  last_login_at timestamptz,
  deactivated_at timestamptz,
  constraint admin_users_external_identity_uq unique (external_identity_id),
  constraint admin_users_role_ck check (role in ('moderator','support_admin','appeals_admin','security_admin')),
  constraint admin_users_status_ck check (status in ('active','suspended','revoked')),
  constraint admin_users_mfa_ck check (status <> 'active' or mfa_enforced),
  constraint admin_users_deactivated_ck check (
    (status = 'active' and deactivated_at is null)
    or (status in ('suspended','revoked') and deactivated_at is not null)),
  constraint admin_users_times_ck check (
    (last_login_at is null or last_login_at >= created_at)
    and (deactivated_at is null or deactivated_at >= created_at))
);
create index admin_users_role_status_ix on safety.admin_users(role, status);

create table safety.report_category_subcategories (
  category varchar(50) not null,
  subcategory varchar(60) not null,
  display_label text,
  status text not null default 'active',
  primary key (category, subcategory),
  constraint report_category_subcategories_code_ck check (
    category ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
    and subcategory ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint report_category_subcategories_status_ck check (status in ('active','deprecated'))
);

create table safety.reports (
  id bigint generated always as identity primary key,
  reporter_user_id uuid not null references core.users(user_id) on delete restrict,
  reported_user_id uuid not null references core.users(user_id) on delete restrict,
  category varchar(50) not null,
  subcategory varchar(60),
  description text,
  status varchar(20) not null default 'new',
  assigned_admin_id bigint references safety.admin_users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  constraint reports_self_report_ck check (reporter_user_id <> reported_user_id),
  constraint reports_category_ck check (category in (
    'harassment','spam','impersonation','hate_speech','fraud_or_scam','misinformation','violence_or_threats',
    'sexual_content_or_exploitation','privacy_violation','child_safety','graphic_or_disturbing_content',
    'financial_exploitation','account_compromise','unauthorized_access_attempt','identity_theft',
    'copyright_or_intellectual_property_violation','ban_evasion','review_or_rating_manipulation',
    'dangerous_activity','animal_welfare','dangerous_goods_or_services','malware_or_phishing',
    'extortion_or_blackmail','self_harm_safety_concern','harmful_recruitment_or_organized_activity',
    'context_or_identity_dispute','other')),
  constraint reports_category_subcategory_fk foreign key (category, subcategory)
    references safety.report_category_subcategories(category, subcategory) on delete restrict,
  constraint reports_description_length_ck check (description is null or char_length(description) <= 1000),
  constraint reports_status_ck check (status in ('new','under_review','action_taken','no_violation','closed')),
  constraint reports_assigned_admin_ck check (status <> 'under_review' or assigned_admin_id is not null),
  constraint reports_status_resolution_ck check (
    (status in ('new','under_review') and resolved_at is null)
    or (status in ('action_taken','no_violation','closed') and resolved_at is not null)),
  constraint reports_resolved_at_ck check (resolved_at is null or resolved_at >= created_at)
);
create index reports_reporter_created_ix on safety.reports(reporter_user_id, created_at desc);
create index reports_reported_created_ix on safety.reports(reported_user_id, created_at desc);
create index reports_status_created_ix on safety.reports(status, created_at desc);
create index reports_category_created_ix on safety.reports(category, created_at desc);

create table safety.moderation_actions (
  id bigint generated always as identity primary key,
  target_user_id uuid not null references core.users(user_id) on delete restrict,
  admin_user_id bigint not null references safety.admin_users(id) on delete restrict,
  report_id bigint references safety.reports(id) on delete restrict,
  action_type varchar(40) not null,
  reason_code varchar(60) not null,
  status varchar(20) not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  reversed_at timestamptz,
  reversed_by_admin_id bigint references safety.admin_users(id) on delete restrict,
  constraint moderation_actions_action_type_ck check (action_type in (
    'warning','content_removal','temporary_suspension','account_restriction','permanent_suspension',
    'content_restriction','comment_removal','message_restriction','profile_restriction','feature_restriction',
    'access_revocation','content_flagging','content_visibility_limit','comment_lock','reply_restriction',
    'direct_message_limit','contact_block','forced_password_reset','session_revocation','feature_access_pause',
    'age_gate','final_warning','read_only_restriction','specialist_referral','education_notice')),
  constraint moderation_actions_reason_code_ck check (reason_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint moderation_actions_status_ck check (status in ('active','expired','reversed')),
  constraint moderation_actions_expiry_ck check (expires_at is null or expires_at > created_at),
  constraint moderation_actions_permanent_expiry_ck check (action_type <> 'permanent_suspension' or expires_at is null),
  constraint moderation_actions_temporary_expiry_ck check (
    action_type not in ('temporary_suspension','feature_access_pause','read_only_restriction','comment_lock')
    or expires_at is not null),
  constraint moderation_actions_expired_status_ck check (status <> 'expired' or expires_at is not null),
  constraint moderation_actions_reversal_ck check (
    (status = 'reversed' and reversed_at is not null and reversed_by_admin_id is not null)
    or (status <> 'reversed' and reversed_at is null and reversed_by_admin_id is null)),
  constraint moderation_actions_reversed_at_ck check (reversed_at is null or reversed_at >= created_at)
);
create index moderation_actions_target_created_ix on safety.moderation_actions(target_user_id, created_at desc);
create index moderation_actions_admin_created_ix on safety.moderation_actions(admin_user_id, created_at desc);
create index moderation_actions_report_ix on safety.moderation_actions(report_id) where report_id is not null;
create index moderation_actions_expiry_ix on safety.moderation_actions(expires_at) where expires_at is not null;

create table safety.moderation_appeals (
  id bigint generated always as identity primary key,
  moderation_action_id bigint not null references safety.moderation_actions(id) on delete restrict,
  appellant_user_id uuid not null references core.users(user_id) on delete restrict,
  status varchar(20) not null default 'submitted',
  statement text,
  reviewer_admin_id bigint references safety.admin_users(id) on delete restrict,
  decision_reason_code varchar(60),
  created_at timestamptz not null default clock_timestamp(),
  decided_at timestamptz,
  constraint moderation_appeals_status_ck check (status in ('submitted','under_review','approved','rejected')),
  constraint moderation_appeals_statement_ck check (statement is null or char_length(statement) <= 2000),
  constraint moderation_appeals_reviewer_ck check (status = 'submitted' or reviewer_admin_id is not null),
  constraint moderation_appeals_decision_ck check (
    (status in ('submitted','under_review') and decision_reason_code is null and decided_at is null)
    or (status = 'approved' and decision_reason_code = 'appeal_accepted' and decided_at is not null)
    or (status = 'rejected' and decision_reason_code = 'original_action_upheld' and decided_at is not null)),
  constraint moderation_appeals_time_ck check (decided_at is null or decided_at >= created_at)
);
create unique index moderation_appeals_one_open_uq on safety.moderation_appeals(moderation_action_id)
  where status in ('submitted','under_review');
create index moderation_appeals_appellant_created_ix on safety.moderation_appeals(appellant_user_id, created_at desc);
create index moderation_appeals_reviewer_ix on safety.moderation_appeals(reviewer_admin_id) where reviewer_admin_id is not null;

create table safety.legal_holds (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  case_reference varchar(20) not null,
  scope varchar(40) not null,
  restricted_actions text[] not null,
  status varchar(20) not null default 'active',
  imposed_by_admin_id bigint not null references safety.admin_users(id) on delete restrict,
  reason_code varchar(60) not null,
  reason_note text,
  imposed_at timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  released_at timestamptz,
  released_by_admin_id bigint references safety.admin_users(id) on delete restrict,
  release_reason_code varchar(60),
  constraint legal_holds_case_reference_ck check (case_reference ~ '^LH-[0-9]{4}-[0-9]{4}$'),
  constraint legal_holds_scope_ck check (scope in (
    'specified_user_accounts','specified_content_items','specified_communications','access_and_security_logs',
    'transaction_records','moderation_and_appeal_history')),
  constraint legal_holds_restricted_actions_ck check (
    cardinality(restricted_actions) > 0 and restricted_actions <@ array[
      'block_account_erasure','block_content_deletion','block_message_deletion','block_media_deletion',
      'block_data_job_purge','preserve_audit_logs','preserve_moderation_records','freeze_account_status_change']::text[]),
  constraint legal_holds_status_ck check (status in ('active','released','expired')),
  constraint legal_holds_reason_code_ck check (reason_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint legal_holds_reason_note_ck check ((reason_code = 'other' and reason_note is not null) or reason_code <> 'other'),
  constraint legal_holds_reason_note_length_ck check (reason_note is null or char_length(reason_note) <= 500),
  constraint legal_holds_effective_until_ck check (effective_until is null or effective_until >= imposed_at),
  constraint legal_holds_release_fields_ck check (
    (status = 'active' and released_at is null and released_by_admin_id is null and release_reason_code is null)
    or (status = 'released' and released_at is not null and released_at >= imposed_at and released_by_admin_id is not null and release_reason_code is not null)
    or (status = 'expired' and effective_until is not null and released_at is null and released_by_admin_id is null and release_reason_code is null)),
  constraint legal_holds_release_reason_ck check (release_reason_code is null or release_reason_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$')
);
create index legal_holds_user_ix on safety.legal_holds(user_id);
create index legal_holds_case_reference_ix on safety.legal_holds(case_reference);
create index legal_holds_active_ix on safety.legal_holds(user_id, effective_until) where status = 'active';

comment on table safety.report_category_subcategories is 'Authoritative 219-pair safety taxonomy seeded from Tejaswini workbook.';
comment on table safety.legal_holds is 'Every deletion/erasure worker must check active restricted actions before destructive work.';
