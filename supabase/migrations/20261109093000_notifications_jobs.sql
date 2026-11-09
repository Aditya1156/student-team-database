create table core.outbox_events (
  id bigint generated always as identity primary key,
  aggregate_type varchar(50) not null,
  aggregate_id text not null,
  aggregate_sequence bigint not null,
  event_type varchar(100) not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  published_at timestamptz,
  status varchar(20) not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz,
  last_error_code varchar(100),
  event_key varchar(255) not null,
  lease_token uuid,
  dead_lettered_at timestamptz,
  lease_owner varchar(100),
  lease_expires_at timestamptz,
  constraint outbox_events_aggregate_sequence_uq unique (aggregate_type, aggregate_id, aggregate_sequence),
  constraint outbox_events_event_key_uq unique (event_key),
  constraint outbox_events_aggregate_type_ck check (aggregate_type ~ '^[a-z][a-z0-9_]{0,49}$'),
  constraint outbox_events_event_type_ck check (event_type ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'),
  constraint outbox_events_payload_object_ck check (jsonb_typeof(payload) = 'object'),
  constraint outbox_events_status_ck check (status in ('pending','processing','published','dead_letter')),
  constraint outbox_events_attempts_ck check (attempt_count >= 0),
  constraint outbox_events_published_ck check ((status = 'published') = (published_at is not null)),
  constraint outbox_events_dead_letter_ck check ((status = 'dead_letter') = (dead_lettered_at is not null)),
  constraint outbox_events_lease_ck check (
    (status = 'processing' and lease_token is not null and lease_owner is not null and lease_expires_at is not null)
    or (status <> 'processing')),
  constraint outbox_events_times_ck check (
    (published_at is null or published_at >= created_at)
    and (dead_lettered_at is null or dead_lettered_at >= created_at))
);
create index outbox_events_worker_ix on core.outbox_events(status, next_attempt_at, created_at);
create index outbox_events_lease_ix on core.outbox_events(lease_expires_at) where status = 'processing';

create table core.notifications (
  id bigint generated always as identity primary key,
  recipient_user_id uuid not null references core.users(user_id) on delete restrict,
  notification_type varchar(40) not null references core.notification_categories(category_code) on delete restrict,
  dedupe_key varchar(255),
  source_event_id bigint references core.outbox_events(id) on delete restrict,
  payload jsonb not null default '{}'::jsonb,
  status varchar(20) not null default 'queued',
  created_at timestamptz not null default clock_timestamp(),
  delivered_at timestamptz,
  read_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint notifications_dedupe_uq unique (recipient_user_id, dedupe_key),
  constraint notifications_payload_object_ck check (jsonb_typeof(payload) = 'object'),
  constraint notifications_status_ck check (status in ('queued','delivered','read','suppressed','failed')),
  constraint notifications_delivered_ck check (
    (status in ('delivered','read') and delivered_at is not null)
    or (status not in ('delivered','read'))),
  constraint notifications_read_ck check ((status = 'read') = (read_at is not null)),
  constraint notifications_times_ck check (
    (delivered_at is null or delivered_at >= created_at)
    and (read_at is null or (delivered_at is not null and read_at >= delivered_at)))
);
create index notifications_recipient_status_ix on core.notifications(recipient_user_id, status, created_at desc);
create index notifications_source_event_ix on core.notifications(source_event_id) where source_event_id is not null;

create table core.account_data_jobs (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  job_type varchar(20) not null,
  status varchar(20) not null default 'queued',
  requested_at timestamptz not null default clock_timestamp(),
  started_at timestamptz,
  completed_at timestamptz,
  export_object_key text,
  export_expires_at timestamptz,
  attempt_count integer not null default 0,
  error_code varchar(100),
  execute_after timestamptz,
  idempotency_key varchar(255),
  lease_expires_at timestamptz,
  worker_id varchar(100),
  lease_token uuid,
  updated_at timestamptz not null default clock_timestamp(),
  constraint account_data_jobs_type_ck check (job_type in ('export','deletion')),
  constraint account_data_jobs_status_ck check (status in ('queued','processing','completed','failed','cancelled')),
  constraint account_data_jobs_attempts_ck check (attempt_count >= 0),
  constraint account_data_jobs_idempotency_uq unique (job_type, idempotency_key),
  constraint account_data_jobs_export_ck check (
    (job_type = 'export') or (export_object_key is null and export_expires_at is null)),
  constraint account_data_jobs_processing_ck check (
    (status = 'processing' and started_at is not null and worker_id is not null and lease_token is not null and lease_expires_at is not null)
    or status <> 'processing'),
  constraint account_data_jobs_completed_ck check ((status = 'completed') = (completed_at is not null)),
  constraint account_data_jobs_times_ck check (
    (started_at is null or started_at >= requested_at)
    and (completed_at is null or (started_at is not null and completed_at >= started_at))
    and (export_expires_at is null or export_expires_at > requested_at))
);
create index account_data_jobs_worker_ix on core.account_data_jobs(status, execute_after, requested_at);
create index account_data_jobs_user_ix on core.account_data_jobs(user_id, requested_at desc);

create table core.account_data_job_steps (
  id bigint generated always as identity primary key,
  job_id bigint not null references core.account_data_jobs(id) on delete restrict,
  step_code varchar(100) not null,
  status varchar(30) not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz,
  lease_token uuid,
  lease_expires_at timestamptz,
  last_error_code varchar(100),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint account_data_job_steps_uq unique (job_id, step_code),
  constraint account_data_job_steps_code_ck check (step_code ~ '^[a-z][a-z0-9_]{0,99}$'),
  constraint account_data_job_steps_status_ck check (status in ('pending','processing','succeeded','retryable_failure','terminal_failure','skipped_by_policy')),
  constraint account_data_job_steps_attempts_ck check (attempt_count >= 0),
  constraint account_data_job_steps_processing_ck check (
    (status = 'processing' and lease_token is not null and lease_expires_at is not null and started_at is not null)
    or status <> 'processing'),
  constraint account_data_job_steps_completed_ck check (
    (status in ('succeeded','terminal_failure','skipped_by_policy') and completed_at is not null)
    or status not in ('succeeded','terminal_failure','skipped_by_policy')),
  constraint account_data_job_steps_times_ck check (completed_at is null or (started_at is not null and completed_at >= started_at))
);
create index account_data_job_steps_worker_ix on core.account_data_job_steps(status, next_attempt_at);

create table core.media_deletion_jobs (
  id bigint generated always as identity primary key,
  profile_media_id uuid references core.profile_media(media_id) on delete set null,
  object_key text not null,
  status varchar(30) not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz,
  lease_expires_at timestamptz,
  last_error_code varchar(100),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  lease_owner varchar(100),
  lease_token uuid,
  dead_lettered_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint media_deletion_jobs_status_ck check (status in ('pending','processing','completed','retry_wait','dead_letter')),
  constraint media_deletion_jobs_attempts_ck check (attempt_count >= 0),
  constraint media_deletion_jobs_processing_ck check (
    (status = 'processing' and lease_owner is not null and lease_token is not null and lease_expires_at is not null)
    or status <> 'processing'),
  constraint media_deletion_jobs_completed_ck check ((status = 'completed') = (completed_at is not null)),
  constraint media_deletion_jobs_dead_letter_ck check ((status = 'dead_letter') = (dead_lettered_at is not null)),
  constraint media_deletion_jobs_times_ck check (
    (completed_at is null or completed_at >= created_at)
    and (dead_lettered_at is null or dead_lettered_at >= created_at))
);
create index media_deletion_jobs_worker_ix on core.media_deletion_jobs(status, next_attempt_at, created_at);

comment on column core.notifications.notification_type is 'Uses Mahera notification category codes as the authoritative preference taxonomy.';
comment on table core.notifications is 'Persistent in-app notification record; push/email delivery is performed from outbox events and effective preferences.';
