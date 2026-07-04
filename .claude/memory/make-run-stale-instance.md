---
name: make-run-stale-instance
description: "speak is a menubar app — `open` won't relaunch it; use make run/doctor or you test stale code"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a28bf5c6-f1d6-4f58-8e0b-d6b2ae499dce
---

`speak` is a menubar **LSUIElement** app. `open Speak.app` does NOT relaunch it if an
instance is already running — it just activates the existing process, which keeps the
**stale in-memory binary** even after a fresh rebuild. This silently masked a completed,
built-and-tested feature (PE-3 chips) and cost a multi-hour detour: the binary file was
new but the running PID predated the build.

**Why:** verifying a live change against a process that started before the build proves
nothing; the symptom is "my code built + tests pass but the app looks unchanged."

**How to apply:** use the dev-loop targets (now in the Makefile, commit a0a1011):
- `make run` — rebuilds, **kills the running instance**, then launches fresh. Always.
- `make doctor` — flags when the running PID's start time predates the binary mtime
  (the staleness tell), plus signing identity + perms hint. Run it FIRST when a rebuild
  seems ignored.
- `make logs` — live `log stream`; speak's `.info` os.Logger lines are NOT persisted to
  `log show`, so live streaming is the only way to watch a dictation.
- `make history` — dump recent dictations (raw vs cleaned) from the SQLite store; fastest
  proof that cleanup ran / a profile reshaped output.

Related: [[dev-codesigning-for-tcc]] (the other rebuild trap — TCC grants needing the
stable `make dev-cert` identity).
