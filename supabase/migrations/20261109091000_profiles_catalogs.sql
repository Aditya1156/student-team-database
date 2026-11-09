create table core.interest_categories (
  id bigint generated always as identity primary key,
  name varchar(80) not null,
  slug varchar(100) not null,
  display_order integer not null default 0,
  status varchar(20) not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint interest_categories_name_uq unique (name),
  constraint interest_categories_slug_uq unique (slug),
  constraint interest_categories_name_ck check (btrim(name) <> ''),
  constraint interest_categories_slug_ck check (slug ~ '^cat-[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint interest_categories_order_ck check (display_order >= 0),
  constraint interest_categories_status_ck check (status in ('active','deprecated'))
);

create table core.interest_subcategories (
  id bigint generated always as identity primary key,
  category_id bigint not null references core.interest_categories(id) on delete restrict,
  name varchar(80) not null,
  slug varchar(120) not null,
  display_order integer not null default 0,
  status varchar(20) not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint interest_subcategories_name_uq unique (category_id, name),
  constraint interest_subcategories_slug_uq unique (slug),
  constraint interest_subcategories_name_ck check (btrim(name) <> ''),
  constraint interest_subcategories_slug_ck check (slug ~ '^sub-[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint interest_subcategories_order_ck check (display_order >= 0),
  constraint interest_subcategories_status_ck check (status in ('active','deprecated'))
);
create index interest_subcategories_category_ix on core.interest_subcategories(category_id, display_order);

create table core.interests (
  id bigint generated always as identity primary key,
  subcategory_id bigint not null references core.interest_subcategories(id) on delete restrict,
  label varchar(80) not null,
  slug varchar(160) not null,
  status varchar(20) not null default 'active',
  display_order integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  intent text,
  constraint interests_label_uq unique (subcategory_id, label),
  constraint interests_slug_uq unique (slug),
  constraint interests_label_ck check (btrim(label) <> ''),
  constraint interests_slug_ck check (slug ~ '^intr-[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint interests_status_ck check (status in ('active','deprecated')),
  constraint interests_order_ck check (display_order >= 0),
  constraint interests_intent_ck check (intent is null or intent in ('Learning','Practising','Performing','Creating','Exploring','Competing','Teaching','Sharing'))
);
create index interests_subcategory_ix on core.interests(subcategory_id, display_order);

create table core.prompt_catalogue (
  id bigint generated always as identity primary key,
  prompt_code varchar(60) not null,
  prompt_text text not null,
  answer_type varchar(30) not null default 'text',
  max_length integer not null default 500,
  status varchar(20) not null default 'active',
  display_order integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint prompt_catalogue_code_uq unique (prompt_code),
  constraint prompt_catalogue_code_ck check (prompt_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint prompt_catalogue_text_ck check (btrim(prompt_text) <> ''),
  constraint prompt_catalogue_answer_type_ck check (answer_type in ('text','key_value')),
  constraint prompt_catalogue_length_ck check (max_length between 50 and 2000),
  constraint prompt_catalogue_status_ck check (status in ('active','deprecated')),
  constraint prompt_catalogue_order_ck check (display_order >= 0)
);

create table core.profiles (
  user_id uuid primary key references core.users(user_id) on delete restrict,
  display_name varchar(80) not null,
  handle varchar(40) not null,
  bio varchar(1000),
  city varchar(100),
  state varchar(100),
  country varchar(100) not null default 'India',
  visibility_status varchar(20) not null default 'visible',
  profile_media_id uuid,
  profile_completeness smallint not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint profiles_display_name_ck check (char_length(btrim(display_name)) between 1 and 80),
  constraint profiles_handle_ck check (handle ~ '^[a-z0-9_]{3,40}$'),
  constraint profiles_bio_ck check (bio is null or char_length(bio) <= 1000),
  constraint profiles_visibility_ck check (visibility_status in ('visible','hidden')),
  constraint profiles_completeness_ck check (profile_completeness between 0 and 100),
  constraint profiles_deleted_time_ck check (deleted_at is null or deleted_at >= created_at)
);
create unique index profiles_handle_ci_uq on core.profiles(lower(handle));
create index profiles_discovery_ix on core.profiles(visibility_status, country, state, city) where deleted_at is null;

create table core.user_interests (
  user_id uuid not null references core.users(user_id) on delete restrict,
  interest_id bigint not null references core.interests(id) on delete restrict,
  is_primary boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, interest_id)
);
create unique index user_interests_one_primary_uq on core.user_interests(user_id) where is_primary;
create index user_interests_interest_ix on core.user_interests(interest_id);

create table core.profile_prompts (
  id bigint generated always as identity primary key,
  user_id uuid not null references core.users(user_id) on delete restrict,
  prompt_code varchar(60) not null references core.prompt_catalogue(prompt_code) on delete restrict,
  answer jsonb not null,
  status varchar(20) not null default 'active',
  block_prompt_code varchar(80),
  supersedes_prompt_id bigint,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint profile_prompts_id_user_uq unique (id, user_id),
  constraint profile_prompts_answer_object_ck check (jsonb_typeof(answer) = 'object' and answer ? 'version'),
  constraint profile_prompts_status_ck check (status in ('active','hidden','removed')),
  constraint profile_prompts_block_ck check (
    (status = 'removed' and block_prompt_code is not null)
    or (status <> 'removed' and block_prompt_code is null)),
  constraint profile_prompts_supersedes_fk foreign key (supersedes_prompt_id) references core.profile_prompts(id) on delete restrict,
  constraint profile_prompts_no_self_cycle_ck check (supersedes_prompt_id is null or supersedes_prompt_id <> id)
);
create unique index profile_prompts_one_active_uq on core.profile_prompts(user_id, prompt_code) where status = 'active';
create index profile_prompts_user_created_ix on core.profile_prompts(user_id, created_at desc);

create table core.notification_preferences (
  user_id uuid primary key references core.users(user_id) on delete restrict,
  in_app_enabled boolean not null default true,
  push_enabled boolean not null default false,
  email_enabled boolean not null default false,
  marketing_enabled boolean not null default false,
  marketing_consent_at timestamptz,
  quiet_hours_start time,
  quiet_hours_end time,
  quiet_hours_timezone varchar(64),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint notification_preferences_marketing_ck check (
    (marketing_enabled and marketing_consent_at is not null)
    or (not marketing_enabled)),
  constraint notification_preferences_quiet_pair_ck check ((quiet_hours_start is null) = (quiet_hours_end is null)),
  constraint notification_preferences_quiet_tz_ck check (
    (quiet_hours_start is null and quiet_hours_timezone is null)
    or (quiet_hours_start is not null and quiet_hours_timezone is not null))
);

create table core.user_languages (
  user_id uuid not null references core.users(user_id) on delete restrict,
  language_id bigint not null references core.interests(id) on delete restrict,
  proficiency_level text not null,
  learning_intent text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, language_id),
  constraint user_languages_proficiency_ck check (proficiency_level in ('beginner','intermediate','advanced','native')),
  constraint user_languages_intent_ck check (learning_intent is null or learning_intent in ('want_to_learn','willing_to_teach','conversational_practice','cultural_interest','language_exchange'))
);
create index user_languages_language_ix on core.user_languages(language_id);

comment on column core.profiles.profile_media_id is 'UUID FK added after core.profile_media is created.';
comment on column core.profile_prompts.answer is 'Versioned JSON object. Text answers use {version,response}; key_value answers use a prompt-specific object contract.';
