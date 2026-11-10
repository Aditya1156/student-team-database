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
  insert into audit.audit_product_event(actor_type,action_type,event_category,target_user_id,request_id,event_status,event_source,data_modified,metadata)
  values('system','registration_started','authentication',v_user,p_request_id,'success','api',false,
         jsonb_build_object('provider',p_provider));
  return v_user;
end $$;

revoke all on function core.register_user(text,text,text,text,text,date,text,text,text,bytea,bytea,text) from public,anon,authenticated;
grant execute on function core.register_user(text,text,text,text,text,date,text,text,text,bytea,bytea,text) to service_role;
