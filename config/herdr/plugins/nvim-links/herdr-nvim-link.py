#!/usr/bin/env python3
"""Herdr link handler: Ctrl-clicked file:// links open in the workspace's nvim tab.

Text files go to Neovim (a running one in the "nvim" tab via RPC, else a new
one), anything else to the macOS default app. HERDR_NVIM_LINK_DEBUG=1 in
Herdr's environment traces to stderr (`herdr plugin log list`) and to
$HERDR_PLUGIN_STATE_DIR/debug.log.
"""

import fcntl
import glob
import json
import logging
import os
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote, urlsplit

log = logging.getLogger("nvim-link")
STATE = Path(os.environ["HERDR_PLUGIN_STATE_DIR"])


def api(method, **params):
    log.debug("herdr %s %s", method, params)
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(10)
        sock.connect(os.environ["HERDR_SOCKET_PATH"])
        sock.sendall(json.dumps({"id": "nvim-link", "method": method, "params": params}).encode() + b"\n")
        response = json.loads(sock.makefile("rb").readline())
    if "error" in response:
        raise RuntimeError(f"{method}: {response['error']}")
    return response["result"]


def local_path(url):
    parts = urlsplit(url)
    if parts.scheme != "file" or parts.hostname not in (None, "localhost", socket.gethostname().lower()):
        raise ValueError(f"not a local file URL: {url}")
    path = Path(unquote(parts.path))
    if not path.is_absolute() or any(c < " " or c == "\x7f" for c in str(path)):
        raise ValueError(f"refusing path: {path!r}")
    if not path.exists():
        raise FileNotFoundError(path)
    return path


def is_text(path):
    if not path.is_file():
        return False
    mime = subprocess.check_output(["file", "-Lb", "--mime-type", path], text=True).strip()
    log.debug("%s is %s", path, mime)
    return mime == "inode/x-empty" or mime.startswith("text/") or mime.endswith(
        ("+json", "+xml", "/json", "/xml", "/javascript", "/toml", "/yaml", "/x-yaml", "/sql", "/x-shellscript")
    )


def foreground(pane_id):
    info = api("pane.process_info", pane_id=pane_id)["process_info"]
    info.setdefault("foreground_processes", [])
    return info


def nvim_pid(info):
    return next((p["pid"] for p in info["foreground_processes"] if p["name"] == "nvim"), None)


def is_idle_shell(info):
    procs = info["foreground_processes"]
    return bool(procs) and all(p["pid"] == info.get("shell_pid") for p in procs)


def nvim_server(pid):
    # Neovim's default listen socket is stdpath("run")/<app>.<pid>.0; the TUI
    # process delegates to an `nvim --embed` child, which is the one listening.
    # ponytail: assumes nvim and Herdr share TMPDIR; use `lsof -p <pid> -U` if that drifts.
    children = subprocess.run(["pgrep", "-P", str(pid), "-x", "nvim"], capture_output=True, text=True).stdout.split()
    run_dir = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    for candidate in [pid, *children]:
        for server in glob.glob(f"{run_dir}/nvim.*/*/*.{candidate}.0"):
            return server
    return None


def wait(ready, what, timeout=10):
    deadline = time.monotonic() + timeout
    while not ready():
        if time.monotonic() > deadline:
            raise TimeoutError(f"timed out waiting for {what}")
        time.sleep(0.1)


def open_in_nvim(nvim, server, path):
    # Vim single-quoted strings escape ' by doubling; nvim_cmd's structured args
    # avoid Ex-command injection and filename expansion.
    quoted = "'" + str(path).replace("'", "''") + "'"
    expr = f"luaeval('vim.api.nvim_cmd({{cmd=\"drop\", args={{_A}}, magic={{file=false, bar=false}}}}, {{}})', {quoted})"
    log.debug("nvim --server %s", server)
    subprocess.run([nvim, "--server", server, "--remote-expr", expr], check=True, capture_output=True, text=True, timeout=10)


def start_nvim(nvim, pane_id, path):
    wait(lambda: is_idle_shell(foreground(pane_id)), "a shell prompt")
    api("pane.send_keys", pane_id=pane_id, keys=["ctrl+u"])
    api("pane.send_input", pane_id=pane_id, text=shlex.join([nvim, "--", str(path)]), keys=["Enter"])
    # Hold the lock until the editor is reachable so a second click reuses it.
    wait(lambda: (pid := nvim_pid(foreground(pane_id))) and nvim_server(pid), "nvim to start")


def route(nvim, context, path):
    """Open path per the rules; return the pane to focus."""
    ws, origin_tab, origin_pane = context["workspace_id"], context["tab_id"], context["focused_pane_id"]
    nvim_tabs = {t["tab_id"] for t in api("tab.list", workspace_id=ws)["tabs"] if t["label"] == "nvim"}
    panes = [p for p in api("pane.list", workspace_id=ws)["panes"] if p["tab_id"] in nvim_tabs]
    panes.sort(key=lambda p: p["tab_id"] != origin_tab)  # prefer the clicked nvim tab
    infos = {p["pane_id"]: foreground(p["pane_id"]) for p in panes}
    for p in panes:
        if pid := nvim_pid(infos[p["pane_id"]]):
            server = nvim_server(pid)
            if not server:
                raise RuntimeError(f"nvim (pid {pid}) in {p['pane_id']} has no listen socket")
            open_in_nvim(nvim, server, path)
            return p["pane_id"]

    cwd = context.get("focused_pane_cwd") or str(path.parent)
    if origin_tab in nvim_tabs:
        idle = [p["pane_id"] for p in panes if p["tab_id"] == origin_tab and is_idle_shell(infos[p["pane_id"]])]
        pane_id = idle[0] if idle else api("pane.split", target_pane_id=origin_pane, direction="right", cwd=cwd)["pane"]["pane_id"]
    else:
        pane_id = api("tab.create", workspace_id=ws, label="nvim", cwd=cwd)["root_pane"]["pane_id"]
    start_nvim(nvim, pane_id, path)
    return pane_id


def main():
    context = json.loads(os.environ["HERDR_PLUGIN_CONTEXT_JSON"])
    log.debug("context %s", context)
    path = local_path(context["clicked_url"])
    if not is_text(path):
        subprocess.run(["open", path], check=True)
        return
    nvim = shutil.which("nvim")
    if not nvim:
        raise RuntimeError("nvim not on Herdr's PATH")
    with open(STATE / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)  # ponytail: one global lock; per-workspace if clicks ever queue noticeably
        api("pane.focus", pane_id=route(nvim, context, path))


if __name__ == "__main__":
    if os.environ.get("HERDR_NVIM_LINK_DEBUG"):
        logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(message)s",
                            handlers=[logging.StreamHandler(), logging.FileHandler(STATE / "debug.log")])
    try:
        main()
    except Exception as error:
        log.debug("failed", exc_info=True)
        sys.exit(f"herdr-nvim-link: {error}")
