create table analytics.product_events (
  id bigint generated always as identity primary key,
  event_type varchar(40) not null,
  actor_pseudonym_id uuid references core.user_pseudonyms(pseudonym_id) on delete restrict,
  aggregate_type varchar(30),
  aggregate_id text,
  event_time timestamptz not null default clock_timestamp(),
  ingested_at timestamptz not null default clock_timestamp(),
  properties jsonb not null,
  source_outbox_event_id bigint references core.outbox_events(id) on delete restrict,
  event_idempotency_key uuid,
  event_source varchar(20),
  session_id uuid,
  constraint product_events_type_ck check (event_type ~ '^[a-z][a-z0-9_]{1,39}$'),
  constraint product_events_aggregate_ck check ((aggregate_type is null) = (aggregate_id is null)),
  constraint product_events_properties_ck check (jsonb_typeof(properties) = 'object' and properties ? 'schema_version'),
  constraint product_events_source_ck check (event_source is null or event_source in ('web','android','ios','api','system')),
  constraint product_events_ingestion_time_ck check (ingested_at >= event_time - interval '24 hours'),
  constraint product_events_outbox_uq unique (source_outbox_event_id),
  constraint product_events_idempotency_uq unique (event_idempotency_key)
);
create index product_events_type_time_ix on analytics.product_events(event_type, event_time desc);
create index product_events_actor_time_ix on analytics.product_events(actor_pseudonym_id, event_time desc) where actor_pseudonym_id is not null;
create index product_events_aggregate_time_ix on analytics.product_events(aggregate_type, aggregate_id, event_time desc) where aggregate_type is not null;

create table analytics.discovery_impressions (
  id bigint generated always as identity primary key,
  request_id uuid not null,
  viewer_pseudonym_id uuid not null references core.user_pseudonyms(pseudonym_id) on delete restrict,
  candidate_pseudonym_id uuid not null references core.user_pseudonyms(pseudonym_id) on delete restrict,
  position smallint not null,
  reason_codes text[] not null default '{}'::text[],
  mode varchar(30) not null default 'default',
  content_category varchar(50),
  subcategory varchar(60),
  decay_factor numeric(4,3) not null default 1.000,
  impression_week varchar(8) not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint discovery_impressions_not_self_ck check (viewer_pseudonym_id <> candidate_pseudonym_id),
  constraint discovery_impressions_position_ck check (position > 0),
  constraint discovery_impressions_request_position_uq unique (request_id, position),
  constraint discovery_impressions_mode_ck check (mode ~ '^[a-z][a-z0-9_]{0,29}$'),
  constraint discovery_impressions_reason_codes_ck check (cardinality(reason_codes) <= 20),
  constraint discovery_impressions_decay_ck check (decay_factor between 0 and 1),
  constraint discovery_impressions_week_ck check (impression_week ~ '^[0-9]{4}-W[0-9]{2}$')
);
create index discovery_impressions_created_ix on analytics.discovery_impressions(created_at desc);
create index discovery_impressions_viewer_created_ix on analytics.discovery_impressions(viewer_pseudonym_id, created_at desc);
create index discovery_impressions_candidate_created_ix on analytics.discovery_impressions(candidate_pseudonym_id, created_at desc);

create table safety.report_evidence (
  id bigint generated always as identity primary key,
  report_id bigint not null references safety.reports(id) on delete restrict,
  evidence_type varchar(40) not null,
  source_entity_type varchar(40),
  source_entity_id text,
  snapshot_payload jsonb not null,
  reporting_user_behavior jsonb not null default '{}'::jsonb,
  reported_user_behavior jsonb not null default '{}'::jsonb,
  relation varchar(30),
  connection_source varchar(30),
  captured_at timestamptz not null default clock_timestamp(),
  retention_until timestamptz,
  purged_at timestamptz,
  evidence_file_hash varchar(64),
  verification_status varchar(20) not null default 'pending',
  reviewed_by_admin_id bigint references safety.admin_users(id) on delete restrict,
  reviewed_at timestamptz,
  redaction_status varchar(20) not null default 'not_redacted',
  access_level varchar(30) not null default 'moderators',
  constraint report_evidence_type_ck check (evidence_type in (
    'screenshot','screen_recording','post_snapshot','comment_snapshot','chat_snapshot',
    'profile_snapshot','audio_recording','video_recording','document','system_log')),
  constraint report_evidence_source_pair_ck check ((source_entity_type is null) = (source_entity_id is null)),
  constraint report_evidence_payload_ck check (
    jsonb_typeof(snapshot_payload) = 'object'
    and jsonb_typeof(reporting_user_behavior) = 'object'
    and jsonb_typeof(reported_user_behavior) = 'object'),
  constraint report_evidence_relation_ck check (relation is null or relation in ('stranger','follower','mutual_friend','collaborator')),
  constraint report_evidence_connection_source_ck check (connection_source is null or connection_source in ('qr_scan','direct_search','shared_group','algorithmic_suggestion')),
  constraint report_evidence_retention_ck check (retention_until is null or retention_until >= captured_at),
  constraint report_evidence_purge_ck check (purged_at is null or purged_at >= captured_at),
  constraint report_evidence_hash_ck check (evidence_file_hash is null or evidence_file_hash ~ '^[a-f0-9]{64}$'),
  constraint report_evidence_verification_ck check (verification_status in ('pending','verified','rejected')),
  constraint report_evidence_review_ck check (
    (verification_status = 'pending' and reviewed_by_admin_id is null and reviewed_at is null)
    or (verification_status in ('verified','rejected') and reviewed_by_admin_id is not null and reviewed_at is not null)),
  constraint report_evidence_review_time_ck check (reviewed_at is null or reviewed_at >= captured_at),
  constraint report_evidence_redaction_ck check (redaction_status in ('not_redacted','partially_redacted','fully_redacted')),
  constraint report_evidence_access_ck check (access_level in ('moderators','security_admins','legal_only'))
);
create index report_evidence_report_ix on safety.report_evidence(report_id);
create index report_evidence_retention_ix on safety.report_evidence(retention_until) where purged_at is null;
create index report_evidence_type_captured_ix on safety.report_evidence(evidence_type, captured_at desc);

create table audit.audit_product_event (
  id bigint generated always as identity primary key,
  event_timestamp timestamptz not null default clock_timestamp(),
  actor_type varchar(20) not null,
  user_id uuid references core.users(user_id) on delete restrict,
  admin_user_id bigint references safety.admin_users(id) on delete restrict,
  action_type varchar(60) not null,
  event_category varchar(30) not null,
  target_user_id uuid references core.users(user_id) on delete restrict,
  request_id varchar(100),
  event_status varchar(20) not null,
  failure_reason varchar(100),
  event_source varchar(20),
  ip_hmac bytea,
  device_id varchar(100),
  authentication_method varchar(30),
  data_modified boolean not null default false,
  previous_value jsonb,
  new_value jsonb,
  metadata jsonb not null default '{}'::jsonb,
  constraint audit_product_event_actor_type_ck check (actor_type in ('user','admin','support','system')),
  constraint audit_product_event_actor_ck check (
    (actor_type = 'user' and user_id is not null and admin_user_id is null)
    or (actor_type in ('admin','support') and admin_user_id is not null)
    or (actor_type = 'system' and user_id is null and admin_user_id is null)),
  constraint audit_product_event_action_ck check (action_type ~ '^[a-z][a-z0-9_]{1,59}$'),
  constraint audit_product_event_category_ck check (event_category in ('authentication','identity','profile','connection','messaging','notification','safety','privacy','security','data_job','system')),
  constraint audit_product_event_request_ck check (request_id is null or request_id ~ '^[A-Za-z0-9:._-]{1,100}$'),
  constraint audit_product_event_status_ck check (event_status in ('success','failure')),
  constraint audit_product_event_failure_ck check ((event_status = 'failure') = (failure_reason is not null)),
  constraint audit_product_event_source_ck check (event_source is null or event_source in ('web','android','ios','api','worker','admin_console','system')),
  constraint audit_product_event_ip_hmac_ck check (ip_hmac is null or octet_length(ip_hmac) = 32),
  constraint audit_product_event_auth_method_ck check (authentication_method is null or authentication_method in ('email_otp','phone_otp','google','apple','staff_sso','service')),
  constraint audit_product_event_values_ck check (
    (data_modified and (previous_value is not null or new_value is not null))
    or (not data_modified and previous_value is null and new_value is null)),
  constraint audit_product_event_json_ck check (
    (previous_value is null or jsonb_typeof(previous_value) = 'object')
    and (new_value is null or jsonb_typeof(new_value) = 'object')
    and jsonb_typeof(metadata) = 'object')
);
create index audit_product_event_time_ix on audit.audit_product_event(event_timestamp desc);
create index audit_product_event_user_time_ix on audit.audit_product_event(user_id, event_timestamp desc) where user_id is not null;
create index audit_product_event_admin_time_ix on audit.audit_product_event(admin_user_id, event_timestamp desc) where admin_user_id is not null;
create index audit_product_event_action_time_ix on audit.audit_product_event(action_type, event_timestamp desc);
create index audit_product_event_request_ix on audit.audit_product_event(request_id) where request_id is not null;
create index audit_product_event_target_time_ix on audit.audit_product_event(target_user_id, event_timestamp desc) where target_user_id is not null;

comment on table analytics.product_events is 'Unpartitioned pilot telemetry. Revisit partitioning only after measured volume warrants it.';
comment on column analytics.product_events.actor_pseudonym_id is 'Purpose-specific pseudonym FK; no direct user UUID is stored in product telemetry.';
comment on table audit.audit_product_event is 'Append-only audit log; sensitive values and plaintext network addresses are prohibited.';
