-- Resolve the validated Aditya findings from the 2026-11-11 gap review.
-- The migration adds database-level ownership and time guarantees, formalizes
-- the existing one-row session rotation model, strengthens KYC/age state, and
-- gives the immutable policy catalogue a controlled non-overlapping lifecycle.

create extension if not exists btree_gist with schema extensions;

-- Step 1: a session's identity must belong to the same application user.
alter table core.auth_identities
  add constraint auth_identities_id_user_uq unique(id,user_id);

alter table core.auth_sessions
  add constraint auth_sessions_identity_owner_fk
    foreign key(auth_identity_id,user_id)
    references core.auth_identities(id,user_id)
    on delete restrict,
  add constraint auth_sessions_idle_within_absolute_ck
    check(idle_expires_at<=expires_at and last_seen_at<=expires_at),
  add constraint auth_sessions_rotation_state_ck
    check(
      (refresh_token_version=1 and replaced_at is null)
      or (refresh_token_version>1 and replaced_at is not null)
    );

create index auth_sessions_identity_owner_ix
  on core.auth_sessions(auth_identity_id,user_id,status);

comment on column core.auth_sessions.session_family_id is
  'Stable lineage identifier reserved for family-wide compromise handling. The current model keeps one row per login session and rotates the digest in that row.';
comment on column core.auth_sessions.replaced_at is
  'Time the current row most recently replaced its refresh-token digest; NULL while refresh_token_version=1.';
comment on function core.rotate_refresh_token(uuid,bytea,bytea) is
  'One-row rotation model: lock the session, compare the current digest, replace it and increment the version; a mismatch marks the session family compromised.';

-- Step 2: eligible/ineligible decisions require verification evidence.
alter table core.users drop constraint users_age_consistency_ck;
alter table core.users
  add constraint users_age_consistency_ck check(
    (age_eligibility_status='unknown' and age_verified_at is null)
    or (age_eligibility_status in ('eligible','ineligible') and age_verified_at is not null)
    or age_eligibility_status='review_required'
  );

-- Step 3: policy versions have non-overlapping effective periods. The original
-- fixture gave v1.0 and v1.1 identical dates; correct that synthetic timeline
-- so existing v1.0/v1.1 consent events remain chronologically valid.
drop trigger policy_versions_append_only_trg on core.policy_versions;

update core.policy_versions
set published_at=timestamptz '2026-11-09 14:00:00+00',
    effective_at=timestamptz '2026-11-09 14:27:40+00'
where consent_type in ('terms_of_service','privacy_notice')
  and policy_version='v1.1';

update core.policy_versions
set retired_at=timestamptz '2026-11-09 14:27:40+00'
where consent_type in ('terms_of_service','privacy_notice')
  and policy_version='v1.0';

alter table core.policy_versions
  add constraint policy_versions_no_effective_overlap_excl
  exclude using gist(
    consent_type with =,
    tstzrange(effective_at,retired_at,'[)') with &&
  );

create or replace function core.policy_versions_before_mutation()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    raise exception 'policy versions cannot be deleted' using errcode='42501';
  end if;
  if coalesce(pg_catalog.current_setting('app.policy_retirement_authorized',true),'')<>'on' then
    raise exception 'policy versions are immutable; use the controlled policy lifecycle functions' using errcode='42501';
  end if;
  if new.consent_type is distinct from old.consent_type
     or new.policy_version is distinct from old.policy_version
     or new.content_sha256 is distinct from old.content_sha256
     or new.document_uri is distinct from old.document_uri
     or new.published_at is distinct from old.published_at
     or new.effective_at is distinct from old.effective_at
     or new.created_at is distinct from old.created_at
     or old.retired_at is not null
     or new.retired_at is null
     or new.retired_at<=old.effective_at then
    raise exception 'only the first valid retirement timestamp may be recorded' using errcode='42501';
  end if;
  return new;
end $$;

create trigger policy_versions_append_only_trg
before update or delete on core.policy_versions
for each row execute function core.policy_versions_before_mutation();

create or replace function core.publish_policy_version(
  p_consent_type text,
  p_policy_version text,
  p_content_sha256 bytea,
  p_document_uri text,
  p_published_at timestamptz,
  p_effective_at timestamptz
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_current core.policy_versions%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('policy:'||p_consent_type));
  select * into v_current
  from core.policy_versions
  where consent_type=p_consent_type
    and effective_at<=p_effective_at
    and (retired_at is null or retired_at>p_effective_at)
  order by effective_at desc
  limit 1
  for update;

  if found then
    if p_effective_at<=v_current.effective_at then
      raise exception 'new policy must become effective after the current version' using errcode='23514';
    end if;
    perform pg_catalog.set_config('app.policy_retirement_authorized','on',true);
    update core.policy_versions
    set retired_at=p_effective_at
    where consent_type=v_current.consent_type and policy_version=v_current.policy_version;
  end if;

  insert into core.policy_versions(
    consent_type,policy_version,content_sha256,document_uri,published_at,effective_at
  ) values(
    p_consent_type,p_policy_version,p_content_sha256,p_document_uri,p_published_at,p_effective_at
  );
end $$;

create or replace function core.retire_policy_version(
  p_consent_type text,
  p_policy_version text,
  p_retired_at timestamptz
)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('policy:'||p_consent_type));
  perform pg_catalog.set_config('app.policy_retirement_authorized','on',true);
  update core.policy_versions
  set retired_at=p_retired_at
  where consent_type=p_consent_type
    and policy_version=p_policy_version
    and retired_at is null;
  if not found then raise exception 'active policy version not found' using errcode='P0002'; end if;
end $$;

create or replace function core.policy_version_is_effective(
  p_consent_type text,
  p_policy_version text,
  p_at timestamptz default current_timestamp
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1 from core.policy_versions p
    where p.consent_type=p_consent_type
      and p.policy_version=p_policy_version
      and p.effective_at<=p_at
      and (p.retired_at is null or p.retired_at>p_at)
  );
$$;

create or replace function core.user_has_current_consent(
  p_user_id uuid,
  p_consent_type text,
  p_at timestamptz default current_timestamp
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from core.user_consents_current c
    join core.policy_versions p
      on p.consent_type=c.consent_type and p.policy_version=c.policy_version
    where c.user_id=p_user_id
      and c.consent_type=p_consent_type
      and c.decision='granted'
      and p.effective_at<=p_at
      and (p.retired_at is null or p.retired_at>p_at)
  );
$$;

create or replace view review.current_policy_versions as
select consent_type,policy_version,encode(content_sha256,'hex') content_sha256,
       document_uri,published_at,effective_at,retired_at
from core.policy_versions
where effective_at<=current_timestamp
  and (retired_at is null or retired_at>current_timestamp);

grant select on review.current_policy_versions to student_database_reviewer;

-- Step 4: make main access depend on currently effective required consent.
create or replace function core.user_access_ready(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists (
    select 1
    from core.users u
    join core.user_verifications v using (user_id)
    where u.user_id=p_user_id
      and v.email_status='verified' and v.phone_status='verified'
      and v.aadhaar_status='verified' and v.pan_status='verified'
      and v.age_eligible is true
      and u.date_of_birth is not null
      and u.date_of_birth<=current_date-interval '18 years'
      and core.user_has_current_consent(p_user_id,'terms_of_service')
      and core.user_has_current_consent(p_user_id,'privacy_notice')
      and core.user_has_current_consent(p_user_id,'kyc_verification')
  );
$$;

-- Step 5: define KYC transitions and protect completed identity evidence.
create or replace function core.user_verifications_before_write()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if tg_op='UPDATE' and new.user_id<>old.user_id then
    raise exception 'verification owner is immutable' using errcode='23514';
  end if;

  if tg_op='UPDATE' then
    if old.aadhaar_status='not_started' and new.aadhaar_status not in ('not_started','pending') then
      raise exception 'Aadhaar must move from not_started to pending' using errcode='23514';
    elsif old.aadhaar_status='pending' and new.aadhaar_status not in ('pending','verified','failed','review_required') then
      raise exception 'Invalid Aadhaar pending transition' using errcode='23514';
    elsif old.aadhaar_status='failed' and new.aadhaar_status not in ('failed','pending') then
      raise exception 'Failed Aadhaar may only remain failed or restart as pending' using errcode='23514';
    elsif old.aadhaar_status='review_required' and new.aadhaar_status not in ('review_required','pending','verified','failed') then
      raise exception 'Invalid Aadhaar review transition' using errcode='23514';
    elsif old.aadhaar_status='verified' and new.aadhaar_status<>'verified' then
      raise exception 'Verified Aadhaar cannot be reset without a future controlled re-verification workflow' using errcode='23514';
    end if;

    if old.pan_status='not_started' and new.pan_status not in ('not_started','pending') then
      raise exception 'PAN must move from not_started to pending' using errcode='23514';
    elsif old.pan_status='pending' and new.pan_status not in ('pending','verified','failed','review_required') then
      raise exception 'Invalid PAN pending transition' using errcode='23514';
    elsif old.pan_status='failed' and new.pan_status not in ('failed','pending') then
      raise exception 'Failed PAN may only remain failed or restart as pending' using errcode='23514';
    elsif old.pan_status='review_required' and new.pan_status not in ('review_required','pending','verified','failed') then
      raise exception 'Invalid PAN review transition' using errcode='23514';
    elsif old.pan_status='verified' and new.pan_status<>'verified' then
      raise exception 'Verified PAN cannot be reset without a future controlled re-verification workflow' using errcode='23514';
    end if;

    if old.aadhaar_status='verified' and (
      new.aadhaar_verified_at is distinct from old.aadhaar_verified_at
      or new.aadhaar_masked is distinct from old.aadhaar_masked
      or new.aadhaar_provider is distinct from old.aadhaar_provider
      or new.aadhaar_provider_ref is distinct from old.aadhaar_provider_ref
      or new.aadhaar_hash is distinct from old.aadhaar_hash
      or new.age_eligible is distinct from old.age_eligible
    ) then raise exception 'Verified Aadhaar evidence is immutable' using errcode='23514'; end if;

    if old.pan_status='verified' and (
      new.pan_verified_at is distinct from old.pan_verified_at
      or new.pan_masked is distinct from old.pan_masked
      or new.pan_provider is distinct from old.pan_provider
      or new.pan_provider_ref is distinct from old.pan_provider_ref
      or new.pan_hash is distinct from old.pan_hash
    ) then raise exception 'Verified PAN evidence is immutable' using errcode='23514'; end if;
  end if;

  if new.aadhaar_status<>'not_started' then
    if new.aadhaar_provider is null or new.aadhaar_provider_ref is null then
      raise exception 'Aadhaar provider and provider reference are required after verification starts' using errcode='23514';
    end if;
    if new.email_status<>'verified' or new.phone_status<>'verified' then
      raise exception 'contacts must be verified before KYC starts' using errcode='23514';
    end if;
    if not core.user_has_current_consent(new.user_id,'kyc_verification') then
      raise exception 'current KYC consent is required' using errcode='23514';
    end if;
  end if;
  if new.pan_status<>'not_started' then
    if new.pan_provider is null or new.pan_provider_ref is null then
      raise exception 'PAN provider and provider reference are required after verification starts' using errcode='23514';
    end if;
    if new.aadhaar_status='not_started' then
      raise exception 'Aadhaar verification must start before PAN verification' using errcode='23514';
    end if;
  end if;
  if new.aadhaar_attempt_count=3 and new.aadhaar_status='pending' then
    new.aadhaar_status:='failed'; new.aadhaar_failure_reason:='too_many_attempts';
  end if;
  if new.pan_attempt_count=3 and new.pan_status='pending' then
    new.pan_status:='failed'; new.pan_failure_reason:='too_many_attempts';
  end if;

  if new.aadhaar_status='not_started' then
    new.aadhaar_started_at:=null; new.aadhaar_failed_at:=null; new.aadhaar_review_requested_at:=null;
  else
    new.aadhaar_started_at:=coalesce(new.aadhaar_started_at,case when tg_op='UPDATE' then old.aadhaar_started_at end,clock_timestamp());
    new.aadhaar_failed_at:=case when new.aadhaar_status='failed' then coalesce(new.aadhaar_failed_at,clock_timestamp()) else null end;
    new.aadhaar_review_requested_at:=case when new.aadhaar_status='review_required' then coalesce(new.aadhaar_review_requested_at,clock_timestamp()) else null end;
  end if;
  if new.pan_status='not_started' then
    new.pan_started_at:=null; new.pan_failed_at:=null; new.pan_review_requested_at:=null;
  else
    new.pan_started_at:=coalesce(new.pan_started_at,case when tg_op='UPDATE' then old.pan_started_at end,clock_timestamp());
    new.pan_failed_at:=case when new.pan_status='failed' then coalesce(new.pan_failed_at,clock_timestamp()) else null end;
    new.pan_review_requested_at:=case when new.pan_status='review_required' then coalesce(new.pan_review_requested_at,clock_timestamp()) else null end;
  end if;
  new.updated_at:=clock_timestamp();
  return new;
end $$;

-- Registration may accept only currently effective Terms and Privacy versions.
create or replace function core.register_user(
  p_provider text,p_provider_subject text,p_email text,p_phone text,p_timezone text,p_date_of_birth date,p_gender text,
  p_terms_version text,p_privacy_version text,p_otp_hmac bytea default null,p_destination_hash bytea default null,p_request_id text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_channel text;
begin
  if p_provider not in ('email_otp','phone_otp','google','apple') then raise exception 'Unsupported provider' using errcode='23514'; end if;
  if not core.policy_version_is_effective('terms_of_service',p_terms_version)
     or not core.policy_version_is_effective('privacy_notice',p_privacy_version) then
    raise exception 'Current Terms and Privacy policy versions are required' using errcode='23514';
  end if;
  insert into core.users(timezone,date_of_birth,gender) values(p_timezone,p_date_of_birth,p_gender) returning user_id into v_user;
  insert into core.user_contacts(user_id,email,phone_number) values(v_user,p_email,p_phone);
  insert into core.user_consents(user_id,consent_type,policy_version,decision,source) values
    (v_user,'terms_of_service',p_terms_version,'granted','signup_flow'),
    (v_user,'privacy_notice',p_privacy_version,'granted','signup_flow');
  if p_provider in ('google','apple') then
    if nullif(btrim(p_provider_subject),'') is null then raise exception 'Provider subject is required' using errcode='23514'; end if;
    insert into core.auth_identities(user_id,provider,provider_subject) values(v_user,p_provider,p_provider_subject);
  else
    if p_otp_hmac is null or octet_length(p_otp_hmac)<>32 then raise exception 'A 32-byte OTP HMAC is required' using errcode='23514'; end if;
    v_channel:=case p_provider when 'email_otp' then 'email' else 'phone' end;
    insert into core.user_otp_challenges(user_id,channel,purpose,destination_hash,contact_version,otp_hmac)
    values(v_user,v_channel,'signup',p_destination_hash,1,p_otp_hmac);
  end if;
  insert into audit.audit_product_event(actor_type,action_type,event_category,target_user_id,request_id,event_status,event_source,data_modified,metadata)
  values('system','registration_started','authentication',v_user,p_request_id,'success','api',false,jsonb_build_object('provider',p_provider));
  return v_user;
end $$;

-- Step 6: focused FK/query-path indexes. PostgreSQL does not create these for
-- referencing columns automatically.
create index user_consents_policy_ix
  on core.user_consents(consent_type,policy_version);

comment on table core.user_contacts is
  'Stores only the current normalized contact. Raw previous email/phone values are intentionally not retained; version changes are audited without copying contact PII.';

revoke all on function core.publish_policy_version(text,text,bytea,text,timestamptz,timestamptz),
  core.retire_policy_version(text,text,timestamptz),
  core.policy_version_is_effective(text,text,timestamptz),
  core.user_has_current_consent(uuid,text,timestamptz)
from public,anon,authenticated;

grant execute on function core.publish_policy_version(text,text,bytea,text,timestamptz,timestamptz),
  core.retire_policy_version(text,text,timestamptz),
  core.policy_version_is_effective(text,text,timestamptz),
  core.user_has_current_consent(uuid,text,timestamptz)
to service_role;

revoke all on function core.register_user(text,text,text,text,text,date,text,text,text,bytea,bytea,text)
from public,anon,authenticated;
grant execute on function core.register_user(text,text,text,text,text,date,text,text,text,bytea,bytea,text)
to service_role;
