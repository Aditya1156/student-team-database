create or replace function core.users_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'Unknown IANA timezone: %', new.timezone using errcode = '23514';
  end if;
  if new.date_of_birth is not null and new.date_of_birth > current_date then
    raise exception 'date_of_birth cannot be in the future' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id then
      raise exception 'user_id is immutable' using errcode = '23514';
    end if;
    if old.age_verified_at is not null and new.date_of_birth is distinct from old.date_of_birth then
      raise exception 'date_of_birth is locked after age verification' using errcode = '23514';
    end if;
    if new.account_status is distinct from old.account_status
       and coalesce(pg_catalog.current_setting('app.status_change_authorized', true), '') <> 'on' then
      raise exception 'Use core.change_account_status()' using errcode = '42501';
    end if;
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger users_before_write_trg
before insert or update on core.users
for each row execute function core.users_before_write();

create or replace function core.users_after_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into core.user_verifications(user_id) values (new.user_id);
  insert into core.user_status_history(user_id, from_status, to_status, actor_type, actor_id, reason_code)
  values (new.user_id, null, 'limited', 'system', null, 'signup');
  return new;
end;
$$;

create trigger users_after_insert_trg
after insert on core.users
for each row execute function core.users_after_insert();

create or replace function core.auth_identities_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_email text;
  v_phone text;
begin
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id or new.provider <> old.provider then
      raise exception 'identity owner and provider are immutable' using errcode = '23514';
    end if;
    if old.status <> 'active' and new.status = 'active' then
      raise exception 'an unlinked or revoked identity cannot be reactivated' using errcode = '23514';
    end if;
  end if;
  if new.provider in ('email_otp','phone_otp') then
    if new.provider_subject <> new.user_id::text then
      raise exception 'OTP provider_subject must equal user_id' using errcode = '23514';
    end if;
    select uv.email_status, uv.phone_status into v_email, v_phone
    from core.user_verifications uv where uv.user_id = new.user_id;
    if (new.provider = 'email_otp' and v_email <> 'verified')
       or (new.provider = 'phone_otp' and v_phone <> 'verified') then
      raise exception 'OTP identity requires a verified contact' using errcode = '23514';
    end if;
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger auth_identities_before_write_trg
before insert or update on core.auth_identities
for each row execute function core.auth_identities_before_write();

create or replace function core.user_contacts_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.email := lower(btrim(new.email));
  if tg_op = 'INSERT' then
    new.contact_version := 1;
  else
    if new.user_id <> old.user_id then
      raise exception 'contact owner is immutable' using errcode = '23514';
    end if;
    if new.email is distinct from old.email or new.phone_number is distinct from old.phone_number then
      new.contact_version := old.contact_version + 1;
    else
      new.contact_version := old.contact_version;
    end if;
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger user_contacts_before_write_trg
before insert or update on core.user_contacts
for each row execute function core.user_contacts_before_write();

create or replace function core.user_contacts_after_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.email is distinct from old.email then
    update core.user_verifications
      set email_status = 'not_started', email_verified_at = null, updated_at = clock_timestamp()
      where user_id = new.user_id;
    update core.user_otp_challenges
      set status = 'cancelled', updated_at = clock_timestamp()
      where user_id = new.user_id and channel = 'email' and status = 'pending';
  end if;
  if new.phone_number is distinct from old.phone_number then
    update core.user_verifications
      set phone_status = 'not_started', phone_verified_at = null, updated_at = clock_timestamp()
      where user_id = new.user_id;
    update core.user_otp_challenges
      set status = 'cancelled', updated_at = clock_timestamp()
      where user_id = new.user_id and channel = 'phone' and status = 'pending';
  end if;
  if (new.email is distinct from old.email or new.phone_number is distinct from old.phone_number)
     and exists (select 1 from core.users where user_id = new.user_id and account_status = 'active') then
    perform core.change_account_status(new.user_id, 'limited', 'system', null, 'verification_reset', null, null);
  end if;
  return new;
end;
$$;

create trigger user_contacts_after_change_trg
after update of email, phone_number on core.user_contacts
for each row execute function core.user_contacts_after_change();

create or replace function core.user_verifications_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.user_id <> old.user_id then
    raise exception 'verification owner is immutable' using errcode = '23514';
  end if;
  if new.phone_status <> 'not_started' and new.email_status <> 'verified' then
    raise exception 'email must be verified before phone verification starts' using errcode = '23514';
  end if;
  if new.aadhaar_status <> 'not_started' then
    if new.email_status <> 'verified' or new.phone_status <> 'verified' then
      raise exception 'contacts must be verified before KYC starts' using errcode = '23514';
    end if;
    if not exists (
      select 1 from core.user_consents_current c
      where c.user_id = new.user_id and c.consent_type = 'kyc_verification' and c.decision = 'granted'
    ) then
      raise exception 'KYC consent is required' using errcode = '23514';
    end if;
  end if;
  if new.pan_status <> 'not_started' and new.aadhaar_status = 'not_started' then
    raise exception 'Aadhaar verification must start before PAN verification' using errcode = '23514';
  end if;
  if new.aadhaar_attempt_count = 3 and new.aadhaar_status = 'pending' then
    new.aadhaar_status := 'failed';
    new.aadhaar_failure_reason := 'too_many_attempts';
  end if;
  if new.pan_attempt_count = 3 and new.pan_status = 'pending' then
    new.pan_status := 'failed';
    new.pan_failure_reason := 'too_many_attempts';
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create or replace function core.verification_sync()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_overall text;
  v_age text;
begin
  v_overall := case
    when new.email_status = 'verified' and new.phone_status = 'verified'
      and new.aadhaar_status = 'verified' and new.pan_status = 'verified' then 'verified'
    when new.aadhaar_status = 'review_required' or new.pan_status = 'review_required' then 'review_required'
    when new.email_status = 'failed' or new.phone_status = 'failed'
      or new.aadhaar_status = 'failed' or new.pan_status = 'failed' then 'rejected'
    else 'pending'
  end;
  v_age := case when new.age_eligible is true then 'eligible'
                when new.age_eligible is false then 'ineligible'
                else 'unknown' end;
  update core.users
     set verification_status = v_overall,
         age_eligibility_status = v_age,
         age_verified_at = case when new.age_eligible is not null then new.aadhaar_verified_at else null end
   where user_id = new.user_id;
  return new;
end;
$$;

create trigger user_verifications_before_write_trg
before insert or update on core.user_verifications
for each row execute function core.user_verifications_before_write();
create trigger user_verifications_after_write_trg
after insert or update on core.user_verifications
for each row execute function core.verification_sync();

create or replace function core.user_otp_challenges_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_version integer;
begin
  select contact_version into v_version from core.user_contacts where user_id = new.user_id;
  if v_version is null or new.contact_version <> v_version then
    raise exception 'OTP contact_version is stale' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    new.sent_at := clock_timestamp();
    new.last_sent_at := new.sent_at;
    new.expires_at := new.sent_at + interval '10 minutes';
  elsif new.user_id <> old.user_id or new.channel <> old.channel or new.purpose <> old.purpose
        or new.contact_version <> old.contact_version or new.otp_hmac <> old.otp_hmac
        or new.destination_hash is distinct from old.destination_hash then
    raise exception 'OTP identity and hashes are immutable' using errcode = '23514';
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger user_otp_challenges_before_write_trg
before insert or update on core.user_otp_challenges
for each row execute function core.user_otp_challenges_before_write();

create or replace function core.append_only_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_schema || '.' || tg_table_name using errcode = '42501';
end;
$$;

create trigger user_consents_append_only_trg
before update or delete on core.user_consents
for each row execute function core.append_only_guard();
create trigger user_status_history_append_only_trg
before update or delete on core.user_status_history
for each row execute function core.append_only_guard();
create trigger audit_product_event_append_only_trg
before update or delete on audit.audit_product_event
for each row execute function core.append_only_guard();

create or replace view core.user_consents_current
with (security_invoker = true)
as
select distinct on (user_id, consent_type)
  id, user_id, consent_type, policy_version, decision, source, captured_at
from core.user_consents
order by user_id, consent_type, captured_at desc, id desc;

create or replace function core.user_can_login(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from core.users u
    join core.user_verifications v using (user_id)
    where u.user_id = p_user_id
      and u.account_status in ('limited','active')
      and v.email_status = 'verified'
      and v.phone_status = 'verified'
  );
$$;

create or replace function core.user_access_ready(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from core.users u
    join core.user_verifications v using (user_id)
    where u.user_id = p_user_id
      and v.email_status = 'verified' and v.phone_status = 'verified'
      and v.aadhaar_status = 'verified' and v.pan_status = 'verified'
      and v.age_eligible is true
      and u.date_of_birth is not null
      and u.date_of_birth <= current_date - interval '18 years'
      and not exists (
        select 1 from (values ('terms_of_service'),('privacy_notice'),('kyc_verification')) required(consent_type)
        where not exists (
          select 1 from core.user_consents_current c
          where c.user_id = p_user_id and c.consent_type = required.consent_type and c.decision = 'granted'
        )
      )
  );
$$;

create or replace function core.user_access_level(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when u.account_status in ('suspended','deactivated','deletion_pending','deleted') then 'blocked_lifecycle'
    when v.email_status <> 'verified' or v.phone_status <> 'verified' then 'contact_verification'
    when v.aadhaar_status in ('failed','review_required') or v.pan_status in ('failed','review_required') then 'kyc_retry_or_review'
    when u.account_status = 'active' and core.user_access_ready(p_user_id) then 'main_app'
    else 'onboarding_kyc'
  end
  from core.users u join core.user_verifications v using (user_id)
  where u.user_id = p_user_id;
$$;

create or replace function core.change_account_status(
  p_user_id uuid,
  p_to_status text,
  p_actor_type text,
  p_actor_id text,
  p_reason_code text,
  p_effective_until timestamptz default null,
  p_request_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from text;
  v_allowed boolean := false;
begin
  select account_status into v_from from core.users where user_id = p_user_id for update;
  if v_from is null then raise exception 'Unknown user' using errcode = 'P0002'; end if;
  if v_from = p_to_status then return; end if;
  if v_from = 'deleted' then raise exception 'Deleted is final' using errcode = '23514'; end if;
  v_allowed := case
    when v_from = 'limited' and p_to_status = 'active' and p_reason_code = 'verification_completed' then true
    when v_from = 'limited' and p_to_status = 'suspended' and p_reason_code in ('policy_violation','fraud_suspected','report_upheld','age_ineligible') then true
    when v_from = 'limited' and p_to_status in ('deactivated','deletion_pending') and p_reason_code in ('user_request','inactivity','legal_request') then true
    when v_from = 'active' and p_to_status = 'limited' and p_reason_code = 'verification_reset' then true
    when v_from = 'active' and p_to_status = 'suspended' and p_reason_code in ('policy_violation','fraud_suspected','report_upheld','age_ineligible') then true
    when v_from = 'active' and p_to_status in ('deactivated','deletion_pending') and p_reason_code in ('user_request','inactivity','legal_request') then true
    when v_from = 'suspended' and p_to_status in ('limited','active') and p_reason_code in ('appeal_accepted','suspension_expired') then true
    when v_from = 'suspended' and p_to_status = 'deletion_pending' and p_reason_code in ('user_request','legal_request') then true
    when v_from = 'deactivated' and p_to_status in ('limited','active') and p_reason_code = 'user_returned' then true
    when v_from = 'deactivated' and p_to_status = 'deletion_pending' and p_reason_code in ('user_request','inactivity','legal_request') then true
    when v_from = 'deletion_pending' and p_to_status in ('limited','active') and p_reason_code = 'deletion_cancelled' then true
    when v_from = 'deletion_pending' and p_to_status = 'deleted' and p_reason_code = 'grace_period_ended' then true
    else false end;
  if not v_allowed then raise exception 'Invalid account transition % -> % (%)', v_from, p_to_status, p_reason_code using errcode = '23514'; end if;
  if p_actor_type not in ('user','admin','support','system')
     or (p_actor_type = 'system' and p_actor_id is not null)
     or (p_actor_type <> 'system' and p_actor_id is null) then
    raise exception 'Invalid actor' using errcode = '23514';
  end if;
  if p_to_status = 'active' and not core.user_access_ready(p_user_id) then
    raise exception 'Activation gates are not satisfied' using errcode = '23514';
  end if;
  if p_to_status = 'deletion_pending' and p_effective_until is null then
    p_effective_until := clock_timestamp() + interval '30 days';
  end if;
  if p_to_status = 'deleted' and exists (
    select 1 from safety.legal_holds h
    where h.user_id = p_user_id and h.status = 'active' and 'freeze_account_status_change' = any(h.restricted_actions)
      and (h.effective_until is null or h.effective_until > clock_timestamp())
  ) then raise exception 'Active legal hold blocks deletion status' using errcode = '42501'; end if;
  perform pg_catalog.set_config('app.status_change_authorized', 'on', true);
  update core.users set account_status = p_to_status,
    deleted_at = case when p_to_status = 'deleted' then clock_timestamp() else null end,
    date_of_birth = case when p_to_status = 'deleted' then null else date_of_birth end
  where user_id = p_user_id;
  insert into core.user_status_history(user_id, from_status, to_status, actor_type, actor_id, reason_code, effective_until, request_id)
  values (p_user_id, v_from, p_to_status, p_actor_type, p_actor_id, p_reason_code, p_effective_until, p_request_id);
end;
$$;

create or replace function core.accept_connection_request(p_request_id bigint, p_recipient_user_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  r core.connection_requests%rowtype;
  v_low uuid;
  v_high uuid;
  v_connection_id bigint;
begin
  select * into r from core.connection_requests where id = p_request_id for update;
  if not found then raise exception 'Unknown connection request' using errcode = 'P0002'; end if;
  if r.recipient_user_id <> p_recipient_user_id then raise exception 'Only the recipient may accept this request' using errcode = '42501'; end if;
  if r.status = 'accepted' then
    select id into v_connection_id from core.connections where created_from_request_id = r.id;
    return v_connection_id;
  end if;
  if r.status <> 'pending' or r.expires_at <= clock_timestamp() then raise exception 'Request is not acceptible' using errcode = '23514'; end if;
  if exists (
    select 1 from core.blocks b where b.removed_at is null
      and (b.expires_at is null or b.expires_at > clock_timestamp()) and b.block_type = 'full'
      and ((b.blocker_user_id = r.sender_user_id and b.blocked_user_id = r.recipient_user_id)
        or (b.blocker_user_id = r.recipient_user_id and b.blocked_user_id = r.sender_user_id))
  ) then raise exception 'A full block prevents connection' using errcode = '42501'; end if;
  v_low := least(r.sender_user_id, r.recipient_user_id);
  v_high := greatest(r.sender_user_id, r.recipient_user_id);
  update core.connection_requests set status = 'accepted', responded_at = clock_timestamp() where id = r.id;
  insert into core.connections(user_low_id, user_high_id, created_from_request_id, connection_source)
  values (v_low, v_high, r.id, coalesce(r.source_context, 'profile'))
  returning id into v_connection_id;
  insert into core.outbox_events(aggregate_type, aggregate_id, aggregate_sequence, event_type, payload, event_key)
  values ('connection', v_connection_id::text, 1, 'connection.created',
    jsonb_build_object('connection_id', v_connection_id, 'request_id', r.id), 'connection.created:' || v_connection_id);
  return v_connection_id;
end;
$$;

create or replace function core.ensure_direct_conversation(p_connection_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  c core.connections%rowtype;
  v_id bigint;
begin
  select * into c from core.connections where id = p_connection_id for update;
  if not found or c.status <> 'active' then raise exception 'Active connection required' using errcode = '23514'; end if;
  select id into v_id from core.conversations where connection_id = p_connection_id;
  if v_id is not null then return v_id; end if;
  insert into core.conversations(connection_id) values (p_connection_id) returning id into v_id;
  insert into core.conversation_participants(conversation_id, user_id)
  values (v_id, c.user_low_id), (v_id, c.user_high_id);
  return v_id;
end;
$$;

create or replace function core.send_text_message(
  p_conversation_id bigint,
  p_sender_user_id uuid,
  p_client_message_id varchar,
  p_text text,
  p_reply_to_message_id bigint default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_connection_id bigint;
  v_seq bigint;
  v_public_id uuid;
  v_message_id bigint;
begin
  if char_length(p_text) not between 1 and 2000 then raise exception 'Message text must be 1-2000 characters' using errcode = '23514'; end if;
  select connection_id into v_connection_id from core.conversations
  where id = p_conversation_id and status = 'active' for update;
  if v_connection_id is null then raise exception 'Active conversation required' using errcode = '23514'; end if;
  if not exists (select 1 from core.conversation_participants where conversation_id = p_conversation_id and user_id = p_sender_user_id and status = 'active') then
    raise exception 'Sender is not an active participant' using errcode = '42501';
  end if;
  if not exists (select 1 from core.connections where id = v_connection_id and status = 'active') then
    raise exception 'Connection is not active' using errcode = '42501';
  end if;
  if exists (
    select 1 from core.blocks b join core.connections c on c.id = v_connection_id
    where b.removed_at is null and (b.expires_at is null or b.expires_at > clock_timestamp())
      and b.block_type in ('full','dms_only')
      and b.blocker_user_id in (c.user_low_id,c.user_high_id)
      and b.blocked_user_id in (c.user_low_id,c.user_high_id)
  ) then raise exception 'A block prevents direct messaging' using errcode = '42501'; end if;
  if p_reply_to_message_id is not null and not exists (
    select 1 from core.messages where conversation_id = p_conversation_id and id = p_reply_to_message_id
  ) then raise exception 'Reply target must be in the same conversation' using errcode = '23503'; end if;
  select coalesce(max(conversation_seq), 0) + 1 into v_seq from core.messages where conversation_id = p_conversation_id;
  insert into core.messages(conversation_id, conversation_seq, sender_user_id, client_message_id, content, reply_to_message_id)
  values (p_conversation_id, v_seq, p_sender_user_id, p_client_message_id, jsonb_build_object('text', p_text), p_reply_to_message_id)
  returning id, public_id into v_message_id, v_public_id;
  update core.conversations set last_message_at = clock_timestamp() where id = p_conversation_id;
  update core.connections set last_interaction_at = clock_timestamp(), interaction_count = interaction_count + 1 where id = v_connection_id;
  insert into core.outbox_events(aggregate_type, aggregate_id, aggregate_sequence, event_type, payload, event_key)
  values ('conversation', p_conversation_id::text, v_seq, 'message.sent',
    jsonb_build_object('message_id', v_message_id, 'conversation_id', p_conversation_id),
    'message.sent:' || v_public_id::text);
  return v_public_id;
exception when unique_violation then
  select public_id into v_public_id from core.messages
  where sender_user_id = p_sender_user_id and client_message_id = p_client_message_id;
  if v_public_id is not null then return v_public_id; end if;
  raise;
end;
$$;

create or replace function core.notification_effective_enabled(p_user_id uuid, p_channel text, p_category text, p_at timestamptz default clock_timestamp())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when nc.status <> 'active' then false
    when nc.requires_marketing_consent and not exists (
      select 1 from core.user_consents_current c where c.user_id = p_user_id and c.consent_type = 'marketing' and c.decision = 'granted'
    ) then false
    when p_channel = 'in_app' and coalesce(np.in_app_enabled, true) = false and not nc.is_mandatory then false
    when p_channel = 'push' and coalesce(np.push_enabled, false) = false and not nc.is_mandatory then false
    when p_channel = 'email' and coalesce(np.email_enabled, false) = false and not nc.is_mandatory then false
    when nc.requires_marketing_consent and coalesce(np.marketing_enabled, false) = false then false
    when not nc.is_mandatory and coalesce(ncp.enabled, true) = false then false
    when not nc.is_mandatory and ncp.snoozed_from is not null and p_at >= ncp.snoozed_from and p_at < ncp.snoozed_until then false
    else true end
  from core.notification_categories nc
  join core.notification_category_channels ncc on ncc.category_code = nc.category_code and ncc.channel = p_channel
  left join core.notification_preferences np on np.user_id = p_user_id
  left join core.notification_category_preferences ncp on ncp.user_id = p_user_id and ncp.channel = p_channel and ncp.category = p_category
  where nc.category_code = p_category;
$$;

create or replace view core.relation_mutuality
with (security_invoker = true)
as
select r.id, r.actor_user_id, r.target_user_id, r.profile_prompt_id, r.reaction_type,
  exists (
    select 1 from core.relations reciprocal
    where reciprocal.actor_user_id = r.target_user_id
      and reciprocal.target_user_id = r.actor_user_id
      and reciprocal.status = 'active'
      and (reciprocal.expires_at is null or reciprocal.expires_at > clock_timestamp())
  ) as is_mutual,
  case
    when exists (
      select 1 from core.blocks b where b.removed_at is null and (b.expires_at is null or b.expires_at > clock_timestamp())
        and ((b.blocker_user_id = r.actor_user_id and b.blocked_user_id = r.target_user_id)
          or (b.blocker_user_id = r.target_user_id and b.blocked_user_id = r.actor_user_id))
    ) then 'user_blocked'
    when exists (
      select 1 from core.relations reciprocal
      where reciprocal.actor_user_id = r.target_user_id and reciprocal.target_user_id = r.actor_user_id
        and reciprocal.status = 'active' and (reciprocal.expires_at is null or reciprocal.expires_at > clock_timestamp())
    ) then null
    else 'awaiting_reciprocal_action'
  end as non_mutual_reason
from core.relations r;

create or replace view core.user_verification_progress
with (security_invoker = true)
as
select u.user_id, u.account_status, u.verification_status, u.age_eligibility_status,
  v.email_status, v.phone_status, v.aadhaar_status, v.aadhaar_failure_reason,
  v.pan_status, v.pan_failure_reason,
  (v.email_status = 'verified' and v.phone_status = 'verified' and v.aadhaar_status = 'verified'
    and v.pan_status = 'verified' and v.age_eligible is true) as all_steps_verified
from core.users u join core.user_verifications v using (user_id);

create or replace function core.prevent_direct_message_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from core.conversation_participants p
    join core.conversations c on c.id = p.conversation_id
    where p.conversation_id = new.conversation_id and p.user_id = new.sender_user_id
      and p.status = 'active' and c.status = 'active'
  ) then raise exception 'Sender is not an active participant in an active conversation' using errcode = '42501'; end if;
  return new;
end;
$$;
create trigger messages_membership_guard_trg
before insert on core.messages
for each row execute function core.prevent_direct_message_write();

create or replace function core.read_cursor_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_old_seq bigint;
  v_new_seq bigint;
begin
  if not exists (select 1 from core.conversation_participants where conversation_id = new.conversation_id and user_id = new.user_id and status = 'active') then
    raise exception 'Read cursor owner is not an active participant' using errcode = '42501';
  end if;
  if new.last_read_message_id is not null then
    select conversation_seq into v_new_seq from core.messages where conversation_id = new.conversation_id and id = new.last_read_message_id;
    if tg_op = 'UPDATE' and old.last_read_message_id is not null then
      select conversation_seq into v_old_seq from core.messages where conversation_id = old.conversation_id and id = old.last_read_message_id;
      if v_new_seq < v_old_seq then raise exception 'Read cursor cannot move backwards' using errcode = '23514'; end if;
    end if;
    new.last_read_at := clock_timestamp();
  end if;
  return new;
end;
$$;
create trigger message_read_cursors_guard_trg
before insert or update on core.message_read_cursors
for each row execute function core.read_cursor_guard();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'auth_identities','user_contacts','user_verifications','user_otp_challenges',
    'interest_categories','interest_subcategories','interests','prompt_catalogue','profiles','user_interests',
    'profile_prompts','notification_preferences','user_languages','connection_intents','discovery_dismissals',
    'conversations','notifications','account_data_jobs','account_data_job_steps','media_deletion_jobs',
    'notification_categories','notification_category_preferences'
  ] loop
    execute format('create trigger %I before update on core.%I for each row execute function core.set_updated_at()', v_table || '_set_updated_at_trg', v_table);
  end loop;
end $$;

do $$
declare
  r record;
begin
  for r in select schemaname, tablename from pg_catalog.pg_tables where schemaname in ('core','safety','analytics','audit') loop
    execute format('alter table %I.%I enable row level security', r.schemaname, r.tablename);
  end loop;
end $$;

revoke all on schema core, safety, analytics, audit from anon, authenticated;
revoke all on all tables in schema core, safety, analytics, audit from anon, authenticated;
revoke all on all sequences in schema core, safety, analytics, audit from anon, authenticated;
revoke all on all functions in schema core, safety, analytics, audit from public, anon, authenticated;

grant usage on schema core, safety, analytics, audit to service_role;
grant all on all tables in schema core, safety, analytics, audit to service_role;
grant all on all sequences in schema core, safety, analytics, audit to service_role;
grant execute on all functions in schema core, safety, analytics, audit to service_role;

alter default privileges in schema core revoke all on tables from anon, authenticated;
alter default privileges in schema safety revoke all on tables from anon, authenticated;
alter default privileges in schema analytics revoke all on tables from anon, authenticated;
alter default privileges in schema audit revoke all on tables from anon, authenticated;
alter default privileges in schema core grant all on tables to service_role;
alter default privileges in schema safety grant all on tables to service_role;
alter default privileges in schema analytics grant all on tables to service_role;
alter default privileges in schema audit grant all on tables to service_role;

do $$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'student_database_reviewer') then
    create role student_database_reviewer nologin noinherit;
  end if;
end $$;

create or replace view review.schema_inventory
as
select n.nspname as schema_name, c.relname as table_name,
  case c.relkind when 'r' then 'table' when 'p' then 'partitioned_table' when 'v' then 'view' when 'm' then 'materialized_view' end as relation_type,
  c.relrowsecurity as rls_enabled
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('core','safety','analytics','audit') and c.relkind in ('r','p','v','m');

create or replace view review.catalog_counts
as
select 'interest_categories'::text as catalog, count(*)::bigint as row_count from core.interest_categories
union all select 'interest_subcategories', count(*) from core.interest_subcategories
union all select 'interests', count(*) from core.interests
union all select 'prompt_catalogue', count(*) from core.prompt_catalogue
union all select 'connection_intents', count(*) from core.connection_intents
union all select 'safety_taxonomy_pairs', count(*) from safety.report_category_subcategories
union all select 'notification_categories', count(*) from core.notification_categories
union all select 'connection_closed_reasons', count(*) from core.connection_closed_reasons;

create or replace view review.synthetic_user_overview
as
select u.user_id, u.account_status, u.verification_status, u.age_eligibility_status,
  p.handle, p.visibility_status, p.profile_completeness,
  (select count(*) from core.user_interests ui where ui.user_id = u.user_id) as interest_count
from core.users u left join core.profiles p using (user_id);

grant usage on schema review to student_database_reviewer;
grant select on review.schema_inventory, review.catalog_counts, review.synthetic_user_overview to student_database_reviewer;
revoke all on all functions in schema core, safety, analytics, audit from student_database_reviewer;

comment on role student_database_reviewer is 'NOLOGIN role; grant through an approved individual access path. It can read only sanitized review views.';
comment on function core.accept_connection_request(bigint,uuid) is 'Trusted-backend routine; recipient identity must be derived from authenticated backend context.';
comment on function core.send_text_message(bigint,uuid,varchar,text,bigint) is 'Trusted-backend routine; sender identity must be derived from authenticated backend context.';
