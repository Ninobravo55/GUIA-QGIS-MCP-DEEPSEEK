#!/usr/bin/env python3
"""
Aplica los 3 parches necesarios al repo qgis_mcp para que funcione con
DeepSeek Harness (o cualquier cliente MCP por stdio) de forma fiable.

Es idempotente: si un parche ya esta aplicado lo reporta y no toca el archivo.

Uso:
    python aplicar_parches.py "C:\\Users\\GEOMATICA\\qgis_mcp"
"""
import io
import pathlib
import sys

SERVER = "src/qgis_mcp/qgis_mcp_server.py"
CLIENT = "src/qgis_mcp/qgis_socket_client.py"

OLD_LIVENESS = """    # If we have an existing connection, check if it's still valid
    if _qgis_connection is not None:
        # Test if the connection is still alive with a simple ping
        try:
            # Just try to send a small message to check if the socket is still connected
            _qgis_connection.sock.sendall(b'')
            return _qgis_connection
"""

NEW_LIVENESS = """    # If we have an existing connection, check if it's still valid
    if _qgis_connection is not None:
        # Comprobar que el socket sigue vivo (getpeername falla si se cerro).
        # Antes esto usaba un atributo inexistente ('sock'), lo que provocaba
        # reconectar en CADA llamada y saturaba el servidor de un solo cliente.
        try:
            if _qgis_connection.socket is None:
                raise RuntimeError("socket cerrado")
            _qgis_connection.socket.getpeername()
            return _qgis_connection
"""

OLD_SEND_ERR = """        except Exception as e:
            print(f"Error sending command: {str(e)}", file=sys.stderr)
            return None
"""

NEW_SEND_ERR = """        except Exception as e:
            print(f"Error sending command: {str(e)}", file=sys.stderr)
            # Cerrar el socket muerto para que la proxima llamada reconecte
            try:
                self.disconnect()
            except Exception:
                pass
            return None
"""


def edit(s, old, new):
    """Reemplazo unico con deteccion de estado."""
    if new in s:
        return s, "ya aplicado"
    if old not in s:
        return s, "NO ENCONTRADO"
    return s.replace(old, new, 1), "aplicado"


def main() -> int:
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\GEOMATICA\qgis_mcp")
    if not (repo / SERVER).exists():
        print(f"ERROR: no existe {repo / SERVER}")
        return 2

    print(f"Repo: {repo}")
    rc = 0

    # ---------------- qgis_mcp_server.py ----------------
    path = repo / SERVER
    s = path.read_text(encoding="utf-8")
    steps = []

    s, st = edit(s, "import json\n", "import json\nimport sys\n")
    steps.append(("import sys", st))

    for label, old, new in [
        ("print de conexion -> stderr",
         'print(f"Error connecting to server: {str(e)}")',
         'print(f"Error connecting to server: {str(e)}", file=sys.stderr)'),
        ("print 'not connected' -> stderr",
         'print("Not connected to server")',
         'print("Not connected to server", file=sys.stderr)'),
        ("print de envio -> stderr",
         'print(f"Error sending command: {str(e)}")',
         'print(f"Error sending command: {str(e)}", file=sys.stderr)'),
    ]:
        s, st = edit(s, old, new)
        steps.append((label, st))

    s, st = edit(s, OLD_LIVENESS, NEW_LIVENESS)
    steps.append(("conexion persistente (sock -> socket)", st))

    s, st = edit(s, OLD_SEND_ERR, NEW_SEND_ERR)
    steps.append(("cerrar socket muerto al fallar", st))

    path.write_text(s, encoding="utf-8", newline="\n")
    for label, st in steps:
        print(f"  [{'OK' if st != 'NO ENCONTRADO' else 'AVISO'}] {label}: {st}")
        if st == "NO ENCONTRADO":
            rc = 1

    # ---------------- qgis_socket_client.py (CLI opcional) ----------------
    path = repo / CLIENT
    if path.exists():
        s = path.read_text(encoding="utf-8")
        steps = []
        for label, old, new in [
            ("print de conexion -> stderr",
             'print(f"Error connecting to server: {str(e)}")',
             'print(f"Error connecting to server: {str(e)}", file=sys.stderr)'),
            ("print 'not connected' -> stderr",
             'print("Not connected to server")',
             'print("Not connected to server", file=sys.stderr)'),
            ("print de envio -> stderr",
             'print(f"Error sending command: {str(e)}")',
             'print(f"Error sending command: {str(e)}", file=sys.stderr)'),
        ]:
            s, st = edit(s, old, new)
            steps.append((label, st))
        path.write_text(s, encoding="utf-8", newline="\n")
        for label, st in steps:
            print(f"  [{'OK' if st != 'NO ENCONTRADO' else 'AVISO'}] cliente: {label}: {st}")

    # Verificacion de sintaxis
    for rel in (SERVER, CLIENT):
        p = repo / rel
        if not p.exists():
            continue
        try:
            compile(p.read_text(encoding="utf-8"), str(p), "exec")
        except SyntaxError as e:
            print(f"ERROR de sintaxis en {rel}: {e}")
            rc = 1
    print("Sintaxis OK" if rc == 0 else "Revisar avisos")
    return rc


if __name__ == "__main__":
    sys.exit(main())
