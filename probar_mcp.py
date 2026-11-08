#!/usr/bin/env python3
"""
Prueba el puente MCP lanzandolo igual que lo hace DeepSeek (stdio) y lista
las herramientas que expone. NO necesita QGIS abierto: valida el servidor MCP.

Uso:
    python probar_mcp.py --repo "C:\\Users\\GEOMATICA\\qgis_mcp" \
                         --uv   "C:\\Users\\GEOMATICA\\.local\\bin\\uv.exe"
"""
import argparse
import asyncio
import os
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def run(repo, uv, timeout_s):
    params = StdioServerParameters(
        command=uv,
        args=[
            "run",
            "--project",
            repo,
            "--directory",
            os.path.join(repo, "src", "qgis_mcp"),
            "qgis_mcp_server.py",
        ],
    )
    print(f"Lanzando: {uv} run --project {repo} --directory {repo}\\src\\qgis_mcp qgis_mcp_server.py")

    async def inner():
        async with stdio_client(params) as (read, write):
            async with ClientSession(read, write) as session:
                init = await session.initialize()
                print(f"Servidor: {init.serverInfo.name} {init.serverInfo.version}")
                tools = await session.list_tools()
                print(f"Herramientas: {len(tools.tools)}")
                for t in tools.tools:
                    print(f"  - {t.name}")
                return len(tools.tools)

    return await asyncio.wait_for(inner(), timeout=timeout_s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=r"C:\Users\GEOMATICA\qgis_mcp")
    ap.add_argument("--uv", default=r"C:\Users\GEOMATICA\.local\bin\uv.exe")
    ap.add_argument("--timeout", type=float, default=120.0)
    a = ap.parse_args()

    try:
        n = asyncio.run(run(a.repo, a.uv, a.timeout))
    except Exception as e:
        print(f"FALLO: {type(e).__name__}: {e}")
        return 1
    if n >= 10:
        print("RESULTADO: OK")
        return 0
    print(f"RESULTADO: inesperado ({n} herramientas)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
