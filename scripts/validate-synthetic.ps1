$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$validationFile = Join-Path ([System.IO.Path]::GetTempPath()) 'student-team-synthetic-validation.sql'
$sourceLines = Get-Content -LiteralPath (Join-Path $repoRoot 'supabase\synthetic_review_data.sql')
$body = ($sourceLines | Where-Object { $_ -notmatch '^\s*(begin|commit);\s*$' }) -join [Environment]::NewLine
$assertion = @'
do $$
begin
  if (select count(*) from core.profiles where handle like 'demo_user_%') <> 50 then
    raise exception 'Synthetic profile count mismatch';
  end if;
  if not exists (select 1 from core.messages where client_message_id = 'synthetic-message-001') then
    raise exception 'Synthetic messaging workflow was not created';
  end if;
end $$;
'@
[System.IO.File]::WriteAllText(
  $validationFile,
  'begin;' + [Environment]::NewLine + $body + [Environment]::NewLine + $assertion + [Environment]::NewLine + 'rollback;',
  [System.Text.UTF8Encoding]::new($false)
)
try {
  & $cli db query --remote --file $validationFile --yes
  if ($LASTEXITCODE -ne 0) { throw "Synthetic validation failed with exit code $LASTEXITCODE" }
} finally {
  Remove-Item -LiteralPath $validationFile -Force -ErrorAction SilentlyContinue
}
