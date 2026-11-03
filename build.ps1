<#
  TFG Build Script for Windows: xelatex + biber + nomenclature.
  Usage:  .\build.ps1          compile
          .\build.ps1 -Clean   clean auxiliary files
  Note: Automatically discovers MiKTeX and TeX Live on any drive/path.
#>
param([switch]$Clean)

$ErrorActionPreference = 'Continue'
$Doc = 'main'
$Log = Join-Path $PSScriptRoot 'build.log'

Set-Location $PSScriptRoot

#───────── clean ───────────────────────────────────────────────────────────────
if ($Clean) {
  $ext = @('aux','toc','lof','lot','bbl','blg','nlo','nls','ilg','out','run.xml','bcf','log','fls','synctex.gz','pdf')
  foreach ($e in $ext) { Remove-Item -Force -ErrorAction SilentlyContinue "$Doc.$e" }
  Remove-Item -Force -ErrorAction SilentlyContinue 'build.log','build.biber.log','build.makeindex.log','mktest.log'
  Write-Host 'Auxiliary files cleaned.'
  return
}

#───────── executable discovery ────────────────────────────────────────────────
function Resolve-Tool([string]$name) {
  # 1. Check current PATH via Get-Command
  foreach ($c in @($name, "$name.exe")) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
  }

  # 2. Check via where.exe (in case it was recently installed)
  try {
    $whereRes = where.exe $name 2>$null | Select-Object -First 1
    if ($whereRes -and (Test-Path $whereRes)) { return $whereRes }
  } catch {}

  # 3. Standard Windows installation paths
  $dirs = [System.Collections.Generic.List[string]]::new()

  # MiKTeX user installation (%LOCALAPPDATA%)
  if ($env:LOCALAPPDATA) {
    $dirs.Add((Join-Path $env:LOCALAPPDATA 'Programs\MiKTeX\miktex\bin\x64'))
    $dirs.Add((Join-Path $env:LOCALAPPDATA 'Programs\MiKTeX\miktex\bin'))
  }
  if ($env:APPDATA) {
    $dirs.Add((Join-Path $env:APPDATA '..\Local\Programs\MiKTeX\miktex\bin\x64'))
    $dirs.Add((Join-Path $env:APPDATA '..\Local\Programs\MiKTeX\miktex\bin'))
  }

  # MiKTeX system-wide installation (%ProgramFiles%)
  if ($env:ProgramFiles) {
    $dirs.Add((Join-Path $env:ProgramFiles 'MiKTeX\miktex\bin\x64'))
    $dirs.Add((Join-Path $env:ProgramFiles 'MiKTeX 2.9\miktex\bin\x64'))
    $dirs.Add((Join-Path $env:ProgramFiles 'MiKTeX\miktex\bin'))
  }
  if (${env:ProgramFiles(x86)}) {
    $dirs.Add((Join-Path ${env:ProgramFiles(x86)} 'MiKTeX\miktex\bin\x64'))
    $dirs.Add((Join-Path ${env:ProgramFiles(x86)} 'MiKTeX 2.9\miktex\bin\x64'))
    $dirs.Add((Join-Path ${env:ProgramFiles(x86)} 'MiKTeX\miktex\bin'))
  }

  # Package managers (Scoop, Chocolatey)
  if ($env:USERPROFILE) {
    $dirs.Add((Join-Path $env:USERPROFILE 'scoop\shims'))
    $dirs.Add((Join-Path $env:USERPROFILE 'scoop\apps\miktex\current\miktex\bin\x64'))
  }
  if ($env:ProgramData) {
    $dirs.Add((Join-Path $env:ProgramData 'chocolatey\bin'))
  }

  # TeX Live and MiKTeX across all system drives
  try {
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName.TrimEnd('\') }
  } catch {
    $drives = @('C:', 'D:', 'E:')
  }
  if (-not $drives -or $drives.Count -eq 0) { $drives = @('C:', 'D:', 'E:') }

  foreach ($drv in $drives) {
    # TeX Live (any year or architecture)
    $tlRoot = Join-Path $drv 'texlive'
    if (Test-Path $tlRoot) {
      Get-ChildItem -Path (Join-Path $tlRoot '*\bin\windows') -ErrorAction SilentlyContinue | ForEach-Object { $dirs.Add($_.FullName) }
      Get-ChildItem -Path (Join-Path $tlRoot '*\bin\win32') -ErrorAction SilentlyContinue | ForEach-Object { $dirs.Add($_.FullName) }
    }
    # MiKTeX on drive root
    $mikRoot = Join-Path $drv 'MiKTeX\miktex\bin\x64'
    if (Test-Path $mikRoot) { $dirs.Add($mikRoot) }
    $mikRoot32 = Join-Path $drv 'MiKTeX\miktex\bin'
    if (Test-Path $mikRoot32) { $dirs.Add($mikRoot32) }
  }

  foreach ($d in $dirs) {
    if ($d -and (Test-Path $d)) {
      $p = Join-Path $d "$name.exe"
      if (Test-Path $p) { return $p }
    }
  }
  return $null
}

$XeLaTeX   = Resolve-Tool 'xelatex'
$Biber     = Resolve-Tool 'biber'
$MakeIndex = Resolve-Tool 'makeindex'

if (-not $XeLaTeX -or -not $Biber) {
  Write-Host '========================================================================'
  Write-Host 'ERROR: Required LaTeX tools not found.'
  if (-not $XeLaTeX) { Write-Host '  - Missing: xelatex' }
  if (-not $Biber)   { Write-Host '  - Missing: biber' }
  Write-Host '------------------------------------------------------------------------'
  Write-Host 'Recommended installation on Windows:'
  Write-Host '  1. Download and install MiKTeX from https://miktex.org or via winget:'
  Write-Host '       winget install MiKTeX.MiKTeX'
  Write-Host '  2. During installation, select "Install missing packages on the fly: Yes".'
  Write-Host '  3. Alternatively, you can install TeX Live: https://www.tug.org/texlive/'
  Write-Host '========================================================================'
  exit 1
}

$IsMiKTeX = ($XeLaTeX -match '(?i)miktex')
$EngineName = if ($IsMiKTeX) { 'MiKTeX' } else { 'TeX Live' }

Write-Host 'Tools:'
Write-Host "  xelatex   : $XeLaTeX ($EngineName)"
Write-Host "  biber     : $Biber"
Write-Host "  makeindex : $(if ($MakeIndex) { $MakeIndex } else { 'NOT FOUND' })"

# Safely executes an external command redirecting stdout and stderr to the log
function Invoke-Cmd {
  param([string]$Exe, [string]$ToolLog, [string]$Arguments)
  $comSpec = $env:ComSpec
  if (-not $comSpec) { $comSpec = 'cmd.exe' }
  $inner = "`"`"$Exe`" $Arguments > `"$ToolLog`" 2>&1`""
  & $comSpec /s /c $inner
  return $LASTEXITCODE
}

function Invoke-Engine {
  $mikFlag = if ($IsMiKTeX) { '-enable-installer ' } else { '' }
  Invoke-Cmd -Exe $XeLaTeX -ToolLog $Log `
    -Arguments "$mikFlag-synctex=1 -interaction=nonstopmode -file-line-error `"$Doc.tex`""
}

function Show-Errors {
  if (Test-Path $Log) {
    Write-Host '--- First error lines (file:line) ---'
    Get-Content $Log | Where-Object { $_ -match '^[^ ]+\.tex:\d+: ' -or $_ -match '^! ' } |
      Select-Object -First 15
    Write-Host "--- End of $Log ---"
    Get-Content $Log -Tail 25
  }
}

function Stop-Build([string]$step) {
  Write-Host "FAILED: $step"
  Show-Errors
  exit 1
}

# A truncated .aux file from concurrent or aborted builds causes
# "Missing \begin{document}" / "Extra }" errors: clean and retry.
function Test-AuxCorrupt {
  (Test-Path $Log) -and ((Get-Content $Log -Raw) -match 'main\.aux.*: (Missing .begin\{document\}|Extra \}, or forgotten|File ended while scanning)|\\@firstoffive')
}

function Invoke-EngineStep([string]$step) {
  if ((Invoke-Engine) -eq 0) { return }
  if (Test-AuxCorrupt) {
    Write-Host '  warning: corrupt main.aux (concurrent/aborted build) -> cleaning and retrying'
    foreach ($e in @('aux','toc','lof','lot','fls','out')) {
      Remove-Item -Force -ErrorAction SilentlyContinue "$Doc.$e"
    }
    if ((Invoke-Engine) -ne 0) { Stop-Build "$step (after cleaning .aux)" }
  } else {
    Stop-Build $step
  }
}

Write-Host '  -> xelatex (1/3)'
Invoke-EngineStep 'xelatex (1/3)'

Write-Host '  -> biber (bibliography)'
if ((Invoke-Cmd -Exe $Biber -ToolLog 'build.biber.log' -Arguments "`"$Doc`"") -ne 0) {
  if (Test-Path 'build.biber.log') { Get-Content 'build.biber.log' -Tail 20 }
  Stop-Build 'biber (check references.bib)'
}

Write-Host '  -> makeindex (nomenclature)'
if ($MakeIndex) {
  if ((Invoke-Cmd -Exe $MakeIndex -ToolLog 'build.makeindex.log' `
        -Arguments "`"$Doc.nlo`" -s nomencl.ist -o `"$Doc.nls`"") -ne 0) {
    Stop-Build 'makeindex'
  }
} else {
  Write-Host '  warning: makeindex not found, nomenclature will not be regenerated'
}

Write-Host '  -> xelatex (2/3)'
Invoke-EngineStep 'xelatex (2/3)'

Write-Host '  -> xelatex (3/3)'
Invoke-EngineStep 'xelatex (3/3)'

if (-not (Test-Path "$Doc.pdf")) { Stop-Build 'main.pdf was not generated' }

$raw = if (Test-Path $Log) { Get-Content $Log -Raw } else { '' }
$pages = if ($raw -match 'main\.pdf \((\d+)') { $Matches[1] } else { '?' }
$unresolved = 0
if ($raw) {
  $unresolved = [int]((Get-Content $Log | Where-Object { $_ -match 'Warning: (Citation|Reference) ' }).Count / 2)
}
Write-Host "OK -> $Doc.pdf ($pages pages)"
if ($unresolved -gt 0) { Write-Host "warning: $unresolved unresolved citation/reference warnings -> rerun .\build.ps1" }
exit 0
