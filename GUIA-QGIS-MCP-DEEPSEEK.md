# QGIS + DeepSeek Harness (MCP) — configuración y uso

Integración basada en <https://github.com/jjsantos01/qgis_mcp>, adaptada a **DeepSeek Harness**
en lugar de Claude Desktop.

---

## 1. Cómo quedó armado

```
DeepSeek Harness  ──MCP/stdio──▶  uv run qgis_mcp_server.py  ──socket TCP 9876──▶  Plugin QGIS
     (modelo)                       (puente Python)                                (dentro de QGIS)
```

| Pieza | Ubicación |
|---|---|
| Repo clonado | `C:\Users\GEOMATICA\qgis_mcp` |
| Entorno Python (creado con uv) | `C:\Users\GEOMATICA\qgis_mcp\.venv` |
| Puente MCP | `C:\Users\GEOMATICA\qgis_mcp\src\qgis_mcp\qgis_mcp_server.py` |
| Plugin de QGIS | `%APPDATA%\QGIS\QGIS3\profiles\default\python\plugins\qgis_mcp_plugin` |
| uv | `C:\Users\GEOMATICA\.local\bin\uv.exe` |
| Bundle de configuración MCP | `...\default-workspace\mcp-qgis-bundle\` |
| Registro del bundle en el perfil | `C:\Users\GEOMATICA\.dsh\profiles\desktop\package.json` |

El bundle `@local/qgis-mcp` inserta el plugin `@deepseek-ai/dsh-mcp-client` con
`serverName: qgis`, por lo que las herramientas aparecen en DeepSeek como
`mcp__qgis__<herramienta>`.

Contenido efectivo del registro (`mcp-qgis-bundle/cordis.patch.yml`):

```yaml
- insert:
    - id: qgis-mcp
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: qgis
        transport: stdio
        command: 'C:\Users\GEOMATICA\.local\bin\uv.exe'
        args:
          - run
          - --project
          - 'C:\Users\GEOMATICA\qgis_mcp'
          - --directory
          - 'C:\Users\GEOMATICA\qgis_mcp\src\qgis_mcp'
          - qgis_mcp_server.py
        cwd: 'C:\Users\GEOMATICA\qgis_mcp\src\qgis_mcp'
        env:
          PYTHONUTF8: '1'
          PYTHONIOENCODING: 'utf-8'
          PYTHONUNBUFFERED: '1'
        toolCallTimeoutMs: 180000
        failOnStartupError: false
```

> Nota: el `--directory` + `run qgis_mcp_server.py` del README **no funciona** con uv 0.13.7
> (`Failed to spawn: qgis_mcp_server.py`). La combinación que sí funciona es
> `run --project <repo> --directory <repo>\src\qgis_mcp qgis_mcp_server.py`, que es la usada arriba.

---

## 2. Uso diario (2 pasos)

1. **En QGIS**, cada vez que lo abras:
   - Menú `Complementos` (`Plugins`) → **QGIS MCP** (activa el dock).
   - En el dock, pulsa **Start Server**. Debe decir `Server: Running on port 9876`.
   - Si cierras el dock o QGIS, el servidor se detiene: hay que volver a pulsar Start Server.
2. **En DeepSeek**, abre un chat nuevo y pide directamente, por ejemplo:

   - «Haz ping a QGIS y dime la versión instalada»
   - «Lista las capas del proyecto con su número de features»
   - «Carga el shapefile `D:\datos\predios.shp` como capa "Predios" y haz zoom»
   - «Ejecuta el algoritmo de centroides sobre la capa activa y guarda en GeoJSON»
   - «Renderiza el mapa actual a `D:\salidas\mapa.png` a 1600x1200»

   El modelo usa las herramientas `mcp__qgis__*` automáticamente.

### Herramientas disponibles (15)

`ping` · `get_qgis_info` · `load_project` · `create_new_project` · `get_project_info` ·
`add_vector_layer` · `add_raster_layer` · `get_layers` · `remove_layer` · `zoom_to_layer` ·
`get_layer_features` · `execute_processing` · `save_project` · `render_map` · `execute_code`

`execute_code` ejecuta PyQGIS arbitrario: es muy potente, úsalo con proyectos respaldados.

---

## 3. Verificación ya realizada

| Prueba | Resultado |
|---|---|
| `uv sync` del repo | OK (mcp 1.3.0, FastMCP) |
| Handshake MCP (`initialize` + `tools/list`) | 15 herramientas |
| `mcp__qgis__ping` | `{"pong": true}` |
| `mcp__qgis__get_qgis_info` | QGIS `3.44.15-Solothurn`, 13 plugins |
| `mcp__qgis__get_project_info` | CRS `EPSG:32718`, 2 capas |
| `mcp__qgis__get_layers` | `Centro_palma_altura_predio` (4862 features), `via` (7 features) |
| Llamadas consecutivas tras la corrección de persistencia | OK (sin reconectar en cada llamada) |

---

## 4. Cambios aplicados al repo clonado

1. `src\qgis_mcp\qgis_mcp_server.py`: `import sys` y los 3 `print(...)` de error ahora escriben a
   **stderr** (líneas 31, 43, 75). Sin esto, si QGIS no estaba escuchando, el texto
   `Error connecting to server: ...` se escribía en **stdout** y rompía el JSON-RPC de MCP:
   el servidor arrancaba pero DeepSeek no podía registrar las herramientas.
2. `src\qgis_mcp\qgis_socket_client.py`: misma corrección en el cliente CLI (líneas 24, 36, 68).
3. `src\qgis_mcp\qgis_mcp_server.py` → `get_qgis_connection()`: la comprobación de vida usaba
   `_qgis_connection.sock`, atributo que **no existe** (el real es `.socket`). El `AttributeError`
   hacía que se reconectara en *cada* llamada; y como el plugin de QGIS atiende **un solo cliente**
   (`listen(1)`), ese trajín acababa dejando el servidor sin responder. Ahora se valida con
   `socket.getpeername()` (conexión realmente persistente) y, si un envío falla, se cierra el socket
   muerto para que la siguiente llamada reconecte sola.
4. `.venv` creado con `uv sync` (no requiere volver a hacerse salvo que cambien dependencias).

Los cambios son locales; si actualizas el repo con `git pull`, revisa que no se pierdan.

---

## 5. Problemas típicos

| Síntoma | Causa / solución |
|---|---|
| No aparecen herramientas `mcp__qgis__*` | QGIS abierto pero **Start Server** sin pulsar, o DeepSeek iniciado antes de instalar el bundle (reinicia la app). |
| `Could not connect to Qgis` al usar una herramienta | El dock de QGIS MCP está en `Stopped` o cerrado. Pulsa Start Server. |
| `[WinError 10048]` al iniciar el servidor en QGIS | El puerto 9876 ya está ocupado (otra instancia de QGIS o el servidor quedó vivo). Cierra la otra instancia o cambia el puerto en el dock (y en `qgis_mcp_server.py`, que fija 9876). |
| `Failed to spawn: qgis_mcp_server.py` | Se usó el comando del README con uv 0.13.7. Usa `--project` + `--directory` como en la sección 1. |
| El plugin no aparece en QGIS | `Complementos` → `Administrar complementos` → pestaña **Todos** → busca «QGIS MCP» → marcar la casilla. |
| Cambiaste `cordis.patch.yml` | DeepSeek recarga la entrada, pero lo más fiable es reiniciar la aplicación. |

### Desactivar / quitar la integración

- Desactivar sin borrar: pide en DeepSeek «desactiva el bundle @local/qgis-mcp».
- Quitar del todo: `plugin_manager` → `remove_bundle` con `@local/qgis-mcp`.
- El bundle vive en `default-workspace\mcp-qgis-bundle` y está enlazado por *link*: **no borres ni
  muevas esa carpeta** mientras el bundle esté instalado.

---

## 6. Referencias

- Repo original: <https://github.com/jjsantos01/qgis_mcp>
- MCP: <https://modelcontextprotocol.io>
- uv: <https://docs.astral.sh/uv/>
