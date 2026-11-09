$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$generator = Join-Path $PSScriptRoot 'generate-full-team-review.mjs'
$validationFile = Join-Path ([System.IO.Path]::GetTempPath()) 'full-team-review-rollback.sql'

try {
  & node $generator --rollback
  if ($LASTEXITCODE -ne 0) { throw "Team fixture generation failed with exit code $LASTEXITCODE" }
  & $cli db query --remote --file $validationFile --yes
  if ($LASTEXITCODE -ne 0) { throw "Full-team rollback validation failed with exit code $LASTEXITCODE" }
} finally {
  Remove-Item -LiteralPath $validationFile -Force -ErrorAction SilentlyContinue
}
