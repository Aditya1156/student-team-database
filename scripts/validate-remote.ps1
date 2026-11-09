$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$contract = Join-Path $repoRoot 'supabase\tests\schema_contract.sql'
& $cli db query --remote --file $contract --yes
if ($LASTEXITCODE -ne 0) { throw "Remote contract validation failed with exit code $LASTEXITCODE" }
