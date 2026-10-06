<#
  Build del TFG en Windows (MiKTeX): xelatex + biber + nomenclatura.
  Uso:  .\build.ps1          compilar
        .\build.ps1 -Clean   borrar auxiliares
  Nota: los procesos externos se lanzan con cmd /c para que PowerShell no
        convierta los avisos de stderr de xelatex/makeindex en errores.
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
  Write-Host 'Limpiados los auxiliares.'
  return
}

#───────── localización de los ejecutables ─────────────────────────────────────
function Resolve-Tool([string]$name) {
  foreach ($c in @($name, "$name.exe")) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
  }
  $dirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\MiKTeX\miktex\bin\x64'),
    "$env:ProgramFiles\MiKTeX 2.9\miktex\bin\x64",
    "$env:ProgramFiles\MiKTeX\miktex\bin\x64"
  )
  foreach ($d in $dirs) {
    $p = Join-Path $d "$name.exe"
    if (Test-Path $p) { return $p }
  }
  return $null
}

$XeLaTeX   = Resolve-Tool 'xelatex'
$Biber     = Resolve-Tool 'biber'
$MakeIndex = Resolve-Tool 'makeindex'

if (-not $XeLaTeX -or -not $Biber) {
  Write-Host 'FALLO: no encuentro xelatex y/o biber.'
  Write-Host 'Abre MiKTeX Console -> Packages y comprueba instalados: xelatex, biblatex, biber.'
  Write-Host 'Activa ademas "Install missing packages on the fly".'
  exit 1
}

Write-Host 'Herramientas:'
Write-Host "  xelatex   : $XeLaTeX"
Write-Host "  biber     : $Biber"
Write-Host "  makeindex : $(if ($MakeIndex) { $MakeIndex } else { 'NO ENCONTRADO' })"

# Ejecuta un externo con cmd /c: stderr y stdout van al mismo log, sin NativeCommandError
function Invoke-Cmd {
  param([string]$Exe, [string]$ToolLog, [string]$Arguments)
  $comSpec = $env:ComSpec
  if (-not $comSpec) { $comSpec = 'cmd.exe' }
  $inner = '"' + $Exe + '" ' + $Arguments + ' > "' + $ToolLog + '" 2>&1'
  & $comSpec /c $inner
  return $LASTEXITCODE
}

function Invoke-Engine {
  Invoke-Cmd -Exe $XeLaTeX -ToolLog $Log `
    -Arguments "-synctex=1 -interaction=nonstopmode -file-line-error `"$Doc.tex`""
}

function Show-Errors {
  if (Test-Path $Log) {
    Write-Host '--- primeras lineas de error (archivo:linea) ---'
    Get-Content $Log | Where-Object { $_ -match '^[^ ]+\.tex:\d+: ' -or $_ -match '^! ' } |
      Select-Object -First 15
    Write-Host "--- final de $Log ---"
    Get-Content $Log -Tail 25
  }
}

function Stop-Build([string]$step) {
  Write-Host "FALLO: $step"
  Show-Errors
  exit 1
}

# Un .aux truncado por dos compilaciones a la vez da "Missing \begin{document}"
function Test-AuxRace {
  if ((Test-Path $Log) -and ((Get-Content $Log -Raw) -match 'Missing .begin\{document\}')) {
    Write-Host '  aviso: main.aux ilegible (compilacion concurrente) -> limpio y reintento'
    foreach ($e in @('aux','toc','lof','lot','fls','out')) {
      Remove-Item -Force -ErrorAction SilentlyContinue "$Doc.$e"
    }
    if ((Invoke-Engine) -ne 0) { Stop-Build 'xelatex tras limpiar .aux' }
  }
}

Write-Host '  -> xelatex (1/3)'
if ((Invoke-Engine) -ne 0) { Stop-Build 'xelatex (1/3)' }
Test-AuxRace

Write-Host '  -> biber (bibliografia)'
if ((Invoke-Cmd -Exe $Biber -ToolLog 'build.biber.log' -Arguments $Doc) -ne 0) {
  if (Test-Path 'build.biber.log') { Get-Content 'build.biber.log' -Tail 20 }
  Stop-Build 'biber (revisa references.bib)'
}

Write-Host '  -> makeindex (nomenclatura)'
if ($MakeIndex) {
  if ((Invoke-Cmd -Exe $MakeIndex -ToolLog 'build.makeindex.log' `
        -Arguments """$Doc.nlo"" -s nomencl.ist -o ""$Doc.nls""") -ne 0) {
    Stop-Build 'makeindex'
  }
} else {
  Write-Host '  aviso: no hay makeindex, la nomenclatura no se regenerara'
}

Write-Host '  -> xelatex (2/3)'
if ((Invoke-Engine) -ne 0) { Stop-Build 'xelatex (2/3)' }
Test-AuxRace

Write-Host '  -> xelatex (3/3)'
if ((Invoke-Engine) -ne 0) { Stop-Build 'xelatex (3/3)' }
Test-AuxRace

if (-not (Test-Path "$Doc.pdf")) { Stop-Build 'no se genero main.pdf' }

$raw = if (Test-Path $Log) { Get-Content $Log -Raw } else { '' }
$pages = if ($raw -match 'main\.pdf \((\d+)') { $Matches[1] } else { '?' }
$unresolved = 0
if ($raw) {
  $unresolved = [int]((Get-Content $Log | Where-Object { $_ -match 'Warning: (Citation|Reference) ' }).Count / 2)
}
Write-Host "OK -> $Doc.pdf ($pages paginas)"
if ($unresolved -gt 0) { Write-Host "aviso: $unresolved avisos de citas/referencias sin resolver -> repite .\build.ps1" }
exit 0
