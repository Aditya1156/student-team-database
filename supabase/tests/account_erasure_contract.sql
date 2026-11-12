-- Rollback-only DB-026 contract test.
do $$
declare
  v_user uuid;
  v_held_user uuid;
  v_admin bigint;
  v_result text;
begin
  if (select count(*) from core.account_deletion_matrix)<30 then
    raise exception 'Account deletion matrix is incomplete';
  end if;

  v_user:=core.register_user(
    'google','erasure-contract-user','erasure.contract@example.test','+919999992001',
    'Asia/Kolkata',date '1990-01-01','male','v1.1','v1.1',null,null,'erasure-contract-register'
  );
  insert into core.profiles(user_id,display_name,handle,bio,location)
  values(v_user,'Erasure Contract','erasure_contract_user','Sensitive profile text','Bengaluru');
  perform core.change_account_status(
    v_user,'deletion_pending','user','erasure-contract-user','user_request',
    clock_timestamp()-interval '1 second','erasure-contract-pending'
  );
  v_result:=core.execute_account_erasure(v_user,'erasure-contract-run');
  if v_result not like 'completed:%' then raise exception 'Erasure did not complete: %',v_result; end if;
  if exists(select 1 from core.user_contacts where user_id=v_user)
     or exists(select 1 from core.user_verifications where user_id=v_user)
     or exists(select 1 from core.auth_identities where user_id=v_user)
     or exists(select 1 from core.auth_sessions where user_id=v_user)
     or exists(select 1 from core.user_otp_challenges where user_id=v_user) then
    raise exception 'Direct identity data survived erasure';
  end if;
  if not exists(
    select 1 from core.users
    where user_id=v_user and account_status='deleted' and date_of_birth is null
      and age_verified_at is null and gender='prefer_not_to_say'
  ) then raise exception 'User tombstone is invalid'; end if;
  if not exists(
    select 1 from core.profiles
    where user_id=v_user and display_name='Deleted User' and bio='[erased]'
      and location='[erased]' and visibility_status='hidden'
  ) then raise exception 'Profile was not anonymized'; end if;
  if not exists(select 1 from core.user_consents where user_id=v_user)
     or not exists(select 1 from core.user_status_history where user_id=v_user and to_status='deleted') then
    raise exception 'Required compliance evidence was not retained';
  end if;
  if not exists(
    select 1 from audit.audit_product_event
    where target_user_id=v_user and action_type='account_erasure_completed'
  ) then raise exception 'Erasure completion was not audited'; end if;

  v_held_user:=core.register_user(
    'google','erasure-contract-held','erasure.held@example.test','+919999992002',
    'Asia/Kolkata',date '1991-01-01','female','v1.1','v1.1',null,null,'erasure-held-register'
  );
  perform core.change_account_status(
    v_held_user,'deletion_pending','user','erasure-contract-user','user_request',
    clock_timestamp()-interval '1 second','erasure-held-pending'
  );
  insert into safety.admin_users(external_identity_id,role)
  values(extensions.gen_random_uuid(),'security_admin') returning id into v_admin;
  insert into safety.legal_holds(
    user_id,case_reference,scope,restricted_actions,imposed_by_admin_id,reason_code
  ) values(
    v_held_user,'LH-9999-9001','specified_user_accounts',array['block_account_erasure'],v_admin,'safety_investigation'
  );
  v_result:=core.execute_account_erasure(v_held_user,'erasure-held-run');
  if v_result<>'blocked_by_legal_hold' then raise exception 'Legal hold did not block erasure: %',v_result; end if;
  if not exists(select 1 from core.user_contacts where user_id=v_held_user) then
    raise exception 'Held user was modified despite legal hold';
  end if;
end $$;

select 'account_erasure_contract_ok' result;

