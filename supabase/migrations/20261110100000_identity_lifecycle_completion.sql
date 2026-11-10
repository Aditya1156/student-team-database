-- Complete the production identity lifecycle: policy provenance, verification
-- transition times, OTP controls, account linking, and revocable sessions.

create table core.policy_versions (
  consent_type text not null,
  policy_version text not null,
  content_sha256 bytea not null,
  document_uri text not null,
  published_at timestamptz not null,
  effective_at timestamptz not null,
  retired_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  primary key (consent_type,policy_version),
  constraint policy_versions_type_ck check (consent_type in ('terms_of_service','privacy_notice','kyc_verification','marketing')),
  constraint policy_versions_version_ck check (policy_version ~ '^v[0-9]{1,3}\.[0-9]{1,3}$'),
  constraint policy_versions_hash_ck check (octet_length(content_sha256)=32),
  constraint policy_versions_uri_ck check (document_uri ~ '^https://'),
  constraint policy_versions_times_ck check (effective_at>=published_at and (retired_at is null or retired_at>effective_at))
);

insert into core.policy_versions(consent_type,policy_version,content_sha256,document_uri,published_at,effective_at)
select t,v,extensions.digest('synthetic-review-policy:'||t||':'||v,'sha256'),
       'https://policies.example.test/'||t||'/'||v,
       timestamptz '2026-01-01 00:00:00+00',timestamptz '2026-01-15 00:00:00+00'
from (values
  ('terms_of_service','v1.0'),('terms_of_service','v1.1'),
  ('privacy_notice','v1.0'),('privacy_notice','v1.1'),
  ('kyc_verification','v1.0'),('marketing','v1.0')
) p(t,v);

alter table core.user_consents
  add constraint user_consents_policy_fk foreign key(consent_type,policy_version)
  references core.policy_versions(consent_type,policy_version) on delete restrict;

alter table core.user_verifications
  add column aadhaar_started_at timestamptz,
  add column aadhaar_failed_at timestamptz,
  add column aadhaar_review_requested_at timestamptz,
  add column pan_started_at timestamptz,
  add column pan_failed_at timestamptz,
  add column pan_review_requested_at timestamptz;

update core.user_verifications set
  aadhaar_started_at=case when aadhaar_status<>'not_started' then created_at end,
  aadhaar_failed_at=case when aadhaar_status='failed' then updated_at end,
  aadhaar_review_requested_at=case when aadhaar_status='review_required' then updated_at end,
  pan_started_at=case when pan_status<>'not_started' then created_at end,
  pan_failed_at=case when pan_status='failed' then updated_at end,
  pan_review_requested_at=case when pan_status='review_required' then updated_at end;

alter table core.user_verifications
  add constraint uv_aadhaar_transition_times_ck check (
    (aadhaar_status='not_started' and aadhaar_started_at is null and aadhaar_failed_at is null and aadhaar_review_requested_at is null)
    or (aadhaar_status='failed' and aadhaar_started_at is not null and aadhaar_failed_at is not null and aadhaar_review_requested_at is null)
    or (aadhaar_status='review_required' and aadhaar_started_at is not null and aadhaar_failed_at is null and aadhaar_review_requested_at is not null)
    or (aadhaar_status in ('pending','verified') and aadhaar_started_at is not null and aadhaar_failed_at is null and aadhaar_review_requested_at is null)),
  add constraint uv_pan_transition_times_ck check (
    (pan_status='not_started' and pan_started_at is null and pan_failed_at is null and pan_review_requested_at is null)
    or (pan_status='failed' and pan_started_at is not null and pan_failed_at is not null and pan_review_requested_at is null)
    or (pan_status='review_required' and pan_started_at is not null and pan_failed_at is null and pan_review_requested_at is not null)
    or (pan_status in ('pending','verified') and pan_started_at is not null and pan_failed_at is null and pan_review_requested_at is null));

create or replace function core.user_verifications_before_write()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='UPDATE' and new.user_id<>old.user_id then raise exception 'verification owner is immutable' using errcode='23514'; end if;
  if new.aadhaar_status<>'not_started' then
    if new.email_status<>'verified' or new.phone_status<>'verified' then raise exception 'contacts must be verified before KYC starts' using errcode='23514'; end if;
    if not exists(select 1 from core.user_consents_current c where c.user_id=new.user_id and c.consent_type='kyc_verification' and c.decision='granted') then raise exception 'KYC consent is required' using errcode='23514'; end if;
  end if;
  if new.pan_status<>'not_started' and new.aadhaar_status='not_started' then raise exception 'Aadhaar verification must start before PAN verification' using errcode='23514'; end if;
  if new.aadhaar_attempt_count=3 and new.aadhaar_status='pending' then new.aadhaar_status:='failed'; new.aadhaar_failure_reason:='too_many_attempts'; end if;
  if new.pan_attempt_count=3 and new.pan_status='pending' then new.pan_status:='failed'; new.pan_failure_reason:='too_many_attempts'; end if;

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

alter table core.user_otp_challenges
  add column resend_count smallint not null default 0,
  add column resend_window_started_at timestamptz,
  add column last_attempt_at timestamptz,
  add column locked_at timestamptz,
  add column recovery_request_id uuid;

update core.user_otp_challenges
set resend_window_started_at=sent_at,
    locked_at=case when status='locked' then updated_at end;

alter table core.user_otp_challenges
  alter column resend_window_started_at set not null,
  add constraint uoc_resend_count_ck check(resend_count between 0 and 5),
  add constraint uoc_attempt_time_ck check(last_attempt_at is null or last_attempt_at>=sent_at),
  add constraint uoc_locked_time_ck check((status='locked')=(locked_at is not null)),
  add constraint uoc_recovery_request_ck check((purpose='account_recovery') or recovery_request_id is null);

create or replace function core.user_otp_challenges_before_write()
returns trigger language plpgsql set search_path='' as $$
declare v_version integer;
begin
  select contact_version into v_version from core.user_contacts where user_id=new.user_id;
  if v_version is null or new.contact_version<>v_version then raise exception 'OTP contact_version is stale' using errcode='23514'; end if;
  if tg_op='INSERT' then
    new.sent_at:=clock_timestamp(); new.last_sent_at:=new.sent_at; new.expires_at:=new.sent_at+interval '10 minutes';
    new.resend_count:=0; new.resend_window_started_at:=new.sent_at;
  elsif new.user_id<>old.user_id or new.channel<>old.channel or new.purpose<>old.purpose
     or new.contact_version<>old.contact_version or new.destination_hash is distinct from old.destination_hash
     or (new.otp_hmac<>old.otp_hmac and coalesce(current_setting('app.otp_secret_rotation_authorized',true),'')<>'on') then
    raise exception 'OTP identity and hashes are immutable' using errcode='23514';
  end if;
  new.locked_at:=case when new.status='locked' then coalesce(new.locked_at,clock_timestamp()) else null end;
  new.updated_at:=clock_timestamp(); return new;
end $$;

create table core.auth_sessions (
  session_id uuid primary key default extensions.gen_random_uuid(),
  session_family_id uuid not null default extensions.gen_random_uuid(),
  user_id uuid not null references core.users(user_id) on delete restrict,
  auth_identity_id bigint not null references core.auth_identities(id) on delete restrict,
  refresh_token_hash bytea not null,
  refresh_token_version integer not null default 1,
  device_id varchar(100),
  ip_hmac bytea,
  user_agent_hash bytea,
  status text not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  idle_expires_at timestamptz not null,
  revoked_at timestamptz,
  revocation_reason text,
  replaced_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint auth_sessions_token_uq unique(refresh_token_hash),
  constraint auth_sessions_token_hash_ck check(octet_length(refresh_token_hash)=32),
  constraint auth_sessions_ip_hash_ck check(ip_hmac is null or octet_length(ip_hmac)=32),
  constraint auth_sessions_agent_hash_ck check(user_agent_hash is null or octet_length(user_agent_hash)=32),
  constraint auth_sessions_version_ck check(refresh_token_version>=1),
  constraint auth_sessions_status_ck check(status in ('active','revoked','expired','compromised')),
  constraint auth_sessions_time_ck check(expires_at>created_at and idle_expires_at>created_at and last_seen_at>=created_at),
  constraint auth_sessions_revocation_ck check(
    (status='active' and revoked_at is null and revocation_reason is null)
    or (status<>'active' and revoked_at is not null and revocation_reason is not null))
);
create index auth_sessions_user_status_ix on core.auth_sessions(user_id,status,expires_at);
create index auth_sessions_family_ix on core.auth_sessions(session_family_id);

create or replace function core.audit_identity_event()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_action text; v_old jsonb; v_new jsonb;
begin
  if tg_table_name='user_verifications' then
    v_user:=new.user_id; v_action:='identity_verification_changed';
    v_old:=case when tg_op='UPDATE' then jsonb_build_object('email_status',old.email_status,'phone_status',old.phone_status,'aadhaar_status',old.aadhaar_status,'pan_status',old.pan_status) end;
    v_new:=jsonb_build_object('email_status',new.email_status,'phone_status',new.phone_status,'aadhaar_status',new.aadhaar_status,'pan_status',new.pan_status);
  elsif tg_table_name='auth_identities' then
    v_user:=new.user_id; v_action:='auth_identity_changed';
    v_old:=case when tg_op='UPDATE' then jsonb_build_object('provider',old.provider,'status',old.status) end;
    v_new:=jsonb_build_object('provider',new.provider,'status',new.status);
  elsif tg_table_name='user_contacts' then
    v_user:=new.user_id; v_action:='contact_changed';
    v_old:=case when tg_op='UPDATE' then jsonb_build_object('contact_version',old.contact_version) end;
    v_new:=jsonb_build_object('contact_version',new.contact_version);
  elsif tg_table_name='user_otp_challenges' then
    v_user:=new.user_id; v_action:='otp_challenge_changed';
    v_old:=case when tg_op='UPDATE' then jsonb_build_object('channel',old.channel,'purpose',old.purpose,'status',old.status,'attempt_count',old.attempt_count,'resend_count',old.resend_count) end;
    v_new:=jsonb_build_object('channel',new.channel,'purpose',new.purpose,'status',new.status,'attempt_count',new.attempt_count,'resend_count',new.resend_count);
  elsif tg_table_name='user_consents' then
    v_user:=new.user_id; v_action:='consent_recorded'; v_old:=null;
    v_new:=jsonb_build_object('consent_type',new.consent_type,'policy_version',new.policy_version,'decision',new.decision,'source',new.source);
  elsif tg_table_name='auth_sessions' then
    v_user:=new.user_id; v_action:='auth_session_changed';
    v_old:=case when tg_op='UPDATE' then jsonb_build_object('status',old.status,'token_version',old.refresh_token_version) end;
    v_new:=jsonb_build_object('status',new.status,'token_version',new.refresh_token_version);
  end if;
  insert into audit.audit_product_event(actor_type,action_type,event_category,target_user_id,event_status,event_source,data_modified,previous_value,new_value,metadata)
  values('system',v_action,'identity',v_user,'success','system',true,v_old,v_new,
         jsonb_build_object('database_role',current_user,'trigger_operation',tg_op));
  return new;
end $$;

create trigger user_verifications_audit_trg after insert or update on core.user_verifications for each row execute function core.audit_identity_event();
create trigger auth_identities_audit_trg after insert or update on core.auth_identities for each row execute function core.audit_identity_event();
create trigger user_contacts_audit_trg after insert or update on core.user_contacts for each row execute function core.audit_identity_event();
create trigger user_otp_challenges_audit_trg after insert or update on core.user_otp_challenges for each row execute function core.audit_identity_event();
create trigger user_consents_audit_trg after insert on core.user_consents for each row execute function core.audit_identity_event();
create trigger auth_sessions_audit_trg after insert or update on core.auth_sessions for each row execute function core.audit_identity_event();
create trigger policy_versions_append_only_trg before update or delete on core.policy_versions for each row execute function core.append_only_guard();

create or replace function core.register_user(
  p_provider text,p_provider_subject text,p_email text,p_phone text,p_timezone text,p_date_of_birth date,p_gender text,
  p_terms_version text,p_privacy_version text,p_otp_hmac bytea default null,p_destination_hash bytea default null,p_request_id text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_channel text;
begin
  if p_provider not in ('email_otp','phone_otp','google','apple') then raise exception 'Unsupported provider' using errcode='23514'; end if;
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
  return v_user;
end $$;

create or replace function core.link_auth_identity(p_user_id uuid,p_provider text,p_provider_subject text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_id bigint;
begin
  if not exists(select 1 from core.users where user_id=p_user_id and account_status<>'deleted') then raise exception 'User is unavailable' using errcode='23514'; end if;
  insert into core.auth_identities(user_id,provider,provider_subject) values(p_user_id,p_provider,p_provider_subject) returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'Identity is already linked' using errcode='23505';
end $$;

create or replace function core.resend_otp_challenge(p_challenge_id bigint,p_new_otp_hmac bytea)
returns void language plpgsql security definer set search_path='' as $$
declare r core.user_otp_challenges%rowtype; v_now timestamptz:=clock_timestamp();
begin
  if p_new_otp_hmac is null or octet_length(p_new_otp_hmac)<>32 then raise exception 'A 32-byte OTP HMAC is required' using errcode='23514'; end if;
  select * into r from core.user_otp_challenges where id=p_challenge_id for update;
  if not found or r.status<>'pending' then raise exception 'OTP challenge is not pending' using errcode='23514'; end if;
  if v_now<r.last_sent_at+interval '60 seconds' then raise exception 'OTP resend cooldown is active' using errcode='P0001'; end if;
  if v_now>=r.resend_window_started_at+interval '1 hour' then r.resend_count:=0; r.resend_window_started_at:=v_now; end if;
  if r.resend_count>=5 then raise exception 'OTP resend limit exceeded' using errcode='P0001'; end if;
  perform set_config('app.otp_secret_rotation_authorized','on',true);
  update core.user_otp_challenges set otp_hmac=p_new_otp_hmac,last_sent_at=v_now,expires_at=v_now+interval '10 minutes',
    resend_count=r.resend_count+1,resend_window_started_at=r.resend_window_started_at where id=p_challenge_id;
end $$;

create or replace function core.verify_otp_challenge(p_challenge_id bigint,p_submitted_hmac bytea)
returns text language plpgsql security definer set search_path='' as $$
declare r core.user_otp_challenges%rowtype; v_now timestamptz:=clock_timestamp(); v_status text; v_provider text;
begin
  select * into r from core.user_otp_challenges where id=p_challenge_id for update;
  if not found then raise exception 'Unknown OTP challenge' using errcode='P0002'; end if;
  if r.status<>'pending' then return r.status; end if;
  if r.expires_at<=v_now then update core.user_otp_challenges set status='expired',last_attempt_at=v_now where id=r.id; return 'expired'; end if;
  if p_submitted_hmac is null or r.otp_hmac<>p_submitted_hmac then
    v_status:=case when r.attempt_count+1>=5 then 'locked' else 'pending' end;
    update core.user_otp_challenges set attempt_count=r.attempt_count+1,status=v_status,last_attempt_at=v_now where id=r.id;
    return v_status;
  end if;
  update core.user_otp_challenges set status='verified',verified_at=v_now,last_attempt_at=v_now where id=r.id;
  if r.channel='email' then update core.user_verifications set email_status='verified',email_verified_at=v_now where user_id=r.user_id;
  else update core.user_verifications set phone_status='verified',phone_verified_at=v_now where user_id=r.user_id; end if;
  if r.purpose='signup' then
    v_provider:=case r.channel when 'email' then 'email_otp' else 'phone_otp' end;
    insert into core.auth_identities(user_id,provider,provider_subject) values(r.user_id,v_provider,r.user_id::text) on conflict(provider,provider_subject) do nothing;
  elsif r.purpose='account_recovery' then
    update core.auth_sessions set status='revoked',revoked_at=v_now,revocation_reason='account_recovery',updated_at=v_now where user_id=r.user_id and status='active';
  end if;
  return 'verified';
end $$;

create or replace function core.issue_auth_session(p_user_id uuid,p_auth_identity_id bigint,p_refresh_token_hash bytea,p_device_id text default null,p_ip_hmac bytea default null,p_user_agent_hash bytea default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_session uuid;
begin
  if octet_length(p_refresh_token_hash)<>32 then raise exception 'Refresh token hash must be 32 bytes' using errcode='23514'; end if;
  if not core.user_can_login(p_user_id) then raise exception 'User cannot log in' using errcode='42501'; end if;
  if not exists(select 1 from core.auth_identities where id=p_auth_identity_id and user_id=p_user_id and status='active') then raise exception 'Active identity is required' using errcode='42501'; end if;
  insert into core.auth_sessions(user_id,auth_identity_id,refresh_token_hash,device_id,ip_hmac,user_agent_hash,expires_at,idle_expires_at)
  values(p_user_id,p_auth_identity_id,p_refresh_token_hash,p_device_id,p_ip_hmac,p_user_agent_hash,clock_timestamp()+interval '30 days',clock_timestamp()+interval '7 days') returning session_id into v_session;
  return v_session;
end $$;

create or replace function core.rotate_refresh_token(p_session_id uuid,p_current_hash bytea,p_new_hash bytea)
returns text language plpgsql security definer set search_path='' as $$
declare r core.auth_sessions%rowtype; v_now timestamptz:=clock_timestamp();
begin
  select * into r from core.auth_sessions where session_id=p_session_id for update;
  if not found then raise exception 'Unknown session' using errcode='P0002'; end if;
  if r.status<>'active' or r.expires_at<=v_now or r.idle_expires_at<=v_now then raise exception 'Session is not active' using errcode='42501'; end if;
  if r.refresh_token_hash<>p_current_hash then
    update core.auth_sessions set status='compromised',revoked_at=v_now,revocation_reason='refresh_token_reuse',updated_at=v_now where session_family_id=r.session_family_id and status='active';
    return 'compromised';
  end if;
  if octet_length(p_new_hash)<>32 then raise exception 'Refresh token hash must be 32 bytes' using errcode='23514'; end if;
  update core.auth_sessions set refresh_token_hash=p_new_hash,refresh_token_version=refresh_token_version+1,last_seen_at=v_now,
    idle_expires_at=least(expires_at,v_now+interval '7 days'),replaced_at=v_now,updated_at=v_now where session_id=p_session_id;
  return 'rotated';
end $$;

create or replace function core.revoke_auth_session(p_session_id uuid,p_reason text default 'user_logout')
returns void language sql security definer set search_path='' as $$
  update core.auth_sessions set status='revoked',revoked_at=clock_timestamp(),revocation_reason=coalesce(p_reason,'user_logout'),updated_at=clock_timestamp()
  where session_id=p_session_id and status='active';
$$;

create or replace function core.revoke_all_user_sessions(p_user_id uuid,p_reason text default 'security_event')
returns bigint language plpgsql security definer set search_path='' as $$
declare v_count bigint;
begin
  update core.auth_sessions set status='revoked',revoked_at=clock_timestamp(),revocation_reason=p_reason,updated_at=clock_timestamp()
  where user_id=p_user_id and status='active'; get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function core.validate_auth_session(p_refresh_token_hash bytea)
returns uuid language sql stable security definer set search_path='' as $$
  select s.user_id from core.auth_sessions s join core.users u using(user_id) join core.auth_identities i on i.id=s.auth_identity_id
  where s.refresh_token_hash=p_refresh_token_hash and s.status='active' and s.expires_at>clock_timestamp()
    and s.idle_expires_at>clock_timestamp() and u.account_status in ('limited','active') and i.status='active';
$$;

create or replace function core.revoke_sessions_for_lifecycle()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.account_status in ('suspended','deactivated','deletion_pending','deleted') and new.account_status is distinct from old.account_status then
    perform core.revoke_all_user_sessions(new.user_id,'account_'||new.account_status);
  end if; return new;
end $$;
create trigger users_revoke_sessions_trg after update of account_status on core.users for each row execute function core.revoke_sessions_for_lifecycle();

create or replace function core.revoke_sessions_for_identity()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status='active' and new.status<>'active' then
    update core.auth_sessions set status='revoked',revoked_at=clock_timestamp(),revocation_reason='identity_'||new.status,updated_at=clock_timestamp()
    where auth_identity_id=new.id and status='active';
  end if; return new;
end $$;
create trigger auth_identities_revoke_sessions_trg after update of status on core.auth_identities for each row execute function core.revoke_sessions_for_identity();

alter table core.policy_versions enable row level security;
alter table core.auth_sessions enable row level security;
revoke all on core.policy_versions,core.auth_sessions from anon,authenticated;
grant all on core.policy_versions,core.auth_sessions to service_role;
grant usage,select on all sequences in schema core to service_role;
revoke all on function core.register_user(text,text,text,text,text,date,text,text,text,bytea,bytea,text),
  core.link_auth_identity(uuid,text,text),core.resend_otp_challenge(bigint,bytea),core.verify_otp_challenge(bigint,bytea),
  core.issue_auth_session(uuid,bigint,bytea,text,bytea,bytea),core.rotate_refresh_token(uuid,bytea,bytea),
  core.revoke_auth_session(uuid,text),core.revoke_all_user_sessions(uuid,text),core.validate_auth_session(bytea)
from public,anon,authenticated;
grant execute on function core.register_user(text,text,text,text,text,date,text,text,text,bytea,bytea,text),
  core.link_auth_identity(uuid,text,text),core.resend_otp_challenge(bigint,bytea),core.verify_otp_challenge(bigint,bytea),
  core.issue_auth_session(uuid,bigint,bytea,text,bytea,bytea),core.rotate_refresh_token(uuid,bytea,bytea),
  core.revoke_auth_session(uuid,text),core.revoke_all_user_sessions(uuid,text),core.validate_auth_session(bytea)
to service_role;

create or replace view review.policy_version_inventory as
select consent_type,policy_version,encode(content_sha256,'hex') content_sha256,document_uri,published_at,effective_at,retired_at
from core.policy_versions;
grant select on review.policy_version_inventory to student_database_reviewer;

comment on table core.auth_sessions is 'Only SHA-256/HMAC refresh-token digests are stored; plaintext access and refresh tokens must never be persisted.';
comment on function core.verify_otp_challenge(bigint,bytea) is 'Accepts a backend-produced OTP HMAC, never a plaintext OTP.';
comment on table core.policy_versions is 'Immutable policy provenance used by append-only user consent events.';

-- Rebuild the complete reviewer count view with the two new identity relations included.
drop view review.team_module_counts;
create view review.team_module_counts as
select 'identity'::text module,'users'::text relation,count(*)::bigint row_count from core.users
union all select 'identity','auth_identities',count(*) from core.auth_identities
union all select 'identity','auth_sessions',count(*) from core.auth_sessions
union all select 'identity','policy_versions',count(*) from core.policy_versions
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
grant select on review.team_module_counts to student_database_reviewer;
