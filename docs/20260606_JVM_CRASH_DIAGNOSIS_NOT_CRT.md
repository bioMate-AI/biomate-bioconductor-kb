# JVM startup SIGSEGV is NOT the AWS CRT bug

**Date:** 2026-06-06
**Status:** Diagnosis only — no fix attempted

## TL;DR

The 26-second `exit_code -6` crash observed on dev (run
`d6a5071a-7fd9-481d-aff8-5e02a4996af3`, HTS plate QC) is **not** the
nf-amazon AWS CRT crash that `327e75345` / `8ce82af6b` (nf-amazon@3.3.0
pin) and the bookworm+JDK17 swap (`cbe554675`) targeted.

It is the same `ld-linux+0x224ba` dlopen SIGSEGV, but fires on
`System.loadLibrary("management")` during Nextflow's startup
`CmdInfo.status()` call — well before any plugin or CRT code runs.

## Evidence

`/tmp/nextflow_runs/d6a5071a-7fd9-481d-aff8-5e02a4996af3/work/hs_err_pid188170.log`:

```
SIGSEGV (0xb) at pc=0x...224ba
JRE version: OpenJDK 17.0.19+10 (Debian bookworm 12)
Problematic frame: C  [ld-linux-x86-64.so.2+0x224ba]
elapsed time: 24.654s

Java stack:
  jdk.internal.loader.NativeLibraries.load
  jdk.internal.loader.NativeLibraries$NativeLibraryImpl.open
  java.lang.System.loadLibrary
  java.lang.management.ManagementFactory.lambda$static$8
  → nextflow.cli.CmdInfo.getInfo(IZ)
  → nextflow.cli.CmdInfo.status(Z)
```

All current CRT mitigations were active in the command line and did not
prevent the crash:
- `-Daws.crt.disable.crt.in.client=true`
- `-Daws.crt.lib.dir=/tmp/.../d6a.../.aws-crt-cache`
- `-Xss2m`
- `LD_BIND_NOW=1` (env)
- nf-amazon@3.3.0 plugin pin

This makes sense: those mitigations target the CRT native lib loader
specifically. The JMX management lib (`libmanagement.so`) load path goes
through the same `ld-linux` dlopen routine but is reached via a
different Java call site (`ManagementFactory.<clinit>`).

## Why the prior fixes thought they had it

`cbe554675` ("honest correction") already retracted the bookworm+JDK17
claim. The nf-amazon@3.3.0 pin observably reduces *one* class of crash
(the plugin-resolution failure) but the underlying glibc/ld-linux
dlopen-lazy-resolve bug fires for *any* native library load, not just
CRT's `.so`. The HTS run happens to fail at JMX-init time before CRT
is even touched.

## Candidate next mitigations (untested — do not deploy without diagnosis)

1. **Disable Java perf-data + JMX entirely on the Nextflow head.** Add
   to `NXF_OPTS` in `nextflow_executor.py` ~line 3661:
   ```
   -XX:-UsePerfData -Dcom.sun.management.jmxremote=false
   ```
   Risk: `CmdInfo.status()` may still call `ManagementFactory`; need to
   verify whether `-XX:-UsePerfData` actually prevents the lazy-init
   `ManagementFactory` static block from running. If not, this won't
   help.

2. **Pre-load libmanagement.so before `LD_BIND_NOW` would matter.** Add
   to the launcher: `LD_PRELOAD=$JAVA_HOME/lib/libmanagement.so`. Forces
   the linker to resolve symbols eagerly outside the buggy lazy path.

3. **Different JDK build.** Try Temurin (Adoptium) JDK 17 or 21 instead
   of `openjdk-17-jre-headless` from Debian bookworm. The crash is in
   Debian's `ld-linux`, but the Java side may avoid the trigger if it
   links symbols differently.

4. **`-Dnextflow.disable.cmdinfo=true`** — does not exist as a real
   flag; would require an upstream NF feature. Not viable short-term.

None of these have been tested. The user's documented preference
(CLAUDE.md "Review Code Before Testing") rules out speculative deploys.

## What this blocks

- HTS plate QC + hit calling cannot complete on dev — the JVM dies
  before the workflow parses.
- Other parallel-fire workflow sweeps would observe the same crash for
  any workflow that fully loads Nextflow's `CmdInfo` at startup (all
  of them).
- The S3-fallback QC fix in `91fd19843` cannot be exercised
  end-to-end on dev until the JVM startup crash is resolved. Code is
  on dev (verified via `docker exec grep`); awaiting one real HTS
  completion to leave a `[QC-S3] Reading report …` INFO line in
  `gunicorn.log`.

## References

- Crash log: `/tmp/nextflow_runs/d6a5071a-7fd9-481d-aff8-5e02a4996af3/work/hs_err_pid188170.log`
  (dev container)
- Galaxy run row: `gunicorn.log` 2026-06-06 23:42:45–23:43:12
- `cbe554675` — prior honest correction that JDK17 swap alone is not
  the fix
- `327e75345` / `8ce82af6b` — nf-amazon@3.3.0 pin (necessary, not
  sufficient)
- `91fd19843` — S3-fallback fix queued behind this
