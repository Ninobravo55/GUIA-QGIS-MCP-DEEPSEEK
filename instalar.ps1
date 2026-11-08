<#
.SYNOPSIS
    Instala el puente QGIS MCP para DeepSeek Harness (basado en jjsantos01/qgis_mcp).

.DESCRIPTION
    Deja lista la parte "host" del setup:
      1. Copia el plugin a la carpeta de plugins de QGIS.
      2. Sincroniza el entorno Python con uv.
      3. Aplica los 3 parches necesarios al repo (stdout -> stderr, conexion persistente).
      4. Genera el bundle de configuracion MCP (package.json + cordis.patch.yml).

    Lo unico que NO puede hacer desde aqui es registrar el bundle en el perfil
    "desktop" (lo administra la app Electron). Ese paso se hace en 1 frase
    dentro de DeepSeek (ver salida final).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\instalar.ps1

.EXAMPLE
    .\instalar.ps1 -Repo "D:\qgis_mcp" -Uv "C:\Users\GEOMATICA\.local\bin\uv.exe"
#>
[CmdletBinding()]
param(
    [string]$Repo = "C:\Users\GEOMATICA\qgis_mcp",
    [string]$Uv = "C:\Users\GEOMATICA\.local\bin\uv.exe",
    [string]$BundleDir = "C:\Users\GEOMATICA\Documents\deepseek-harness\default-workspace\mcp-qgis-bundle",
    [switch]$SkipPluginCopy
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Problems = 0

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor DarkGray
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor DarkGray
}
function Write-Ok([string]$Text)   { Write-Host "   [OK]  $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text){ Write-Host "   [!!]  $Text" -ForegroundColor Yellow; $script:Problems++ }
function Write-Bad([string]$Text)  { Write-Host "   [XX]  $Text" -ForegroundColor Red;    $script:Problems++ }

Write-Host ""
Write-Host "  QGIS MCP -> DeepSeek Harness  |  instalador" -ForegroundColor White

# ---------------------------------------------------------------- 1. Repo
Write-Step "1/7  Repositorio qgis_mcp"
if (-not (Test-Path (Join-Path $Repo 'pyproject.toml'))) {
    Write-Bad "No encuentro el repo en: $Repo"
    Write-Host "        Descargalo de https://github.com/jjsantos01/qgis_mcp"
    Write-Host "        (Code > Download ZIP, descomprime) y ejecuta de nuevo con -Repo <ruta>"
    exit 1
}
Write-Ok "Repo: $Repo"

# ---------------------------------------------------------------- 2. uv
Write-Step "2/7  Gestor uv"
if (-not (Test-Path $Uv)) {
    $cmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($cmd) {
        $Uv = $cmd.Source
        Write-Warn2 "No estaba en la ruta indicada; uso $Uv"
    } else {
        Write-Bad "No encuentro uv.exe. Instalalo: https://docs.astral.sh/uv/"
        exit 1
    }
}
$uvVersion = (& $Uv --version) 2>&1
Write-Ok "uv: $Uv  ($uvVersion)"

# ---------------------------------------------------------------- 3. Plugin
Write-Step "3/7  Plugin dentro de QGIS"
if ($SkipPluginCopy) {
    Write-Warn2 "Copia del plugin omitida (-SkipPluginCopy)"
} else {
    $pluginSrc = Join-Path $Repo 'qgis_mcp_plugin'
    $pluginsRoot = Join-Path $env:APPDATA 'QGIS\QGIS3\profiles\default\python\plugins'
    if (-not (Test-Path (Join-Path $pluginSrc 'metadata.txt'))) {
        Write-Bad "No existe $pluginSrc (repo incompleto)"
    } else {
        $pluginDst = Join-Path $pluginsRoot 'qgis_mcp_plugin'
        New-Item -ItemType Directory -Path $pluginDst -Force | Out-Null
        Copy-Item (Join-Path $pluginSrc '*') $pluginDst -Recurse -Force
        Write-Ok "Plugin copiado a: $pluginDst"
        $same = @(Get-ChildItem $pluginDst -File).Count
        Write-Host "        ($same archivos)"
    }
}

# ---------------------------------------------------------------- 4. uv sync
Write-Step "4/7  Entorno Python (uv sync)"
& $Uv sync --directory $Repo --no-progress
if ($LASTEXITCODE -ne 0) {
    Write-Bad "uv sync fallo (codigo $LASTEXITCODE). Revisa conexion a internet."
    exit 1
}
$py = Join-Path $Repo '.venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    Write-Bad "No se creo el entorno en $py"
    exit 1
}
Write-Ok "Entorno: $py"

# ---------------------------------------------------------------- 5. Parches
Write-Step "5/7  Parches del repo (idempotente)"
& $py (Join-Path $Here 'aplicar_parches.py') $Repo
if ($LASTEXITCODE -ne 0) {
    Write-Warn2 "Algun parche no se pudo aplicar (revisa la salida de arriba)"
} else {
    Write-Ok "Parches aplicados / ya presentes"
}

# ---------------------------------------------------------------- 6. Bundle
Write-Step "6/7  Bundle de configuracion MCP"
New-Item -ItemType Directory -Path $BundleDir -Force | Out-Null
Copy-Item (Join-Path $Here 'bundle\package.json') (Join-Path $BundleDir 'package.json') -Force

$yaml = @"
# Bundle local: conecta DeepSeek Harness con QGIS via qgis_mcp.
# Generado por instalar.ps1 el $(Get-Date -Format 'yyyy-MM-dd HH:mm').
# El plugin de QGIS escucha en localhost:9876; este cliente MCP lanza el
# puente Python (uv) que traduce MCP/stdio <-> socket de QGIS.
- insert:
    - id: qgis-mcp
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: qgis
        transport: stdio
        command: '$Uv'
        args:
          - run
          - --project
          - '$Repo'
          - --directory
          - '$Repo\src\qgis_mcp'
          - qgis_mcp_server.py
        cwd: '$Repo\src\qgis_mcp'
        env:
          PYTHONUTF8: '1'
          PYTHONIOENCODING: 'utf-8'
          PYTHONUNBUFFERED: '1'
        toolCallTimeoutMs: 180000
        failOnStartupError: false
"@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $BundleDir 'cordis.patch.yml'), $yaml, $utf8NoBom)
Write-Ok "Bundle en: $BundleDir"

# ---------------------------------------------------------------- 7. Estado
Write-Step "7/7  Estado del registro en DeepSeek"
$profilePkgs = Join-Path $env:USERPROFILE '.dsh\profiles\desktop\package.json'
$registered = $false
if (Test-Path $profilePkgs) {
    $registered = (Get-Content $profilePkgs -Raw) -match 'qgis-mcp'
}
if ($registered) {
    Write-Ok "El bundle ya esta registrado en el perfil 'desktop'."
    Write-Host "        Si cambiaste rutas o parches, reinicia DeepSeek Harness."
} else {
    Write-Warn2 "Falta registrarlo (1 paso, dentro de DeepSeek)"
}

Write-Host ""
Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " SIGUIENTE PASO" -ForegroundColor White
Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGray
if (-not $registered) {
    Write-Host " 1. Abre (o reinicia) DeepSeek Harness." -ForegroundColor White
    Write-Host " 2. En un chat nuevo escribe:" -ForegroundColor White
    Write-Host ""
    Write-Host "      Instala este bundle como plugin del perfil:" -ForegroundColor Gray
    Write-Host "      $BundleDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    (el agente usara la herramienta plugin_manager -> install_bundle)" -ForegroundColor Gray
} else {
    Write-Host " 1. Reinicia DeepSeek Harness si cambiaste algo." -ForegroundColor White
}
Write-Host " 3. En QGIS: Complementos > QGIS MCP > Start Server." -ForegroundColor White
Write-Host "    Debe decir: Server: Running on port 9876" -ForegroundColor Gray
Write-Host " 4. Prueba en el chat:  'haz ping a QGIS'" -ForegroundColor White
Write-Host ""
Write-Host " Verificacion tecnica (sin QGIS abierto):" -ForegroundColor White
Write-Host "   powershell -ExecutionPolicy Bypass -File `"$Here\verificar.ps1`" -Repo `"$Repo`" -Uv `"$Uv`"" -ForegroundColor Gray
Write-Host ""
if ($Problems -gt 0) {
    Write-Host " Avisos durante la instalacion: $Problems (ver lineas [!!] / [XX])" -ForegroundColor Yellow
}
