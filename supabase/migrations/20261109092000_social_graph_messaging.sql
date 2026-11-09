create table core.connection_intents (
  intent_id varchar(20) not null,
  intent_code varchar(40) primary key,
  display_label varchar(80) not null,
  category varchar(40) not null,
  status varchar(20) not null default 'active',
  sort_order smallint,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint connection_intents_id_uq unique (intent_id),
  constraint connection_intents_label_uq unique (display_label),
  constraint connection_intents_code_ck check (intent_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint connection_intents_category_ck check (category in (
    'professional_general_networking','friendship_social_connection','learning_skill_development',
    'hobbies_lifestyle_activities','community_volunteering')),
  constraint connection_intents_status_ck check (status in ('active','inactive')),
  constraint connection_intents_sort_ck check (sort_order is null or sort_order > 0),
  constraint connection_intents_category_sort_uq unique (category, sort_order)
);

create table core.connection_requests (
  id bigint generated always as identity primary key,
  sender_user_id uuid not null references core.users(user_id) on delete restrict,
  recipient_user_id uuid not null references core.users(user_id) on delete restrict,
  category varchar(20) not null,
  intent_code varchar(40) references core.connection_intents(intent_code) on delete restrict,
  source_context varchar(30),
  status varchar(20) not null default 'pending',
  reason_text varchar(300),
  idempotency_key varchar(255),
  created_at timestamptz not null default clock_timestamp(),
  responded_at timestamptz,
  expires_at timestamptz not null default (clock_timestamp() + interval '30 days'),
  cooldown_until timestamptz,
  constraint connection_requests_not_self_ck check (sender_user_id <> recipient_user_id),
  constraint connection_requests_category_ck check (category in ('collaboration','colleague','friendship','mentorship','networking')),
  constraint connection_requests_source_ck check (source_context is null or source_context in ('events','mutual_connections','profile','search','suggestions')),
  constraint connection_requests_status_ck check (status in ('pending','accepted','declined','withdrawn','cancelled','expired')),
  constraint connection_requests_reason_ck check (reason_text is null or char_length(reason_text) <= 300),
  constraint connection_requests_idempotency_uq unique (sender_user_id, idempotency_key),
  constraint connection_requests_expiry_ck check (expires_at > created_at),
  constraint connection_requests_response_ck check (
    (status = 'pending' and responded_at is null)
    or (status = 'expired' and responded_at is null)
    or (status in ('accepted','declined','withdrawn','cancelled') and responded_at is not null and responded_at >= created_at)),
  constraint connection_requests_cooldown_ck check (cooldown_until is null or cooldown_until >= created_at)
);
create unique index connection_requests_one_pending_direction_uq
  on core.connection_requests(sender_user_id, recipient_user_id) where status = 'pending';
create index connection_requests_recipient_status_ix on core.connection_requests(recipient_user_id, status, created_at desc);
create index connection_requests_sender_created_ix on core.connection_requests(sender_user_id, created_at desc);

create table core.blocks (
  id bigint generated always as identity primary key,
  blocker_user_id uuid not null references core.users(user_id) on delete restrict,
  blocked_user_id uuid not null references core.users(user_id) on delete restrict,
  block_type varchar(20) not null default 'full',
  reason_code varchar(50),
  source varchar(20) not null default 'user',
  source_context varchar(30),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  removed_at timestamptz,
  constraint blocks_not_self_ck check (blocker_user_id <> blocked_user_id),
  constraint blocks_type_ck check (block_type in ('dms_only','full','mute','soft_block')),
  constraint blocks_source_ck check (source in ('user','moderator')),
  constraint blocks_context_ck check (source_context is null or source_context in ('comments','direct_message','group_chat','profile_page','search_results')),
  constraint blocks_reason_ck check (reason_code is null or reason_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint blocks_expires_ck check (expires_at is null or expires_at > created_at),
  constraint blocks_removed_ck check (removed_at is null or removed_at >= created_at)
);
create unique index blocks_one_active_pair_uq on core.blocks(blocker_user_id, blocked_user_id) where removed_at is null;
create index blocks_blocked_active_ix on core.blocks(blocked_user_id) where removed_at is null;

create table core.user_pseudonyms (
  pseudonym_id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references core.users(user_id) on delete restrict,
  handle varchar(100) not null,
  scope varchar(30) not null,
  status varchar(20) not null default 'active',
  is_default boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  rotated_at timestamptz,
  constraint user_pseudonyms_scope_ck check (scope in ('anonymous_feedback','blind_recruiting','community_forum','public_networking','private_group')),
  constraint user_pseudonyms_status_ck check (status in ('active','rotated','revoked','dormant')),
  constraint user_pseudonyms_rotated_ck check ((status = 'rotated') = (rotated_at is not null)),
  constraint user_pseudonyms_time_ck check (rotated_at is null or rotated_at >= created_at)
);
create unique index user_pseudonyms_handle_ci_uq on core.user_pseudonyms(scope, lower(handle));
create unique index user_pseudonyms_one_default_uq on core.user_pseudonyms(user_id, scope) where is_default and status = 'active';
create index user_pseudonyms_owner_ix on core.user_pseudonyms(user_id, scope, status);

create table core.profile_media (
  media_id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references core.users(user_id) on delete restrict,
  storage_bucket varchar(60) not null,
  object_key varchar(255) not null,
  media_type varchar(20) not null,
  moderation_status varchar(20) not null default 'pending',
  lifecycle_status varchar(20) not null default 'active',
  sort_order smallint not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  purge_after timestamptz,
  purged_at timestamptz,
  constraint profile_media_media_user_uq unique (media_id, user_id),
  constraint profile_media_object_uq unique (storage_bucket, object_key),
  constraint profile_media_bucket_ck check (storage_bucket in ('user-profile-media-prod','quarantine-profile-media')),
  constraint profile_media_type_ck check (media_type in ('audio','image','video')),
  constraint profile_media_moderation_ck check (moderation_status in ('pending','approved','rejected','quarantined')),
  constraint profile_media_lifecycle_ck check (lifecycle_status in ('active','deleted','purged')),
  constraint profile_media_sort_ck check (sort_order >= 0),
  constraint profile_media_lifecycle_fields_ck check (
    (lifecycle_status = 'active' and deleted_at is null and purged_at is null)
    or (lifecycle_status = 'deleted' and deleted_at is not null and purged_at is null)
    or (lifecycle_status = 'purged' and deleted_at is not null and purged_at is not null)),
  constraint profile_media_times_ck check (
    (deleted_at is null or deleted_at >= created_at)
    and (purge_after is null or (deleted_at is not null and purge_after >= deleted_at))
    and (purged_at is null or (deleted_at is not null and purged_at >= deleted_at)))
);
create index profile_media_owner_state_ix on core.profile_media(user_id, lifecycle_status, sort_order);

alter table core.profiles
  add constraint profiles_media_owner_fk
  foreign key (profile_media_id, user_id)
  references core.profile_media(media_id, user_id)
  on delete restrict;

create table core.notification_categories (
  category_code varchar(40) primary key,
  display_label varchar(100) not null,
  description text not null,
  default_priority text not null default 'normal',
  is_mandatory boolean not null default false,
  requires_marketing_consent boolean not null default false,
  status text not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint notification_categories_code_ck check (category_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint notification_categories_priority_ck check (default_priority in ('critical','high','normal','low')),
  constraint notification_categories_status_ck check (status in ('active','deprecated'))
);

create table core.notification_category_channels (
  channel varchar(20) not null,
  category_code varchar(40) not null references core.notification_categories(category_code) on delete restrict,
  primary key (channel, category_code),
  constraint notification_category_channels_channel_ck check (channel in ('in_app','push','email'))
);

create table core.connection_closed_reasons (
  code varchar(40) not null,
  closed_by_type text not null,
  description text not null,
  is_user_visible boolean not null default true,
  status text not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  primary key (code, closed_by_type),
  constraint connection_closed_reasons_code_ck check (code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint connection_closed_reasons_actor_ck check (closed_by_type in ('user','admin','system')),
  constraint connection_closed_reasons_status_ck check (status in ('active','deprecated'))
);

create table core.notification_category_preferences (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  channel varchar(20) not null,
  category varchar(40) not null,
  enabled boolean not null default true,
  priority_level text not null default 'normal',
  preferred_notification_period text,
  snoozed_from timestamptz,
  snoozed_until timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint notification_category_preferences_uq unique (user_id, channel, category),
  constraint notification_category_preferences_pair_fk foreign key (channel, category)
    references core.notification_category_channels(channel, category_code) on delete restrict,
  constraint notification_category_preferences_priority_ck check (priority_level in ('critical','high','normal','low')),
  constraint notification_category_preferences_period_ck check (preferred_notification_period is null or preferred_notification_period in ('anytime','morning','afternoon','evening')),
  constraint notification_category_preferences_snooze_ck check (
    (snoozed_from is null and snoozed_until is null)
    or (snoozed_from is not null and snoozed_until is not null and snoozed_until > snoozed_from))
);
create index notification_category_preferences_user_ix on core.notification_category_preferences(user_id);

create table core.device_tokens (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  provider varchar(20) not null,
  platform varchar(20) not null,
  token_ciphertext bytea not null,
  token_nonce bytea not null,
  token_key_version text not null,
  token_fingerprint bytea not null,
  status varchar(20) not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  revoked_at timestamptz,
  invalidated_at timestamptz,
  constraint device_tokens_provider_ck check (provider in ('apns','fcm','webpush','wns')),
  constraint device_tokens_platform_ck check (platform in ('android','ios','ipados','macos','windows','web')),
  constraint device_tokens_provider_platform_ck check (
    (provider = 'apns' and platform in ('ios','ipados','macos'))
    or (provider = 'fcm' and platform = 'android')
    or (provider = 'wns' and platform = 'windows')
    or (provider = 'webpush' and platform = 'web')),
  constraint device_tokens_nonce_len_ck check (octet_length(token_nonce) = 12),
  constraint device_tokens_fingerprint_len_ck check (octet_length(token_fingerprint) = 32),
  constraint device_tokens_nonce_uq unique (token_key_version, token_nonce),
  constraint device_tokens_status_ck check (status in ('active','revoked','invalid','expired')),
  constraint device_tokens_times_ck check (
    (expires_at is null or expires_at > created_at)
    and (revoked_at is null or revoked_at >= created_at)
    and (invalidated_at is null or invalidated_at >= created_at)),
  constraint device_tokens_status_fields_ck check (
    (status = 'active' and revoked_at is null and invalidated_at is null)
    or (status = 'revoked' and revoked_at is not null and invalidated_at is null)
    or (status = 'invalid' and invalidated_at is not null and revoked_at is null)
    or (status = 'expired' and expires_at is not null and revoked_at is null and invalidated_at is null))
);
create unique index device_tokens_active_fingerprint_uq on core.device_tokens(provider, token_fingerprint) where status = 'active';
create index device_tokens_owner_status_ix on core.device_tokens(user_id, status);

create table core.connections (
  id bigint generated always as identity primary key,
  user_low_id uuid not null references core.users(user_id) on delete restrict,
  user_high_id uuid not null references core.users(user_id) on delete restrict,
  status varchar(20) not null default 'active',
  created_from_request_id bigint references core.connection_requests(id) on delete restrict,
  connection_source varchar(30) not null,
  created_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  closed_reason varchar(40),
  closed_by_type text,
  closed_by_user_id uuid references core.users(user_id) on delete restrict,
  last_interaction_at timestamptz,
  interaction_count bigint not null default 0,
  constraint connections_canonical_pair_ck check (user_low_id < user_high_id),
  constraint connections_status_ck check (status in ('active','closed')),
  constraint connections_request_uq unique (created_from_request_id),
  constraint connections_source_ck check (connection_source in ('events','mutual_connections','profile','search','suggestions')),
  constraint connections_closed_actor_fk foreign key (closed_reason, closed_by_type)
    references core.connection_closed_reasons(code, closed_by_type) on delete restrict,
  constraint connections_closed_ck check (
    (status = 'active' and closed_at is null and closed_reason is null and closed_by_type is null and closed_by_user_id is null)
    or (status = 'closed' and closed_at is not null and closed_reason is not null and closed_by_type is not null
      and ((closed_by_type = 'user' and closed_by_user_id in (user_low_id, user_high_id))
        or (closed_by_type in ('admin','system') and closed_by_user_id is null)))),
  constraint connections_times_ck check (
    (closed_at is null or closed_at >= created_at)
    and (last_interaction_at is null or last_interaction_at >= created_at)),
  constraint connections_interaction_count_ck check (interaction_count >= 0)
);
create unique index connections_one_open_pair_uq on core.connections(user_low_id, user_high_id) where status = 'active';
create index connections_low_ix on core.connections(user_low_id, created_at desc);
create index connections_high_ix on core.connections(user_high_id, created_at desc);

create table core.relations (
  id bigint generated always as identity primary key,
  actor_user_id uuid not null references core.users(user_id) on delete restrict,
  target_user_id uuid not null references core.users(user_id) on delete restrict,
  profile_prompt_id bigint,
  relation_source varchar(30) not null,
  reaction_type varchar(20) not null default 'like',
  status varchar(20) not null default 'active',
  idempotency_key varchar(255),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  undone_at timestamptz,
  constraint relations_not_self_ck check (actor_user_id <> target_user_id),
  constraint relations_prompt_owner_fk foreign key (profile_prompt_id, target_user_id)
    references core.profile_prompts(id, user_id) on delete restrict,
  constraint relations_source_ck check (relation_source in ('profile','prompt_answer','search','mutual_connections','suggestions')),
  constraint relations_reaction_ck check (reaction_type in ('like','wave','endorse','react')),
  constraint relations_status_ck check (status in ('active','undone','hidden','expired')),
  constraint relations_idempotency_uq unique (actor_user_id, idempotency_key),
  constraint relations_time_ck check (
    (expires_at is null or expires_at > created_at)
    and (undone_at is null or undone_at >= created_at)),
  constraint relations_undone_ck check ((status = 'undone') = (undone_at is not null)),
  constraint relations_expired_ck check (status <> 'expired' or expires_at is not null)
);
create unique index relations_one_active_profile_uq
  on core.relations(actor_user_id, target_user_id, reaction_type)
  where status = 'active' and profile_prompt_id is null;
create unique index relations_one_active_prompt_uq
  on core.relations(actor_user_id, target_user_id, reaction_type, profile_prompt_id)
  where status = 'active' and profile_prompt_id is not null;
create index relations_target_created_ix on core.relations(target_user_id, created_at desc);

create table core.discovery_dismissals (
  id bigint generated always as identity primary key,
  viewer_user_id uuid not null references core.users(user_id) on delete restrict,
  candidate_user_id uuid not null references core.users(user_id) on delete restrict,
  scope varchar(20) not null default 'all',
  reason_code varchar(40),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  category_code varchar(30),
  reversed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint discovery_dismissals_not_self_ck check (viewer_user_id <> candidate_user_id),
  constraint discovery_dismissals_scope_ck check (scope in ('temporary','all','category')),
  constraint discovery_dismissals_reason_ck check (reason_code is null or reason_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint discovery_dismissals_scope_fields_ck check (
    (scope = 'temporary' and expires_at is not null and category_code is null)
    or (scope = 'category' and expires_at is null and category_code is not null)
    or (scope = 'all' and expires_at is null and category_code is null)),
  constraint discovery_dismissals_times_ck check (
    (expires_at is null or expires_at > created_at)
    and (reversed_at is null or reversed_at >= created_at))
);
create index discovery_dismissals_viewer_active_ix on core.discovery_dismissals(viewer_user_id, candidate_user_id) where reversed_at is null;

create table core.acknowledgements (
  id bigint generated always as identity primary key,
  actor_user_id uuid not null references core.users(user_id) on delete restrict,
  target_user_id uuid not null references core.users(user_id) on delete restrict,
  category varchar(40) not null,
  subcategory varchar(40) not null,
  status varchar(20) not null default 'active',
  idempotency_key varchar(255),
  created_at timestamptz not null default clock_timestamp(),
  undone_at timestamptz,
  constraint acknowledgements_not_self_ck check (actor_user_id <> target_user_id),
  constraint acknowledgements_category_ck check (category in (
    'gratitude_appreciation','love_affection','joy_celebration','encouragement_motivation','care_concern',
    'empathy_support','respect_admiration','friendship_belonging','apology_forgiveness','hope_wellbeing')),
  constraint acknowledgements_subcategory_ck check (subcategory ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint acknowledgements_status_ck check (status in ('active','undone','hidden','expired')),
  constraint acknowledgements_idempotency_uq unique (actor_user_id, idempotency_key),
  constraint acknowledgements_undone_ck check ((status = 'undone') = (undone_at is not null)),
  constraint acknowledgements_time_ck check (undone_at is null or undone_at >= created_at)
);
create index acknowledgements_target_created_ix on core.acknowledgements(target_user_id, created_at desc);

create table core.conversations (
  id bigint generated always as identity primary key,
  connection_id bigint not null references core.connections(id) on delete restrict,
  type varchar(20) not null default 'direct',
  status varchar(20) not null default 'active',
  last_message_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint conversations_connection_uq unique (connection_id),
  constraint conversations_type_ck check (type = 'direct'),
  constraint conversations_status_ck check (status in ('active','restricted','closed')),
  constraint conversations_closed_ck check ((status = 'closed') = (closed_at is not null)),
  constraint conversations_times_ck check (
    (last_message_at is null or last_message_at >= created_at)
    and (closed_at is null or closed_at >= created_at))
);

create table core.conversation_participants (
  id bigint generated always as identity primary key,
  conversation_id bigint not null references core.conversations(id) on delete restrict,
  user_id uuid not null references core.users(user_id) on delete restrict,
  role varchar(20) not null default 'member',
  status varchar(20) not null default 'active',
  joined_at timestamptz not null default clock_timestamp(),
  left_at timestamptz,
  added_by_user_id uuid references core.users(user_id) on delete restrict,
  removed_by_user_id uuid references core.users(user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint conversation_participants_role_ck check (role = 'member'),
  constraint conversation_participants_status_ck check (status in ('active','left','removed','banned')),
  constraint conversation_participants_left_ck check (
    (status = 'active' and left_at is null and removed_by_user_id is null)
    or (status = 'left' and left_at is not null and removed_by_user_id is null)
    or (status in ('removed','banned') and left_at is not null and removed_by_user_id is not null)),
  constraint conversation_participants_time_ck check (left_at is null or left_at >= joined_at)
);
create unique index conversation_participants_one_active_uq on core.conversation_participants(conversation_id, user_id) where status = 'active';
create index conversation_participants_user_active_ix on core.conversation_participants(user_id, conversation_id) where status = 'active';

create table core.messages (
  id bigint generated always as identity primary key,
  conversation_id bigint not null references core.conversations(id) on delete restrict,
  conversation_seq bigint not null,
  sender_user_id uuid not null references core.users(user_id) on delete restrict,
  client_message_id varchar(64) not null,
  message_type varchar(20) not null default 'text',
  content jsonb not null,
  status varchar(20) not null default 'sent',
  created_at timestamptz not null default clock_timestamp(),
  edited_at timestamptz,
  deleted_at timestamptz,
  reply_to_message_id bigint,
  public_id uuid not null default extensions.gen_random_uuid(),
  constraint messages_conversation_id_uq unique (conversation_id, id),
  constraint messages_sequence_uq unique (conversation_id, conversation_seq),
  constraint messages_sender_client_uq unique (sender_user_id, client_message_id),
  constraint messages_public_id_uq unique (public_id),
  constraint messages_sequence_ck check (conversation_seq > 0),
  constraint messages_type_ck check (message_type in ('text','system')),
  constraint messages_content_object_ck check (jsonb_typeof(content) = 'object'),
  constraint messages_text_length_ck check (message_type <> 'text' or (content ? 'text' and char_length(content->>'text') between 1 and 2000)),
  constraint messages_status_ck check (status in ('sent','hidden','removed','quarantined')),
  constraint messages_removed_ck check (
    (status = 'removed' and deleted_at is not null and content = '{}'::jsonb)
    or (status <> 'removed' and deleted_at is null)),
  constraint messages_times_ck check (
    (edited_at is null or edited_at >= created_at)
    and (deleted_at is null or deleted_at >= created_at)),
  constraint messages_reply_fk foreign key (conversation_id, reply_to_message_id)
    references core.messages(conversation_id, id) on delete restrict
);
create index messages_conversation_created_ix on core.messages(conversation_id, created_at desc);

create table core.message_read_cursors (
  conversation_id bigint not null references core.conversations(id) on delete restrict,
  user_id uuid not null references core.users(user_id) on delete restrict,
  last_read_message_id bigint,
  last_read_at timestamptz,
  primary key (conversation_id, user_id),
  constraint message_read_cursors_message_fk foreign key (conversation_id, last_read_message_id)
    references core.messages(conversation_id, id) on delete restrict,
  constraint message_read_cursors_pair_ck check ((last_read_message_id is null) = (last_read_at is null))
);

comment on table core.connections is 'One accepted canonical user pair per connection episode; requests are accepted through core.accept_connection_request().';
comment on table core.relations is 'Lightweight profile/prompt reactions. Mutuality is exposed through a derived view rather than stored.';
comment on table core.acknowledgements is 'Explicit supportive acknowledgement taxonomy, distinct from lightweight relations.';
