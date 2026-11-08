# Kit: QGIS ↔ DeepSeek Harness (MCP)

Todo lo necesario para conectar QGIS con DeepSeek Harness en ~5 minutos, basado en
[jjsantos01/qgis_mcp](https://github.com/jjsantos01/qgis_mcp).

## Contenido

| Archivo | Para qué |
|---|---|
| `INSTALAR.cmd` | **Doble clic**: instala todo (llama a `instalar.ps1` con la política de ejecución saltada). |
| `instalar.ps1` | Hace todo el trabajo: copia el plugin, sincroniza Python con uv, parchea el repo y genera el bundle MCP. |
| `verificar.ps1` + `probar_mcp.py` | Comprueba que el puente MCP arranca y expone las 15 herramientas (sin abrir QGIS). |
| `aplicar_parches.py` | Aplica (o comprueba) los 3 parches necesarios. Idempotente. |
| `bundle/package.json` | Manifiesto del bundle `@local/qgis-mcp` para DeepSeek. |
| `GUIA-QGIS-MCP-DEEPSEEK.md` | Guía de uso, verificación y problemas típicos. |

## Instalación (3 pasos)

**1. Script de host** — doble clic en **`INSTALAR.cmd`** (evita el bloqueo de
`ExecutionPolicy` y deja la ventana abierta al terminar).

Equivalentes desde consola:

```powershell
powershell -ExecutionPolicy Bypass -File .\instalar.ps1
```

Parámetros si tus rutas son distintas:

```powershell
.\instalar.ps1 -Repo "D:\qgis_mcp" -Uv "C:\Users\TU_USUARIO\.local\bin\uv.exe" `
               -BundleDir "C:\ruta\estable\mcp-qgis-bundle"
```

> Si ejecutas `.\instalar.ps1` directamente y Windows lo bloquea, es la política de
> ejecución de scripts: usa `INSTALAR.cmd` o el `-ExecutionPolicy Bypass` de arriba.

**2. Registrar el bundle en DeepSeek** (único paso manual, porque el perfil `desktop`
lo administra la app Electron). Abre un chat nuevo y pide:

> Instala este bundle como plugin del perfil: `C:\Users\GEOMATICA\Documents\deepseek-harness\default-workspace\mcp-qgis-bundle`

El agente lo registra con `plugin_manager → install_bundle`. Si ya estaba registrado,
basta reiniciar DeepSeek.

**3. En QGIS**: `Complementos` → **QGIS MCP** → **Start Server**
(debe decir `Server: Running on port 9876`).

Luego, en el chat: *«haz ping a QGIS»* → `{"pong": true}`.

> **Cada vez que abras QGIS** hay que pulsar **Start Server**: el plugin no tiene autoarranque.

## Verificación sin QGIS

```powershell
.\verificar.ps1
```

Salida esperada: `Servidor: Qgis_mcp 1.3.0`, `Herramientas: 15`, `RESULTADO: OK`.

## Qué arregla este kit

El repo original está pensado para Claude Desktop y tiene tres defectos que rompen la
integración en cualquier cliente MCP por stdio:

1. **`print()` a stdout** en `qgis_mcp_server.py` (3 sitios): si QGIS no está escuchando,
   el texto contamina el canal JSON-RPC y el cliente MCP no registra ninguna herramienta.
   → se redirige a `stderr`.
2. **Comprobación de conexión rota**: usaba `_qgis_connection.sock` (el atributo real es
   `.socket`), así que lanzaba `AttributeError` y **reconectaba en cada llamada**,
   saturando el servidor de QGIS, que atiende un único cliente (`listen(1)`).
   → se valida con `getpeername()`; la conexión pasa a ser realmente persistente.
3. **Socket muerto no se cerraba** tras un fallo de envío.
   → se cierra para que la siguiente llamada reconecte sola.

Además el comando del README (`uv run --directory <repo> qgis_mcp_server.py`) **falla con
uv ≥ 0.13** (`Failed to spawn`). La forma correcta, ya configurada en el bundle, es:

```text
uv run --project <repo> --directory <repo>\src\qgis_mcp qgis_mcp_server.py
```

## Problemas típicos

| Síntoma | Solución |
|---|---|
| `uv sync fallo` | Sin internet o uv muy antiguo. `uv self update`. |
| No aparecen herramientas `mcp__qgis__*` | Falta registrar el bundle (paso 2) o reiniciar DeepSeek. |
| `Could not connect to Qgis` | El dock de QGIS MCP no está en `Running`: pulsa **Start Server**. |
| `[WinError 10048]` al iniciar en QGIS | Puerto 9876 ocupado por otra instancia; ciérrala o cambia el puerto en el dock (y en `qgis_mcp_server.py`). |
| El plugin no sale en QGIS | `Complementos → Administrar complementos → Todos → "QGIS MCP" → marcar`. |

## Desinstalar

1. En DeepSeek: `plugin_manager → remove_bundle` con `@local/qgis-mcp`.
2. Borra la carpeta del bundle (`mcp-qgis-bundle`).
3. En QGIS: desmarca el plugin y borra `%APPDATA%\QGIS\QGIS3\profiles\default\python\plugins\qgis_mcp_plugin`.
4. Opcional: borra `C:\Users\GEOMATICA\qgis_mcp\.venv`.
