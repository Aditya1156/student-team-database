-- Transactional regression checks for the 2026-11-11 Aditya gap hardening.
-- Run through scripts/validate-aditya-gap-hardening.ps1 so all test rows roll back.

do $$
declare
  v_user uuid;
  v_other_user uuid;
  v_identity bigint;
  v_other_identity bigint;
  v_constraint_count integer;
begin
  select count(*) into v_constraint_count
  from pg_constraint
  where conrelid='core.auth_sessions'::regclass
    and conname in (
      'auth_sessions_identity_owner_fk',
      'auth_sessions_idle_within_absolute_ck',
      'auth_sessions_rotation_state_ck'
    );
  if v_constraint_count<>3 then raise exception 'Session hardening constraints are missing'; end if;

  if not core.policy_version_is_effective('terms_of_service','v1.1')
     or not core.policy_version_is_effective('privacy_notice','v1.1')
     or not core.policy_version_is_effective('kyc_verification','v1.0') then
    raise exception 'Current policy resolution failed';
  end if;
  if core.policy_version_is_effective('terms_of_service','v1.0') then
    raise exception 'Retired Terms v1.0 is still effective';
  end if;

  v_user:=core.register_user(
    'google','gap-contract-google-a','gap.contract.a@example.test','+919999991001',
    'Asia/Kolkata',date '1992-01-01','prefer_not_to_say','v1.1','v1.1',null,null,'gap-contract-a');
  v_other_user:=core.register_user(
    'google','gap-contract-google-b','gap.contract.b@example.test','+919999991002',
    'Asia/Kolkata',date '1993-01-01','prefer_not_to_say','v1.1','v1.1',null,null,'gap-contract-b');
  select id into v_identity from core.auth_identities where user_id=v_user and provider='google';
  select id into v_other_identity from core.auth_identities where user_id=v_other_user and provider='google';

  begin
    insert into core.auth_sessions(user_id,auth_identity_id,refresh_token_hash,expires_at,idle_expires_at)
    values(v_user,v_other_identity,extensions.digest('gap-owner-mismatch','sha256'),clock_timestamp()+interval '30 days',clock_timestamp()+interval '7 days');
    raise exception 'Mismatched session identity unexpectedly succeeded';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into core.auth_sessions(user_id,auth_identity_id,refresh_token_hash,expires_at,idle_expires_at)
    values(v_user,v_identity,extensions.digest('gap-idle-after-absolute','sha256'),clock_timestamp()+interval '1 day',clock_timestamp()+interval '2 days');
    raise exception 'Idle expiry after absolute expiry unexpectedly succeeded';
  exception when check_violation then null;
  end;

  begin
    insert into core.auth_sessions(user_id,auth_identity_id,refresh_token_hash,refresh_token_version,expires_at,idle_expires_at)
    values(v_user,v_identity,extensions.digest('gap-rotation-state','sha256'),2,clock_timestamp()+interval '30 days',clock_timestamp()+interval '7 days');
    raise exception 'Invalid rotation state unexpectedly succeeded';
  exception when check_violation then null;
  end;

  begin
    update core.users set age_eligibility_status='eligible',age_verified_at=null where user_id=v_user;
    raise exception 'Age decision without verification time unexpectedly succeeded';
  exception when check_violation then null;
  end;

  update core.user_verifications
  set email_status='verified',email_verified_at=clock_timestamp(),
      phone_status='verified',phone_verified_at=clock_timestamp()
  where user_id=v_user;
  insert into core.user_consents(user_id,consent_type,policy_version,decision,source)
  values(v_user,'kyc_verification','v1.0','granted','api');

  begin
    update core.user_verifications
    set aadhaar_status='pending',aadhaar_provider='digilocker',aadhaar_provider_ref=null
    where user_id=v_user;
    raise exception 'Incomplete Aadhaar provider evidence unexpectedly succeeded';
  exception when check_violation then null;
  end;

  update core.user_verifications
  set aadhaar_status='pending',aadhaar_provider='digilocker',aadhaar_provider_ref='gap-aadhaar-ref'
  where user_id=v_user;
  if not exists(
    select 1 from core.user_verifications
    where user_id=v_user and aadhaar_status='pending' and aadhaar_started_at is not null
  ) then raise exception 'Valid Aadhaar start transition failed'; end if;

  insert into core.user_otp_challenges(user_id,channel,purpose,destination_hash,contact_version,otp_hmac)
  values(v_user,'email','login',extensions.digest('gap-destination','sha256'),1,extensions.digest('gap-otp-one','sha256'));
  begin
    insert into core.user_otp_challenges(user_id,channel,purpose,destination_hash,contact_version,otp_hmac)
    values(v_user,'email','login',extensions.digest('gap-destination','sha256'),1,extensions.digest('gap-otp-two','sha256'));
    raise exception 'Duplicate pending OTP unexpectedly succeeded';
  exception when unique_violation then null;
  end;

  if position('FOR UPDATE' in upper(pg_get_functiondef('core.verify_otp_challenge(bigint,bytea)'::regprocedure)))=0
     or position('FOR UPDATE' in upper(pg_get_functiondef('core.resend_otp_challenge(bigint,bytea)'::regprocedure)))=0 then
    raise exception 'OTP concurrency row locks are missing';
  end if;

  begin
    insert into core.policy_versions(consent_type,policy_version,content_sha256,document_uri,published_at,effective_at)
    values('terms_of_service','v9.9',extensions.digest('gap-overlap','sha256'),
           'https://policies.example.test/terms_of_service/v9.9',clock_timestamp()-interval '1 day',clock_timestamp());
    raise exception 'Overlapping policy period unexpectedly succeeded';
  exception when exclusion_violation then null;
  end;

  begin
    update core.policy_versions set document_uri='https://policies.example.test/changed'
    where consent_type='terms_of_service' and policy_version='v1.1';
    raise exception 'Immutable policy content unexpectedly changed';
  exception when insufficient_privilege then null;
  end;

  begin
    update core.user_consents set decision='withdrawn'
    where id=(select min(id) from core.user_consents where user_id=v_user);
    raise exception 'Append-only consent unexpectedly changed';
  exception when insufficient_privilege then null;
  end;

  if exists(
    select 1 from core.auth_sessions s
    join core.auth_identities i on i.id=s.auth_identity_id
    where s.user_id<>i.user_id
  ) then raise exception 'Session identity ownership mismatch exists'; end if;
end $$;

select 'aditya_gap_hardening_contract_ok' result;
