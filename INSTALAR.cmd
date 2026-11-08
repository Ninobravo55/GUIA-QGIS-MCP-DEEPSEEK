@echo off
setlocal
rem Instalador de un clic: evita los bloqueos de ExecutionPolicy.
rem Uso:  INSTALAR.cmd  [--params para instalar.ps1]
echo.
echo  QGIS MCP - DeepSeek Harness
echo  ===========================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1" %*
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" (
  echo El instalador termino con codigo %RC%.
) else (
  echo Instalacion completada.
)
pause
exit /b %RC%
