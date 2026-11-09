$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$validationFile = Join-Path ([System.IO.Path]::GetTempPath()) 'student-team-synthetic-validation.sql'
$sourceLines = Get-Content -LiteralPath (Join-Path $repoRoot 'supabase\synthetic_review_data.sql')
$body = ($sourceLines | Where-Object { $_ -notmatch '^\s*(begin|commit);\s*$' }) -join [Environment]::NewLine
$assertion = @'
do $$
begin
  if (select count(*) from core.users) <> 50 then
    raise exception 'Aditya synthetic user count mismatch';
  end if;
  if (select count(*) from core.user_contacts) <> 50
     or (select count(*) from core.user_verifications) <> 50
     or (select count(*) from core.user_otp_challenges) <> 50 then
    raise exception 'Aditya identity child-table count mismatch';
  end if;
  if (select count(distinct gender) from core.users) <> 10 then
    raise exception 'Gender value coverage mismatch';
  end if;
  if (select count(distinct account_status) from core.users) <> 6
     or (select count(distinct verification_status) from core.users) <> 4 then
    raise exception 'Account or verification state coverage mismatch';
  end if;
  if (select count(distinct email_status) from core.user_verifications) <> 4
     or (select count(distinct phone_status) from core.user_verifications) <> 4
     or (select count(distinct aadhaar_status) from core.user_verifications) <> 5
     or (select count(distinct pan_status) from core.user_verifications) <> 5 then
    raise exception 'Verification step coverage mismatch';
  end if;
  if (select count(distinct provider) from core.auth_identities) <> 4
     or (select count(distinct status) from core.auth_identities) <> 3
     or (select count(distinct status) from core.user_otp_challenges) <> 5
     or (select count(distinct purpose) from core.user_otp_challenges) <> 4 then
    raise exception 'Identity provider or OTP coverage mismatch';
  end if;
  if (select count(distinct consent_type) from core.user_consents) <> 4
     or (select count(distinct decision) from core.user_consents) <> 3
     or (select count(distinct source) from core.user_consents) <> 4
     or (select count(distinct actor_type) from core.user_status_history) <> 4
     or (select count(distinct reason_code) from core.user_status_history) <> 15 then
    raise exception 'Consent or lifecycle-history coverage mismatch';
  end if;
  if (select count(distinct aadhaar_failure_reason) from core.user_verifications where aadhaar_failure_reason is not null) <> 16
     or (select count(distinct pan_failure_reason) from core.user_verifications where pan_failure_reason is not null) <> 13 then
    raise exception 'KYC failure-reason coverage mismatch';
  end if;
end $$;
'@
$sequenceRepair = @'
do $$
declare
  v_table text;
  v_max bigint;
begin
  foreach v_table in array array[
    'users','auth_identities','user_contacts','user_verifications',
    'user_otp_challenges','user_consents','user_status_history'
  ]
  loop
    execute format('select max(id) from core.%I', v_table) into v_max;
    if v_max is null then
      execute format('select pg_catalog.setval(pg_catalog.pg_get_serial_sequence(''core.%I'',''id''),1,false)', v_table);
    else
      execute format('select pg_catalog.setval(pg_catalog.pg_get_serial_sequence(''core.%I'',''id''),%s,true)', v_table, v_max);
    end if;
  end loop;
end $$;
'@
[System.IO.File]::WriteAllText(
  $validationFile,
  'begin;' + [Environment]::NewLine + $body + [Environment]::NewLine + $assertion + [Environment]::NewLine + 'rollback;' + [Environment]::NewLine + $sequenceRepair,
  [System.Text.UTF8Encoding]::new($false)
)
try {
  & $cli db query --remote --file $validationFile --yes
  if ($LASTEXITCODE -ne 0) { throw "Synthetic validation failed with exit code $LASTEXITCODE" }
} finally {
  Remove-Item -LiteralPath $validationFile -Force -ErrorAction SilentlyContinue
}
