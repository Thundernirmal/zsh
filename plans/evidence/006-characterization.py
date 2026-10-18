import hashlib, os, pty, resource, select, subprocess, sys, time
# Usage: 006-characterization.py REPO LEGACY_FORMAT OUT_DIR full|reduced [RENDER_SCRIPT]
# RENDER_SCRIPT defaults to the retained sibling 006-characterization-render.zsh.
repo, legacy, out_dir, matrix = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
script = os.path.abspath(sys.argv[5]) if len(sys.argv) > 5 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "006-characterization-render.zsh")
if not os.path.isfile(script):
    sys.exit(f"render script not found: {script}")
os.makedirs(out_dir, exist_ok=True)
def limit(): resource.setrlimit(resource.RLIMIT_AS, (2 << 30, 2 << 30))
env = {"HOME": out_dir, "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "TERM": "xterm-256color"}
def run_pty(mode):
    pid, fd = pty.fork()
    if pid == 0:
        limit(); os.execve("/usr/bin/zsh", ["zsh", "-f", script, repo, mode, legacy, matrix], env)
    buf = b""; deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        r, _, _ = select.select([fd], [], [], 1)
        if r:
            try: chunk = os.read(fd, 65536)
            except OSError: break
            if not chunk: break
            buf += chunk
    _, status = os.waitpid(pid, 0); os.close(fd)
    return buf, os.waitstatus_to_exitcode(status)
def run_pipe(mode):
    p = subprocess.run(["zsh", "-f", script, repo, mode, legacy, matrix], env=env, capture_output=True, timeout=900, preexec_fn=limit)
    return p.stdout + b"\n--stderr--\n" + p.stderr, p.returncode
ok = True
for kind, fn in (("pty", run_pty), ("pipe", run_pipe)):
    res = {}
    for mode in ("frozen", "live"):
        t0 = time.monotonic(); data, rc = fn(mode); el = time.monotonic() - t0
        open(os.path.join(out_dir, f"{kind}-{mode}.out"), "wb").write(data)
        res[mode] = (hashlib.sha256(data).hexdigest(), rc, len(data), data.count(b"=== "))
        print(f"{kind} {mode}: rc={rc} bytes={len(data)} renders={res[mode][3]} sha256={res[mode][0][:16]} {el:.1f}s", flush=True)
    same = res["frozen"][:2] == res["live"][:2]
    ok &= same and res["live"][1] == 0
    print(f"{kind}: {'IDENTICAL' if same else 'DIFFERENT'}", flush=True)
sys.exit(0 if ok else 1)
