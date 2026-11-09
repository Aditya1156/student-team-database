-- Replace the earlier synthetic fixture cleanly so internal test IDs remain
-- deterministic from 1 while every non-Aditya table stays empty.
do $$
declare
  v_tables text;
  v_count integer;
begin
  select count(*), string_agg(format('%I.%I', schemaname, tablename), ', ' order by schemaname, tablename)
    into v_count, v_tables
  from pg_catalog.pg_tables
  where schemaname in ('core', 'safety', 'analytics', 'audit');
  if v_count <> 49 then raise exception 'Expected 49 application tables, found %', v_count; end if;
  execute 'truncate table ' || v_tables || ' restart identity';
end $$;

create or replace view review.aditya_identity_scenarios
as
select
  row_number() over (order by c.email) as reviewer_number,
  u.user_id,
  c.email,
  c.phone_number,
  u.account_status,
  u.verification_status,
  u.age_eligibility_status,
  u.gender,
  v.email_status,
  v.phone_status,
  v.aadhaar_status,
  v.pan_status,
  case
    when u.account_status = 'deleted' then 'deleted'
    when u.account_status = 'deletion_pending' then 'deletion_pending'
    when u.account_status = 'suspended' then 'suspended'
    when u.account_status = 'deactivated' then 'deactivated'
    when u.account_status = 'active' and u.verification_status = 'verified' then 'verified_active'
    when u.verification_status = 'verified' then 'verified_limited'
    when v.aadhaar_status = 'review_required' or v.pan_status = 'review_required' then 'manual_review'
    when v.aadhaar_status = 'pending' or v.pan_status = 'pending' then 'kyc_pending'
    when u.verification_status = 'rejected' then 'rejected'
    when v.email_status = 'verified' and v.phone_status = 'verified' then 'contact_verified'
    else 'not_started'
  end as review_scenario
from core.users u
join core.user_contacts c using (user_id)
join core.user_verifications v using (user_id)
where c.email like 'aditya.user%@example.test';

grant select on review.aditya_identity_scenarios to student_database_reviewer;
