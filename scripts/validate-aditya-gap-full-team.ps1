$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$wrapper = Join-Path $PSScriptRoot 'validate-pending-migration.mjs'
$migration = Join-Path $repoRoot 'supabase\migrations\20261111100000_aditya_gap_hardening.sql'
$fixture = Join-Path $repoRoot 'supabase\full_team_review_data.sql'
$validationFile = & node $wrapper $migration $fixture
try {
  & $cli db query --remote --file $validationFile --yes
  if ($LASTEXITCODE -ne 0) { throw "Aditya gap plus full-team validation failed with exit code $LASTEXITCODE" }
} finally {
  Remove-Item -LiteralPath $validationFile -Force -ErrorAction SilentlyContinue
}
