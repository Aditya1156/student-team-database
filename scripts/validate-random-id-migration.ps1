$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$validationFile = Join-Path ([System.IO.Path]::GetTempPath()) 'student-team-random-id-validation.sql'
$migration = Get-Content -LiteralPath (Join-Path $repoRoot 'supabase\migrations\20261109101000_randomize_synthetic_user_ids.sql') -Raw
$seedLines = Get-Content -LiteralPath (Join-Path $repoRoot 'supabase\synthetic_review_data.sql')
$seed = ($seedLines | Where-Object { $_ -notmatch '^\s*(begin|commit);\s*$' }) -join [Environment]::NewLine
$assertion = @'
do $$
begin
  if (select count(*) from core.profiles where handle like '%_demo') <> 8 then
    raise exception 'Synthetic profile count mismatch';
  end if;
  if exists (select 1 from core.users where user_id::text like '00000000-0000-4000-8000-00000000000%') then
    raise exception 'Sequential synthetic user IDs remain';
  end if;
  if (select count(*) from core.messages where client_message_id = 'synthetic-message-001') <> 1 then
    raise exception 'Synthetic workflow was not recreated';
  end if;
end $$;
'@
[System.IO.File]::WriteAllText(
  $validationFile,
  'begin;' + [Environment]::NewLine + $migration + [Environment]::NewLine + $seed + [Environment]::NewLine + $assertion + [Environment]::NewLine + 'rollback;',
  [System.Text.UTF8Encoding]::new($false)
)
try {
  & $cli db query --remote --file $validationFile --yes
  if ($LASTEXITCODE -ne 0) { throw "Random-ID migration validation failed with exit code $LASTEXITCODE" }
} finally {
  Remove-Item -LiteralPath $validationFile -Force -ErrorAction SilentlyContinue
}
