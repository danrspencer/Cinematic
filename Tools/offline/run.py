"""Runs an offline tool with Python's lupa (Lua 5.1) instead of lua5.1, for
PCs without it (Windows). From the repo root:

    python -I Tools/offline/run.py Tools/offline/check.lua
    python -I Tools/offline/run.py Tools/offline/export.lua > profiles.json

Needs lupa (pip install lupa). The tools start a run of their own per client
through CINE_LUA, which this sets to itself, so no lua5.1 is ever looked for.
(Never a lua5.1 shim on PATH instead: Windows asks what to open it with.)
"""
import os
import sys

import lupa.lua51 as lua51


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python -I Tools/offline/run.py <script.lua> [args...]")
    # (Quoted only where there's a space: cmd.exe strips a command's first
    # and last quotes, which breaks two quoted paths in a row.)
    def arg(path):
        return '"%s"' % path if " " in path else path
    script = os.path.relpath(os.path.abspath(__file__)).replace("\\", "/")
    os.environ["CINE_LUA"] = "%s -I %s" % (arg(sys.executable), arg(script))
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    args = {i: a for i, a in enumerate(sys.argv[1:])}
    lua.globals().arg = lua.table_from(args)
    chunk = lua.eval("function(path) return assert(loadfile(path)) end")(sys.argv[1])
    chunk(*sys.argv[2:])


if __name__ == "__main__":
    main()
