-- DB-026: controlled account erasure with a retained, non-login user tombstone.
-- Physical deletion of core.users remains intentionally restricted because
-- append-only consent, lifecycle, audit, and safety evidence reference it.

create table core.account_deletion_matrix (
  relation_name text primary key,
  data_class text not null,
  deletion_action text not null,
  execution_order smallint not null,
  owner_name text not null,
  hold_behavior text not null,
  implemented boolean not null default true,
  notes text not null,
  constraint account_deletion_matrix_relation_ck
    check(relation_name ~ '^(core|safety|analytics|audit)\.[a-z][a-z0-9_]*$'),
  constraint account_deletion_matrix_action_ck
    check(deletion_action in (
      'delete','anonymize','retain','retain_under_hold','external_delete_then_delete'
    )),
  constraint account_deletion_matrix_order_ck check(execution_order between 1 and 1000),
  constraint account_deletion_matrix_hold_ck
    check(hold_behavior in ('continue','block_erasure','preserve'))
);

insert into core.account_deletion_matrix
  (relation_name,data_class,deletion_action,execution_order,owner_name,hold_behavior,notes)
values
  ('core.auth_sessions','authentication_secret','delete',10,'Aditya','block_erasure','Revoke first, then remove refresh-token digests.'),
  ('core.device_tokens','notification_secret','delete',20,'Mahera','block_erasure','Remove encrypted push tokens and fingerprints.'),
  ('core.user_otp_challenges','authentication_secret','delete',30,'Aditya','block_erasure','Remove short-lived OTP hashes and destinations.'),
  ('core.auth_identities','authentication_identifier','delete',40,'Aditya','block_erasure','Remove provider subjects after sessions are removed.'),
  ('core.user_contacts','direct_identifier','delete',50,'Aditya','block_erasure','Remove email and phone.'),
  ('core.user_verifications','sensitive_identity','delete',60,'Aditya','block_erasure','Remove Aadhaar/PAN hashes, references, masks and KYC state.'),
  ('core.notifications','user_content','delete',70,'Koushik','block_erasure','Remove user delivery records and payloads.'),
  ('core.notification_preferences','preference','delete',80,'Thanushree','block_erasure','Remove user notification settings.'),
  ('core.notification_category_preferences','preference','delete',90,'Mahera','block_erasure','Remove per-category settings.'),
  ('core.user_interests','preference','delete',100,'Thanushree','block_erasure','Remove user-interest links.'),
  ('core.user_languages','preference','delete',110,'Thanushree','block_erasure','Remove language preferences.'),
  ('core.relations','social_graph','delete',120,'Mahera','block_erasure','Remove reactions involving the erased user.'),
  ('core.acknowledgements','social_graph','delete',130,'Rajath','block_erasure','Remove acknowledgements involving the erased user.'),
  ('core.discovery_dismissals','social_graph','delete',140,'Rajath','block_erasure','Remove discovery decisions involving the erased user.'),
  ('core.blocks','safety_preference','delete',150,'Prajwal','block_erasure','Remove user block rows after access is disabled.'),
  ('core.connection_requests','social_graph','anonymize',160,'Prajwal','block_erasure','Remove free text/idempotency; retain accepted request identity when referenced.'),
  ('core.connections','shared_relationship','anonymize',170,'Mahera','block_erasure','Close active connections and retain the tombstone reference.'),
  ('core.conversation_participants','shared_relationship','anonymize',180,'Rajath','block_erasure','Leave active conversations; retain membership evidence.'),
  ('core.messages','shared_content','anonymize',190,'Rajath','block_erasure','Redact content while preserving conversation ordering and safety references.'),
  ('core.message_read_cursors','preference','delete',200,'Rajath','block_erasure','Remove private read position.'),
  ('core.profile_prompts','profile_content','anonymize',210,'Thanushree','block_erasure','Replace answers with an erasure marker.'),
  ('core.profiles','profile_content','anonymize',220,'Thanushree','block_erasure','Remove name, bio, location and public handle.'),
  ('core.profile_media','external_media','external_delete_then_delete',230,'Prajwal','block_erasure','Delete object storage first through media_deletion_jobs.'),
  ('core.user_pseudonyms','pseudonymous_link','anonymize',240,'Prajwal','block_erasure','Revoke and unlink pseudonyms from the user tombstone.'),
  ('core.outbox_events','operational_event','anonymize',250,'Koushik','preserve','Redact payloads containing the user UUID; retain delivery ordering.'),
  ('analytics.product_events','analytics_event','anonymize',260,'Skanda','preserve','Redact unexpected direct UUIDs; unlinked pseudonyms remain.'),
  ('core.user_consents','compliance_evidence','retain',300,'Aditya','preserve','Append-only minimal policy decision evidence.'),
  ('core.user_status_history','compliance_evidence','retain',310,'Aditya','preserve','Append-only lifecycle and deletion evidence.'),
  ('core.account_data_jobs','privacy_job_evidence','retain',320,'Koushik','preserve','Retain deletion-job evidence linked to the tombstone.'),
  ('core.account_data_job_steps','privacy_job_evidence','retain',330,'Koushik','preserve','Retain step-level outcome evidence.'),
  ('audit.audit_product_event','security_audit','retain',340,'Skanda','preserve','Append-only operational audit linked only to tombstone UUID.'),
  ('safety.reports','safety_record','retain_under_hold',350,'Tejaswini','preserve','Preserve reports according to approved safety retention.'),
  ('safety.moderation_actions','safety_record','retain_under_hold',360,'Tejaswini','preserve','Preserve moderation decisions.'),
  ('safety.moderation_appeals','safety_record','retain_under_hold',370,'Tejaswini','preserve','Preserve appeal evidence.'),
  ('safety.report_evidence','safety_record','retain_under_hold',380,'Skanda','preserve','Preserve protected evidence under its retention policy.'),
  ('safety.legal_holds','legal_hold','retain_under_hold',390,'Tejaswini','preserve','Legal holds control and evidence are never erased by this workflow.'),
  ('core.users','identity_tombstone','anonymize',400,'Aditya','preserve','Retain random UUID, deleted state and deletion timestamp only.');

alter table core.account_deletion_matrix enable row level security;
revoke all on core.account_deletion_matrix from public,anon,authenticated;
grant select on core.account_deletion_matrix to service_role;

create or replace view review.account_deletion_matrix as
select relation_name,data_class,deletion_action,execution_order,owner_name,
       hold_behavior,implemented,notes
from core.account_deletion_matrix
order by execution_order,relation_name;
grant select on review.account_deletion_matrix to student_database_reviewer;

-- Pseudonyms may be retained for aggregate analytics only after the link to the
-- user tombstone is removed.
alter table core.user_pseudonyms alter column user_id drop not null;
alter table core.user_pseudonyms
  add constraint user_pseudonyms_unlinked_ck check(
    user_id is not null or (status='revoked' and is_default is false)
  );

-- Clearing DOB during an authorized final deletion is not a forbidden DOB edit.
create or replace function core.users_before_write()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=new.timezone) then
    raise exception 'Unknown IANA timezone: %',new.timezone using errcode='23514';
  end if;
  if new.date_of_birth is not null and new.date_of_birth>current_date then
    raise exception 'date_of_birth cannot be in the future' using errcode='23514';
  end if;
  if tg_op='UPDATE' then
    if new.user_id<>old.user_id then
      raise exception 'user_id is immutable' using errcode='23514';
    end if;
    if old.age_verified_at is not null
       and new.date_of_birth is distinct from old.date_of_birth
       and not (
         new.date_of_birth is null
         and (
           old.account_status='deleted'
           or (new.account_status='deleted' and
               coalesce(pg_catalog.current_setting('app.status_change_authorized',true),'')='on')
         )
       ) then
      raise exception 'date_of_birth is locked after age verification' using errcode='23514';
    end if;
    if new.account_status is distinct from old.account_status
       and coalesce(pg_catalog.current_setting('app.status_change_authorized',true),'')<>'on' then
      raise exception 'Use core.change_account_status()' using errcode='42501';
    end if;
  end if;
  new.updated_at:=clock_timestamp();
  return new;
end $$;

insert into core.connection_closed_reasons
  (code,closed_by_type,description,is_user_visible)
values
  ('account_deleted','system','The connection was closed because an account was deleted.',false)
on conflict(code,closed_by_type) do update
set description=excluded.description,is_user_visible=false;

create or replace function core.execute_account_erasure(
  p_user_id uuid,
  p_request_id text default null
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_now timestamptz:=clock_timestamp();
  v_status text;
  v_effective_until timestamptz;
  v_job_id bigint;
  v_job_status text;
  v_key text:='account-erasure:'||p_user_id::text;
  v_pending_media integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_key));
  select account_status into v_status
  from core.users where user_id=p_user_id for update;
  if not found then raise exception 'Unknown user' using errcode='P0002'; end if;

  if exists(
    select 1 from safety.legal_holds h
    where h.user_id=p_user_id
      and h.status='active'
      and (h.effective_until is null or h.effective_until>v_now)
      and h.restricted_actions && array[
        'block_account_erasure','block_content_deletion','block_message_deletion',
        'block_media_deletion','block_data_job_purge'
      ]::text[]
  ) then
    insert into audit.audit_product_event(
      actor_type,action_type,event_category,target_user_id,request_id,
      event_status,failure_reason,event_source,data_modified,metadata
    ) values(
      'system','account_erasure_blocked','privacy',p_user_id,p_request_id,
      'failure','active_legal_hold','system',false,
      jsonb_build_object('workflow','db026_controlled_erasure')
    );
    return 'blocked_by_legal_hold';
  end if;

  if v_status='deletion_pending' then
    select effective_until into v_effective_until
    from core.user_status_history
    where user_id=p_user_id and to_status='deletion_pending'
    order by id desc limit 1;
    if v_effective_until is null or v_effective_until>v_now then
      return 'grace_period_active';
    end if;
    perform core.change_account_status(
      p_user_id,'deleted','system',null,'grace_period_ended',null,
      coalesce(p_request_id,'erasure-finalize:'||p_user_id::text)
    );
    v_status:='deleted';
  end if;
  if v_status<>'deleted' then
    raise exception 'Account must be deletion_pending after its grace period or deleted' using errcode='23514';
  end if;

  select id,status into v_job_id,v_job_status
  from core.account_data_jobs
  where job_type='deletion' and idempotency_key=v_key
  for update;
  if v_job_status='completed' then return 'already_completed:'||v_job_id::text; end if;

  insert into core.account_data_jobs(
    user_id,job_type,status,requested_at,started_at,attempt_count,idempotency_key,
    worker_id,lease_token,lease_expires_at,updated_at
  ) values(
    p_user_id,'deletion','processing',v_now,v_now,1,v_key,
    'database_erasure',extensions.gen_random_uuid(),v_now+interval '5 minutes',v_now
  )
  on conflict(job_type,idempotency_key) do update
  set status='processing',started_at=coalesce(core.account_data_jobs.started_at,v_now),
      completed_at=null,attempt_count=core.account_data_jobs.attempt_count+1,
      error_code=null,worker_id='database_erasure',
      lease_token=extensions.gen_random_uuid(),lease_expires_at=v_now+interval '5 minutes',
      updated_at=v_now
  returning id into v_job_id;

  insert into core.account_data_job_steps(job_id,step_code)
  select v_job_id,step_code from unnest(array[
    'legal_hold_check','revoke_access','erase_private_data',
    'external_media_deletion','anonymize_shared_data','finalize_tombstone'
  ]) step_code
  on conflict(job_id,step_code) do nothing;
  update core.account_data_job_steps
  set status='succeeded',started_at=coalesce(started_at,v_now),completed_at=v_now,
      last_error_code=null,updated_at=v_now
  where job_id=v_job_id and step_code='legal_hold_check';

  update core.auth_sessions
  set status='revoked',revoked_at=v_now,revocation_reason='account_deleted',updated_at=v_now
  where user_id=p_user_id and status='active';
  delete from core.auth_sessions where user_id=p_user_id;
  delete from core.device_tokens where user_id=p_user_id;
  delete from core.user_otp_challenges where user_id=p_user_id;
  delete from core.auth_identities where user_id=p_user_id;
  update core.account_data_job_steps
  set status='succeeded',started_at=coalesce(started_at,v_now),completed_at=v_now,updated_at=v_now
  where job_id=v_job_id and step_code='revoke_access';

  delete from core.user_contacts where user_id=p_user_id;
  delete from core.user_verifications where user_id=p_user_id;
  delete from core.notifications where recipient_user_id=p_user_id;
  delete from core.notification_category_preferences where user_id=p_user_id;
  delete from core.notification_preferences where user_id=p_user_id;
  delete from core.user_interests where user_id=p_user_id;
  delete from core.user_languages where user_id=p_user_id;
  delete from core.message_read_cursors where user_id=p_user_id;
  delete from core.relations where actor_user_id=p_user_id or target_user_id=p_user_id;
  delete from core.acknowledgements where actor_user_id=p_user_id or target_user_id=p_user_id;
  delete from core.discovery_dismissals where viewer_user_id=p_user_id or candidate_user_id=p_user_id;
  delete from core.blocks where blocker_user_id=p_user_id or blocked_user_id=p_user_id;

  update core.connection_requests
  set reason_text=null,idempotency_key=null,
      status=case when status='pending' then 'cancelled' else status end,
      responded_at=case when status='pending' then v_now else responded_at end
  where sender_user_id=p_user_id or recipient_user_id=p_user_id;
  delete from core.connection_requests r
  where (r.sender_user_id=p_user_id or r.recipient_user_id=p_user_id)
    and not exists(select 1 from core.connections c where c.created_from_request_id=r.id);

  update core.connections
  set status='closed',closed_at=v_now,closed_reason='account_deleted',
      closed_by_type='system',closed_by_user_id=null
  where status='active' and (user_low_id=p_user_id or user_high_id=p_user_id);

  update core.conversation_participants
  set status='left',left_at=v_now,removed_by_user_id=null
  where user_id=p_user_id and status='active';
  update core.messages
  set content=case when message_type='text'
        then jsonb_build_object('text','[erased]')
        else jsonb_build_object('redacted',true) end,
      status='removed',deleted_at=coalesce(deleted_at,v_now),edited_at=null,
      client_message_id='erased-'||id::text
  where sender_user_id=p_user_id;

  update core.profile_prompts
  set answer=jsonb_build_object('version',1,'response','[erased]'),
      status='hidden',block_prompt_code=null,updated_at=v_now
  where user_id=p_user_id;
  update core.profiles
  set display_name='Deleted User',handle='deleted_'||left(replace(p_user_id::text,'-',''),24),
      bio='[erased]',location='[erased]',visibility_status='hidden',
      profile_media_id=null,profile_completeness=0,deleted_at=coalesce(deleted_at,v_now),
      updated_at=v_now
  where user_id=p_user_id;

  update core.user_pseudonyms
  set user_id=null,handle='erased-'||replace(pseudonym_id::text,'-',''),
      status='revoked',is_default=false,rotated_at=null
  where user_id=p_user_id;
  update core.outbox_events
  set payload=jsonb_build_object('redacted',true,'schema_version',1)
  where aggregate_id=p_user_id::text or payload::text like '%'||p_user_id::text||'%';
  update analytics.product_events
  set properties=jsonb_build_object(
        'schema_version',coalesce(properties->'schema_version','1'::jsonb),
        'redacted',true
      )
  where properties::text like '%'||p_user_id::text||'%';
  update core.account_data_job_steps
  set status='succeeded',started_at=coalesce(started_at,v_now),completed_at=v_now,updated_at=v_now
  where job_id=v_job_id and step_code in ('erase_private_data','anonymize_shared_data');

  update core.profile_media pm
  set lifecycle_status='purged',deleted_at=coalesce(deleted_at,v_now),
      purge_after=coalesce(purge_after,v_now),purged_at=v_now
  where pm.user_id=p_user_id and pm.lifecycle_status<>'purged'
    and exists(
      select 1 from core.media_deletion_jobs j
      where j.object_key=pm.object_key and j.status='completed'
    );
  update core.profile_media
  set lifecycle_status='deleted',deleted_at=coalesce(deleted_at,v_now),
      purge_after=coalesce(purge_after,v_now)
  where user_id=p_user_id and lifecycle_status='active';
  insert into core.media_deletion_jobs(profile_media_id,object_key)
  select pm.media_id,pm.object_key from core.profile_media pm
  where pm.user_id=p_user_id and pm.lifecycle_status<>'purged'
    and not exists(
      select 1 from core.media_deletion_jobs j
      where j.object_key=pm.object_key and j.status in ('pending','processing','retry_wait','completed')
    );
  select count(*) into v_pending_media
  from core.profile_media where user_id=p_user_id and lifecycle_status<>'purged';

  update core.users
  set timezone='UTC',verification_status='pending',age_eligibility_status='unknown',
      age_verified_at=null,date_of_birth=null,gender='prefer_not_to_say'
  where user_id=p_user_id;

  if v_pending_media>0 then
    update core.account_data_job_steps
    set status='pending',last_error_code='waiting_for_external_media',updated_at=v_now
    where job_id=v_job_id and step_code='external_media_deletion';
    update core.account_data_jobs
    set status='queued',error_code='waiting_for_external_media',execute_after=v_now+interval '5 minutes',
        worker_id=null,lease_token=null,lease_expires_at=null,updated_at=v_now
    where id=v_job_id;
    return 'waiting_for_media:'||v_job_id::text;
  end if;

  delete from core.profile_media where user_id=p_user_id;
  update core.account_data_job_steps
  set status='succeeded',started_at=coalesce(started_at,v_now),completed_at=v_now,
      last_error_code=null,updated_at=v_now
  where job_id=v_job_id and step_code in ('external_media_deletion','finalize_tombstone');
  update core.account_data_jobs
  set status='completed',completed_at=v_now,error_code=null,execute_after=null,
      worker_id=null,lease_token=null,lease_expires_at=null,updated_at=v_now
  where id=v_job_id;
  insert into audit.audit_product_event(
    actor_type,action_type,event_category,target_user_id,request_id,
    event_status,event_source,data_modified,previous_value,new_value,metadata
  ) values(
    'system','account_erasure_completed','privacy',p_user_id,p_request_id,
    'success','system',true,
    jsonb_build_object('account_status','deleted'),
    jsonb_build_object('tombstone_retained',true,'direct_identifiers_removed',true),
    jsonb_build_object('job_id',v_job_id,'workflow','db026_controlled_erasure')
  );
  return 'completed:'||v_job_id::text;
end $$;

comment on function core.execute_account_erasure(uuid,text) is
  'Idempotent DB-026 erasure worker. Requires deletion_pending after grace or deleted, blocks on active destructive legal holds, removes direct PII/secrets, redacts shared data, waits for external media deletion, and retains a minimal user tombstone plus approved evidence.';

revoke all on function core.execute_account_erasure(uuid,text) from public,anon,authenticated;
grant execute on function core.execute_account_erasure(uuid,text) to service_role;

