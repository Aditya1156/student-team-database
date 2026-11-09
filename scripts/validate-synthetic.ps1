$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$validationFile = Join-Path ([System.IO.Path]::GetTempPath()) 'student-team-synthetic-validation.sql'
$sourceLines = Get-Content -LiteralPath (Join-Path $repoRoot 'supabase\synthetic_review_data.sql')
$body = ($sourceLines | Where-Object { $_ -notmatch '^\s*(begin|commit);\s*$' }) -join [Environment]::NewLine
$assertion = @'
do $$
declare
  r record;
  v_rows bigint;
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
  if (select count(*) from core.users where account_status = 'active') <> 15
     or (select count(*) from core.users where account_status = 'suspended') <> 3
     or (select count(*) from core.users where account_status = 'deactivated') <> 2 then
    raise exception 'Account lifecycle scenario mismatch';
  end if;
  for r in
    select schemaname, tablename from pg_catalog.pg_tables
    where schemaname in ('core','safety','analytics','audit')
      and not (schemaname = 'core' and tablename in (
        'users','auth_identities','user_contacts','user_verifications',
        'user_otp_challenges','user_consents','user_status_history'))
  loop
    execute format('select count(*) from %I.%I', r.schemaname, r.tablename) into v_rows;
    if v_rows <> 0 then raise exception 'Non-Aditya table %.% contains % rows', r.schemaname, r.tablename, v_rows; end if;
  end loop;
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
