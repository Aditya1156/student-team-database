do $$
declare
  v_email_user uuid;
  v_phone_user uuid;
  v_challenge bigint;
  v_identity bigint;
  v_session uuid;
  v_session_two uuid;
  v_result text;
  v_before bigint;
begin
  if to_regclass('core.auth_sessions') is null or to_regclass('core.policy_versions') is null then
    raise exception 'Lifecycle completion tables are missing';
  end if;
  if (select count(*) from core.policy_versions) <> 6 then raise exception 'Policy catalogue count mismatch'; end if;

  v_email_user:=core.register_user(
    'email_otp',null,'contract.email@example.test','+919999990001','Asia/Kolkata',date '1995-01-01','prefer_not_to_say',
    'v1.1','v1.1',extensions.digest('email-otp','sha256'),extensions.digest('email-destination','sha256'),'contract-email');
  select id into v_challenge from core.user_otp_challenges where user_id=v_email_user and purpose='signup';
  if core.verify_otp_challenge(v_challenge,extensions.digest('email-otp','sha256'))<>'verified' then raise exception 'Email OTP registration failed'; end if;
  if not exists(select 1 from core.auth_identities where user_id=v_email_user and provider='email_otp' and status='active') then raise exception 'Email identity was not linked'; end if;

  update core.user_verifications set phone_status='verified',phone_verified_at=clock_timestamp() where user_id=v_email_user;
  v_identity:=core.link_auth_identity(v_email_user,'google','contract-google-subject');
  if v_identity is null then raise exception 'Cross-provider linking failed'; end if;

  begin
    perform core.register_user('google','duplicate-contact-subject','contract.email@example.test','+919999990099','Asia/Kolkata',date '1995-01-01','prefer_not_to_say','v1.1','v1.1',null,null,'duplicate-contact');
    raise exception 'Duplicate contact registration unexpectedly succeeded';
  exception when unique_violation then null;
  end;

  v_phone_user:=core.register_user(
    'phone_otp',null,'contract.phone@example.test','+919999990002','Asia/Kolkata',date '1994-02-02','prefer_not_to_say',
    'v1.1','v1.1',extensions.digest('phone-otp','sha256'),extensions.digest('phone-destination','sha256'),'contract-phone');
  select id into v_challenge from core.user_otp_challenges where user_id=v_phone_user and purpose='signup';
  update core.user_otp_challenges set sent_at=clock_timestamp()-interval '3 minutes',last_sent_at=clock_timestamp()-interval '2 minutes',
    expires_at=clock_timestamp()+interval '8 minutes',resend_window_started_at=clock_timestamp()-interval '3 minutes' where id=v_challenge;
  perform core.resend_otp_challenge(v_challenge,extensions.digest('phone-otp-resend','sha256'));
  if (select resend_count from core.user_otp_challenges where id=v_challenge)<>1 then raise exception 'OTP resend counter failed'; end if;
  begin
    perform core.resend_otp_challenge(v_challenge,extensions.digest('phone-otp-resend-two','sha256'));
    raise exception 'OTP resend cooldown unexpectedly bypassed';
  exception when sqlstate 'P0001' then null;
  end;
  for i in 1..5 loop v_result:=core.verify_otp_challenge(v_challenge,extensions.digest('incorrect-'||i,'sha256')); end loop;
  if v_result<>'locked' then raise exception 'Incorrect OTP attempts did not lock challenge'; end if;

  select id into v_identity from core.auth_identities where user_id=v_email_user and provider='email_otp';
  v_session:=core.issue_auth_session(v_email_user,v_identity,extensions.digest('refresh-one','sha256'),'contract-device');
  if core.validate_auth_session(extensions.digest('refresh-one','sha256'))<>v_email_user then raise exception 'Session validation failed'; end if;
  if core.rotate_refresh_token(v_session,extensions.digest('refresh-one','sha256'),extensions.digest('refresh-two','sha256'))<>'rotated' then raise exception 'Refresh rotation failed'; end if;
  if core.rotate_refresh_token(v_session,extensions.digest('stolen-old-token','sha256'),extensions.digest('refresh-three','sha256'))<>'compromised' then raise exception 'Refresh reuse was not detected'; end if;
  if (select status from core.auth_sessions where session_id=v_session)<>'compromised' then raise exception 'Compromised session was not persisted'; end if;

  v_session_two:=core.issue_auth_session(v_email_user,v_identity,extensions.digest('refresh-four','sha256'),'contract-device-two');
  perform core.change_account_status(v_email_user,'suspended','admin','contract-admin','policy_violation',clock_timestamp()+interval '1 day','contract-suspend');
  if (select status from core.auth_sessions where session_id=v_session_two)<>'revoked' then raise exception 'Lifecycle change did not revoke session'; end if;

  insert into core.user_consents(user_id,consent_type,policy_version,decision,source)
  values(v_email_user,'privacy_notice','v1.1','withdrawn','settings');
  if not exists(select 1 from core.user_consents where user_id=v_email_user and consent_type='privacy_notice' and policy_version='v1.1' and decision='withdrawn') then
    raise exception 'Versioned consent withdrawal failed';
  end if;

  if not exists(select 1 from core.user_verifications where user_id=v_email_user and email_verified_at is not null) then raise exception 'Verification timestamps are missing'; end if;
  select count(*) into v_before from audit.audit_product_event where target_user_id in (v_email_user,v_phone_user) and event_category='identity';
  if v_before<10 then raise exception 'Automatic identity audit coverage is incomplete'; end if;
end $$;

select 'identity_lifecycle_contract_ok' result;
