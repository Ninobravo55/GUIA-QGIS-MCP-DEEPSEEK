<#
.SYNOPSIS
    Verifica el puente MCP de QGIS sin necesidad de abrir QGIS.

.DESCRIPTION
    Lanza el servidor MCP igual que lo hace DeepSeek (uv + stdio), hace el
    handshake y lista las herramientas. Deben salir 15.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verificar.ps1
#>
[CmdletBinding()]
param(
    [string]$Repo = "C:\Users\GEOMATICA\qgis_mcp",
    [string]$Uv = "C:\Users\GEOMATICA\.local\bin\uv.exe",
    [double]$Timeout = 120
)

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$py = Join-Path $Repo '.venv\Scripts\python.exe'

if (-not (Test-Path $py)) {
    Write-Host "[XX] No existe el entorno: $py" -ForegroundColor Red
    Write-Host "     Ejecuta primero: .\instalar.ps1" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path (Join-Path $Here 'probar_mcp.py'))) {
    Write-Host "[XX] Falta probar_mcp.py junto a este script" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Probando el servidor MCP (stdio)..." -ForegroundColor Cyan
& $py (Join-Path $Here 'probar_mcp.py') --repo $Repo --uv $Uv --timeout $Timeout
$code = $LASTEXITCODE

Write-Host ""
if ($code -eq 0) {
    Write-Host "[OK] El puente MCP funciona. Falta solo el lado de QGIS:" -ForegroundColor Green
    Write-Host "     Complementos > QGIS MCP > Start Server" -ForegroundColor Gray
} else {
    Write-Host "[XX] El puente MCP fallo (codigo $code)." -ForegroundColor Red
    Write-Host "     Revisa la salida de arriba y ejecuta .\instalar.ps1" -ForegroundColor Yellow
}
exit $code
