create or replace view review.synthetic_user_overview
as
select u.user_id, u.account_status, u.verification_status, u.age_eligibility_status,
  p.handle, p.visibility_status, p.profile_completeness,
  (select count(*) from core.user_interests ui where ui.user_id = u.user_id) as interest_count,
  row_number() over (order by p.handle) as reviewer_number,
  case
    when u.account_status = 'active' and u.verification_status = 'verified' then 'verified_active'
    when v.aadhaar_status = 'review_required' or v.pan_status = 'review_required' then 'manual_review'
    when v.aadhaar_status = 'pending' or v.pan_status = 'pending' then 'kyc_pending'
    when v.email_status = 'failed' or v.phone_status = 'failed' then 'contact_failed'
    when v.email_status = 'verified' and v.phone_status = 'verified' then 'contact_verified'
    else 'not_started'
  end as review_scenario
from core.users u
join core.profiles p using (user_id)
join core.user_verifications v using (user_id)
where p.handle like 'demo_user_%';

grant select on review.synthetic_user_overview to student_database_reviewer;
comment on column review.synthetic_user_overview.reviewer_number is 'Convenient display number 1-50; never use as a key.';
