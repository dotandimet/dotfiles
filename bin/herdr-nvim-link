#!/usr/bin/env python3
"""Herdr local-file Ctrl-click handler (macOS, Python 3; no extra packages).

Deploy with mise dotfiles apply, then register once:
    herdr plugin link ~/.config/herdr/plugins/nvim-links
Restart existing LazyVim instances after deploying the RPC registration.
Tracing is off by default. Set HERDR_NVIM_LINK_DEBUG=1 in the plugin's
launch environment to enable it (exporting inside a pane does not update an
already-running Herdr server). Unset, empty, 0, false, no, or off disables it.
Failures still produce a concise stderr message when tracing is disabled.
Live JSONL trace: ${XDG_CACHE_HOME:-~/.cache}/herdr-nvim-links/clicks.log
The same trace is on stderr: herdr plugin log list --plugin dotfiles.nvim-links
With debugging enabled, each click has a run ID. handler.start confirms dispatch reached Python;
handler.done means routing completed. No handler.start? Check Herdr's plugin
log for launch errors (missing executable/interpreter) or an unmatched click.
Logs contain local paths and process/socket IDs, but not file contents or the
full environment. They append until manually removed; do not commit them.

All file:// clicks are consumed by the plugin. Text goes to Neovim; other
local files go to macOS's default app. Errors never fall through to `open`.
"""

from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import stat
import subprocess
import sys
import time
import traceback
from urllib.parse import unquote, urlsplit


CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "herdr-nvim-links"
LOG_PATH = CACHE / "clicks.log"
DEBUG = os.environ.get("HERDR_NVIM_LINK_DEBUG", "").strip().lower() not in {"", "0", "false", "no", "off"}
STARTED = time.monotonic()
RUN_ID = f"{os.getpid()}-{time.time_ns()}"
LOG_FILE = None
LAST_VALUES = {}


def log(event, **fields):
    global LOG_FILE
    if not DEBUG:
        return
    line = json.dumps({
        "time": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "run": RUN_ID,
        "elapsed_ms": round((time.monotonic() - STARTED) * 1000),
        "event": event,
        **fields,
    }, ensure_ascii=True)
    print(line, file=sys.stderr, flush=True)
    if LOG_FILE is not None:
        try:
            print(line, file=LOG_FILE, flush=True)
        except OSError as error:
            # Diagnostics must not change click handling if logging fails.
            LOG_FILE = None
            print(f"herdr-nvim-link: file logging failed: {error}", file=sys.stderr, flush=True)


def setup_logging():
    global LOG_FILE
    if not DEBUG:
        return
    try:
        CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        LOG_FILE = os.fdopen(fd, "a", encoding="utf-8")
    except OSError as error:
        log("logging.unavailable", path=str(LOG_PATH), error=str(error))


def log_change(event, key, **fields):
    if not DEBUG:
        return
    # Polling can run every 100 ms: report the first observation and changes,
    # not hundreds of identical snapshots while waiting for shell/editor startup.
    identity = (event, key)
    if LAST_VALUES.get(identity) != fields:
        LAST_VALUES[identity] = fields
        log(event, **fields)


def api(method, *, trace_io=True, **params):
    """The Unix socket also exposes pane.focus (no direct CLI equivalent)."""
    if trace_io:
        log("herdr.request", method=method, params=params)
    started = time.monotonic()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(10)
            client.connect(os.environ["HERDR_SOCKET_PATH"])
            request = {"id": RUN_ID, "method": method, "params": params}
            client.sendall(json.dumps(request).encode() + b"\n")
            with client.makefile("rb") as reader:
                response = json.loads(reader.readline())
        if "error" in response:
            raise RuntimeError(f"{method}: {response['error']}")
        result = response["result"]
    except Exception as error:
        log("herdr.failed", method=method, params=params, error=str(error))
        raise
    if trace_io:
        log("herdr.response", method=method, result_type=result.get("type"),
            duration_ms=round((time.monotonic() - started) * 1000))
    return result


def local_path(url):
    parsed = urlsplit(url)
    hosts = {"", "localhost", socket.gethostname().lower(), socket.getfqdn().lower()}
    if parsed.scheme != "file" or parsed.netloc.lower() not in hosts:
        raise ValueError("Only local file:// links are supported; refusing a remote host")
    path = unquote(parsed.path, errors="strict")
    if not path.startswith("/") or any(ord(c) < 32 or ord(c) == 127 for c in path):
        raise ValueError("Expected an absolute file path without control characters")
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(path)
    return path


def is_text(path):
    # Inspect contents, not extensions: extensionless files and dotfiles work,
    # and renaming a binary to .md does not send it to the editor.
    if not path.is_file():
        log("file.classified", path=str(path), text=False, reason="not a regular file")
        return False
    if path.stat().st_size == 0:
        log("file.classified", path=str(path), text=True, reason="empty file")
        return True
    log("file.inspect", path=str(path), tool="/usr/bin/file")
    mime = subprocess.run(
        ["/usr/bin/file", "-L", "-b", "--mime-type", "--", str(path)],
        check=True, capture_output=True, text=True, timeout=5,
    ).stdout.strip()
    text = (
        mime.startswith("text/")
        or mime.endswith(("+json", "+xml"))
        or mime in {"application/json", "application/xml", "application/javascript",
                    "application/toml", "application/yaml", "application/x-yaml",
                    "application/sql", "application/x-shellscript"}
    )
    log("file.classified", path=str(path), mime=mime, text=text)
    return text


def processes(pane):
    info = api("pane.process_info", trace_io=False, pane_id=pane["pane_id"])["process_info"]
    log_change("pane.processes", pane["pane_id"], pane_id=pane["pane_id"],
               shell_pid=info.get("shell_pid"),
               foreground_process_group_id=info.get("foreground_process_group_id"),
               processes=[{k: p.get(k) for k in ("pid", "name", "argv0")}
                          for p in info.get("foreground_processes", [])])
    return info


def nvim_processes(info):
    return [p for p in info.get("foreground_processes", [])
            if Path(p.get("argv0") or p["name"]).name == "nvim"]


def idle_shell(info):
    procs = info.get("foreground_processes", [])
    return bool(procs) and all(
        p["pid"] == info.get("shell_pid")
        and Path(p.get("argv0") or p["name"]).name.lstrip("-") in {"bash", "zsh", "sh", "fish"}
        for p in procs
    )


def registration_for(pid):
    # Do not pin the registration to its original pane ID: panes can move
    # between workspaces. The caller establishes process ownership instead.
    record_path = CACHE / f"{pid}.json"
    try:
        record = json.loads(record_path.read_text())
    except FileNotFoundError:
        log_change("nvim.registration", pid, pid=pid,
                   path=str(record_path), status="missing")
        return None
    matches = (record.get("pid") == pid
               and record.get("herdr_socket") == os.environ["HERDR_SOCKET_PATH"])
    log_change("nvim.registration", pid, pid=pid,
               path=str(record_path), status="matched" if matches else "mismatch",
               registered_pid=record.get("pid"), server=record.get("server"),
               registered_herdr_socket=record.get("herdr_socket"),
               expected_herdr_socket=os.environ["HERDR_SOCKET_PATH"])
    if matches:
        return {"pid": pid, "server": record["server"]}
    return None


def server_for(proc):
    # Herdr sees the foreground TUI process. With Neovim's split UI/core
    # architecture, init.lua and RPC run in its direct `nvim --embed` child,
    # which need not belong to the foreground process group. Older/single-
    # process Neovim instances register the foreground PID itself.
    registration = registration_for(proc["pid"])
    if registration is None:
        result = subprocess.run(
            ["/bin/ps", "-U", str(os.getuid()), "-o", "pid=,ppid=,comm="],
            check=True, capture_output=True, text=True, timeout=5,
        )
        children = []
        for line in result.stdout.splitlines():
            fields = line.strip().split(None, 2)
            if len(fields) != 3:
                continue
            pid, parent_pid, executable = fields
            if int(parent_pid) == proc["pid"] and Path(executable).name == "nvim":
                children.append(int(pid))
        log_change("nvim.children", proc["pid"], foreground_pid=proc["pid"], child_pids=children)
        # Only direct Neovim children of the selected foreground process are
        # eligible. Never pick an arbitrary cache entry or a descendant editor
        # running inside an unrelated nested terminal job.
        matches = [record for pid in children if (record := registration_for(pid)) is not None]
        if len(matches) > 1:
            raise RuntimeError("Multiple registered Neovim children; refusing an ambiguous RPC target")
        if not matches:
            return None
        registration = matches[0]
    log_change("nvim.server_resolved", proc["pid"], foreground_pid=proc["pid"],
               rpc_pid=registration["pid"], server=registration["server"])
    return registration


def remote(nvim, server, expression, *, operation):
    log("nvim.rpc.start", operation=operation, executable=nvim, server=server)
    started = time.monotonic()
    result = subprocess.run(
        [nvim, "--server", server, "--remote-expr", expression],
        capture_output=True, text=True, timeout=10,
    )
    log("nvim.rpc.result", operation=operation, returncode=result.returncode,
        stdout=result.stdout.strip()[:2000], stderr=result.stderr.strip()[:2000],
        duration_ms=round((time.monotonic() - started) * 1000))
    if result.returncode:
        raise RuntimeError(f"Neovim RPC failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def open_existing(nvim, proc, pane, path):
    registration = server_for(proc)
    if not registration:
        raise RuntimeError("Neither the foreground Neovim nor its Neovim child has a link registration; check LazyVim config/startup")
    server = registration["server"]
    rpc_pid = registration["pid"]
    if remote(nvim, server, "getpid()", operation="verify_pid") != str(rpc_pid):
        raise RuntimeError("Stale Neovim RPC registration; refusing to target another process")
    log("nvim.verified", foreground_pid=proc["pid"], rpc_pid=rpc_pid, pane_id=pane["pane_id"])
    # Vim single-quoted strings escape quotes by doubling them. nvim_cmd's
    # structured args avoid Ex-command injection and filename expansion.
    quoted_path = "'" + str(path).replace("'", "''") + "'"
    expression = (
        "luaeval('vim.api.nvim_cmd({cmd=\"drop\", args={_A}, "
        "magic={file=false, bar=false}}, {})', " + quoted_path + ")"
    )
    remote(nvim, server, expression, operation="open_file")
    log("nvim.opened", path=str(path), pane_id=pane["pane_id"],
        foreground_pid=proc["pid"], rpc_pid=rpc_pid)
    api("pane.focus", pane_id=pane["pane_id"])
    log("pane.focused", pane_id=pane["pane_id"])


def start_nvim(nvim, pane, path):
    # New shells may still be starting. Never paste a command into an agent,
    # editor, or other foreground program.
    log("shell.wait", pane_id=pane["pane_id"], timeout_seconds=10)
    deadline = time.monotonic() + 10
    while not idle_shell(processes(pane)):
        if time.monotonic() >= deadline:
            raise RuntimeError("Target pane did not become an idle shell; no command sent")
        time.sleep(0.1)
    log("shell.ready", pane_id=pane["pane_id"])
    log("nvim.launch", pane_id=pane["pane_id"], executable=nvim, path=str(path))
    api("pane.send_keys", pane_id=pane["pane_id"], keys=["ctrl+u"])
    api("pane.send_input", pane_id=pane["pane_id"],
        text=shlex.join([nvim, "--", str(path)]), keys=["Enter"])
    log("nvim.command_sent", pane_id=pane["pane_id"])
    api("pane.focus", pane_id=pane["pane_id"])
    log("pane.focused", pane_id=pane["pane_id"])
    # Keep the per-workspace lock until startup registers the editor, so a
    # rapid second click reuses it instead of opening another tab.
    log("nvim.registration_wait", pane_id=pane["pane_id"], timeout_seconds=15)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        for proc in nvim_processes(processes(pane)):
            registration = server_for(proc)
            if registration:
                log("nvim.registered", pane_id=pane["pane_id"],
                    foreground_pid=proc["pid"], rpc_pid=registration["pid"])
                return
        time.sleep(0.1)
    raise RuntimeError("Neovim was launched but did not register RPC; check its startup/config")


def route(nvim, context, path):
    origin = api("pane.get", pane_id=context["focused_pane_id"])["pane"]
    workspace = context["workspace_id"]
    log("origin.resolved", pane_id=origin["pane_id"], tab_id=origin["tab_id"],
        workspace_id=origin["workspace_id"])
    if origin["workspace_id"] != workspace or origin["tab_id"] != context["tab_id"]:
        raise RuntimeError("The clicked pane moved; click the link again")
    tabs = api("tab.list", workspace_id=workspace)["tabs"]
    editor_tabs = {t["tab_id"] for t in tabs if t["label"] == "nvim"}
    panes = api("pane.list", workspace_id=workspace)["panes"]
    candidates = [p for p in panes if p["tab_id"] in editor_tabs]
    # Prefer the clicked pane/tab if there are multiple tabs named nvim.
    candidates.sort(key=lambda p: (p["tab_id"] != origin["tab_id"], p["pane_id"] != origin["pane_id"]))
    log("route.candidates", tabs=[{k: t[k] for k in ("tab_id", "label")} for t in tabs],
        pane_ids=[p["pane_id"] for p in candidates])
    infos = {p["pane_id"]: processes(p) for p in candidates}
    for pane in candidates:
        editors = nvim_processes(infos[pane["pane_id"]])
        if editors:
            log("route.selected", branch="reuse_nvim", pane_id=pane["pane_id"], pid=editors[0]["pid"])
            open_existing(nvim, editors[0], pane, path)
            return

    cwd = origin.get("foreground_cwd") or origin.get("cwd") or str(path.parent)
    if origin["tab_id"] in editor_tabs:
        # Stay in the clicked nvim tab. If it is busy, add a split rather than
        # interrupting its foreground program or sending it shell commands.
        idle = [p for p in candidates if p["tab_id"] == origin["tab_id"]
                and idle_shell(infos[p["pane_id"]])]
        log("route.selected", branch="start_in_idle_pane" if idle else "split_clicked_tab",
            tab_id=origin["tab_id"])
        pane = idle[0] if idle else api(
            "pane.split", workspace_id=workspace, target_pane_id=origin["pane_id"],
            direction="right", cwd=cwd, focus=False,
        )["pane"]
    else:
        log("route.selected", branch="create_nvim_tab", workspace_id=workspace, cwd=cwd)
        pane = api("tab.create", workspace_id=workspace, label="nvim", cwd=cwd, focus=False)["root_pane"]
    log("route.target", pane_id=pane["pane_id"], tab_id=pane["tab_id"], workspace_id=pane["workspace_id"])
    start_nvim(nvim, pane, path)


def main():
    if os.environ.get("HERDR_ENV") != "1":
        raise RuntimeError("Run this through the Herdr nvim-links plugin")
    context = json.loads(os.environ["HERDR_PLUGIN_CONTEXT_JSON"])
    log("context.received", **{k: context.get(k) for k in (
        "invocation_source", "clicked_url", "workspace_id", "tab_id", "focused_pane_id", "link_handler_id",
    )})
    if context.get("invocation_source") != "link_click":
        raise RuntimeError("This action requires a link click with originating pane context")
    log("file.validate", url=context["clicked_url"])
    path = local_path(context["clicked_url"])
    log("file.local", path=str(path))
    mode = path.stat().st_mode
    if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
        raise ValueError("Refusing to open a device, socket, or other special file")
    if not is_text(path):
        log("route.selected", branch="default_app", path=str(path))
        subprocess.run(["/usr/bin/open", str(path)], check=True, timeout=10)
        log("default_app.dispatched", path=str(path))
        return
    nvim = shutil.which("nvim")
    log("nvim.executable", path=nvim)
    if not nvim:
        raise RuntimeError("nvim is not on Herdr's PATH")
    state = Path(os.environ["HERDR_PLUGIN_STATE_DIR"])
    key = os.environ["HERDR_SOCKET_PATH"] + "\0" + context["workspace_id"]
    lock = state / (hashlib.sha256(key.encode()).hexdigest() + ".lock")
    log("lock.wait", path=str(lock))
    with lock.open("w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        log("lock.acquired", path=str(lock))
        route(nvim, context, path)
    log("lock.released", path=str(lock))


if __name__ == "__main__":
    setup_logging()
    log("handler.start", script=str(Path(__file__).resolve()), python=sys.executable,
        log_path=str(LOG_PATH), file_logging=LOG_FILE is not None,
        herdr_env=os.environ.get("HERDR_ENV"),
        herdr_socket=os.environ.get("HERDR_SOCKET_PATH"),
        plugin_id=os.environ.get("HERDR_PLUGIN_ID"),
        action_id=os.environ.get("HERDR_PLUGIN_ACTION_ID"))
    try:
        main()
        log("handler.done")
    except Exception as error:
        if DEBUG:
            details = {}
            if isinstance(error, subprocess.SubprocessError):
                # TimeoutExpired output can be bytes even with text=True.
                for name in ("stdout", "stderr"):
                    output = getattr(error, name, None)
                    if isinstance(output, bytes):
                        output = output.decode(errors="replace")
                    if output:
                        details[name] = output[:2000]
            log("handler.failed", error_type=type(error).__name__, error=str(error),
                traceback=traceback.format_exc(), **details)
        else:
            print(f"herdr-nvim-link: {error}", file=sys.stderr)
        sys.exit(1)
    finally:
        if LOG_FILE is not None:
            LOG_FILE.close()
