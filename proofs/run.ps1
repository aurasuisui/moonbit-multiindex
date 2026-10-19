# Check proofs/*.smt2 with z3.
#   powershell -NoProfile -File proofs/run.ps1
#   powershell -NoProfile -File proofs/run.ps1 -Z3Path C:\path\z3.exe
# Messages are intentionally ASCII: Windows PowerShell 5.1 reads BOM-less
# script files as ANSI, so non-ASCII text inside a script breaks parsing.
param([string]$Z3Path = "")

$ErrorActionPreference = "Stop"
if ($Z3Path -eq "") {
  $cmd = Get-Command z3 -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "z3 not found. Pass -Z3Path or put z3 on PATH." }
  $Z3Path = $cmd.Source
}

Write-Host ("z3: " + $Z3Path)
$failed = 0
foreach ($f in Get-ChildItem -Path (Join-Path $PSScriptRoot "*.smt2") | Sort-Object Name) {
  $out = & $Z3Path -smt2 $f.FullName 2>&1 | Out-String
  $verdict = ($out -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()
  if ($verdict -eq "unsat") {
    Write-Host ("  PASS  " + $f.Name)
  } else {
    Write-Host ("  FAIL  " + $f.Name + "  (expected unsat, got " + $verdict + ")")
    $failed++
  }
}
if ($failed -gt 0) { Write-Host ("failed: " + $failed); exit 1 }
Write-Host "all proofs checked"
