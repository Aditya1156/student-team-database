$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$wrapper = Join-Path $PSScriptRoot 'validate-pending-migration.mjs'
$contract = Join-Path $repoRoot 'supabase\tests\aditya_gap_hardening_contract.sql'
$validationFile = & node $wrapper $contract
try {
  & $cli db query --remote --file $validationFile --yes
  if ($LASTEXITCODE -ne 0) { throw "Aditya gap hardening validation failed with exit code $LASTEXITCODE" }
} finally {
  Remove-Item -LiteralPath $validationFile -Force -ErrorAction SilentlyContinue
}
