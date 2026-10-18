"""Paired real-PTY Tab latency for npkg cached completion (plan 005 evidence)."""
import json, os, pty, resource, select, shutil, subprocess, sys, tarfile, time, statistics
ROOT = sys.argv[1]; WORK = sys.argv[2]; BASE_REF = sys.argv[3]; SAMPLES = int(sys.argv[4])
os.makedirs(WORK, exist_ok=True)
base = os.path.join(WORK, "baseline-tree")
if not os.path.isdir(base):
    os.makedirs(base)
    tar = os.path.join(WORK, "b.tar")
    with open(tar, "wb") as fh:
        subprocess.run(["git", "archive", "--format=tar", BASE_REF], cwd=ROOT, stdout=fh, check=True)
    with tarfile.open(tar) as t: t.extractall(base, filter="data")
    os.unlink(tar)
home = os.path.join(WORK, "home"); cache = os.path.join(WORK, "cache", "npkg"); fb = os.path.join(WORK, "bin")
for d in (home, cache, fb): os.makedirs(d, exist_ok=True)
with open(os.path.join(cache, "nixpkgs-attrs-x86_64-linux.txt"), "w") as fh:
    fh.write("".join(f"pkg{i:06}\n" for i in range(60000)) + "zzunique-attr\n")
nixlog = os.path.join(WORK, "nix-calls")
with open(os.path.join(fb, "nix"), "w") as fh: fh.write(f"#!/bin/sh\nprintf called >> '{nixlog}'\nexit 99\n")
os.chmod(os.path.join(fb, "nix"), 0o700)
def limit():
    resource.setrlimit(resource.RLIMIT_AS, (2 << 30, 2 << 30))
    if os.environ.get("PINCPU"): os.sched_setaffinity(0, {int(os.environ["PINCPU"])})
def read_until(fd, needle, count, deadline):
    buf = b""
    while buf.count(needle) < count:
        if time.monotonic() > deadline: raise TimeoutError(buf[-400:])
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try: buf += os.read(fd, 65536)
            except OSError: raise RuntimeError(b"pty closed: " + buf[-400:])
    return buf
def sample(tree):
    env = {"HOME": home, "ZDOTDIR": home, "XDG_CACHE_HOME": os.path.dirname(cache), "TERM": "xterm-256color",
           "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "PATH": fb + ":/usr/bin:/bin", "COLUMNS": "120", "LINES": "40"}
    pid, fd = pty.fork()
    if pid == 0:
        limit(); os.execve("/usr/bin/zsh", ["zsh", "-dfi"], env)
    try:
        dl = time.monotonic() + 60
        setup = (f"PS1='P> '; autoload -Uz compinit; compinit -D -i; r={tree}; source $r/25-theme.zsh; source $r/55-ui-helpers.zsh; "
                 f"source $r/60-functions.zsh; source $r/65-help.zsh; source $r/66-compdefs.zsh; {os.environ.get("TABPRE","")} print SETUP-''DONE\n")
        os.write(fd, setup.encode()); read_until(fd, b"SETUP-DONE", 1, dl)
        time.sleep(0.2); os.write(fd, b"npkg add zzuni"); read_until(fd, b"zzuni", 1, dl)
        t0 = time.monotonic(); os.write(fd, b"\t"); read_until(fd, b"que-attr", 1, dl); cold = (time.monotonic() - t0) * 1000
        seq = []
        for _ in range(int(os.environ.get("WARMN", "1"))):
            os.write(fd, b"\x15npkg add zzuni"); time.sleep(float(os.environ.get("WARMGAP", "0.2")))
            t0 = time.monotonic(); os.write(fd, b"\t"); read_until(fd, b"que-attr", 1, dl); seq.append((time.monotonic() - t0) * 1000)
        warm = seq
        os.write(fd, b"\x15exit\n")
    finally:
        try: os.killpg(pid, 9)
        except OSError: pass
        os.waitpid(pid, 0); os.close(fd)
    return cold, warm
res = {"baseline": {"cold": [], "warm": []}, "candidate": {"cold": [], "warm": []}}
for i in range(SAMPLES):
    order = [("baseline", base), ("candidate", ROOT)] if i % 2 == 0 else [("candidate", ROOT), ("baseline", base)]
    for name, tree in order:
        c, w = sample(tree); res[name]["cold"].append(c); res[name]["warm"].append(w)
        print(f"{i} {name} cold={c:.1f}ms warm={' '.join(f'{x:.1f}' for x in w)}", flush=True)
nat = os.path.exists(nixlog)
summary = {k: {"cold": statistics.median_low(v["cold"]),
               "warm_pooled": statistics.median_low([x for s in v["warm"] for x in s]),
               "warm_pooled_min": min(x for s in v["warm"] for x in s),
               "warm_sample_medians": statistics.median_low([statistics.median_low(s) for s in v["warm"]])} for k, v in res.items()}
print("medians_ms", json.dumps(summary), "native_nix_calls", int(nat))
json.dump({"workload": "real PTY Tab: npkg add zzuni<Tab> with 60001 cached names, zsh -dfi + compinit; one cold Tab then WARMN warm Tabs per fresh shell", "pinned_cpu": os.environ.get("PINCPU"), "warm_tabs": os.environ.get("WARMN"), "warm_gap_s": os.environ.get("WARMGAP"),
           "baseline_ref": BASE_REF, "samples_ms": res, "medians_ms_lower": summary, "native_nix_called": nat,
           "zsh": subprocess.run(["zsh", "--version"], capture_output=True, text=True).stdout.strip()},
          open(os.path.join(WORK, "result.json"), "w"), indent=1)
