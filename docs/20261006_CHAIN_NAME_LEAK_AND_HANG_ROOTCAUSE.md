# Chain name-leak + hang + status-404 — root cause & fixes (2026-10-06)

## Observed (real dev run, from the ADMET real-use-case E2E)
A user ADMET request routed correctly (`predict_admet_properties`, `workflow_ready`) and the **hERG QC gate
fired live** (2 failures on terfenadine — correct). But:
1. the run record was **mislabeled** `name="Bulk RNA-seq DE -> Pathway Enrichment (airway/GSE52778 validation)"`
   on an ADMET execution (invId `chain_1791260333_5f39f9`);
2. it polled `running` for ~30 min with **no terminal state**;
3. afterwards `GET /api/nextflow/status/{run_id}` returned **404 for both** the chain id and the exec id.

Three parallel code investigations established the root causes (file:line below).

## Root causes
### A. Name leak — a stale `chain_hint` trusted verbatim, never bound to the steps
- The chain is freshly minted (`chain_{int(time.time())}_{3 bytes}`, `workflow_chain.py:1035`) — **not** a key
  collision. Its display `name` is stamped straight from `request.chain_name` (`workflow_chain.py:1057`, resume
  `:1028-1029`) and **never derived/validated from the resolved steps**.
- Upstream source: the intent classifier is always fed the last 3 user turns with "no programmatic gate"
  (`frontend/server/galaxy-assistant.ts:7013-7022`); the "ADMET must NOT set chain_hint" rule lives only in the
  prompt (`:6465-6470`), not in code. So the ADMET turn inherited the prior RNA-seq turn's `chain_hint`
  (`bulk_rnaseq_consensus_de_bioc`, whose display name is the airway/GSE52778 string — the cold-start txn seed,
  `cold-start-dashboard.tsx:102`). That curated display name flowed artifact → submit → immutable run label
  (`galaxy-assistant.ts:5229,5233` → `chain-execution.ts:206-209` → `workflow_chain.py:1057`). ADMET still ran
  (hence the live PREDICT_ADMET_PROPERTIES gate); the record just wore the RNA-seq name.
- Ruled out: fallback-to-example-name, chain_meta sidecar collision, module-global stale read.

### B. Hang + double-404 — chains have no poller/rehydration and status has no chain-awareness
- A chain runs in a **per-worker daemon thread** (`workflow_chain.py:_run_chain`, launched `:1103`) polling each
  phase to terminal. There is **no chain-level completion handler, no rehydration, and no orphan/poller coverage**
  (`CompletionPoller`/`orphan_finalizer` only finalize per-phase *exec* ids). A gunicorn worker recycle mid-phase
  kills the thread → the chain's on-disk JSON freezes at `status:"running"` forever.
- `/api/nextflow/status/{run_id}` had **no chain-awareness** — chain ids live in `BIOMATE_CHAINS_DIR`, served by a
  *different* router (`/api/workflows/chain/{id}`) — so a chain id 404'd deterministically; the exec id 404'd under
  the per-worker InMemory store after recycle.
- The QC HALT is **advisory only** (`autoloop_bridge.py:9-14`, return ignored at `nextflow_executor.py:3536`) — it
  does not stop/terminal the chain. So the gate firing is correct behaviour, not the hang.

## Fixes applied in this PR (backend, low-risk, verified)
1. **Bind chain name to what runs** (`workflow_chain.py`, new-chain path): for a **single-step** chain, drop any
   multi-phase/mismatched `request.chain_name` and name it after its one workflow; for multi-step, derive a name
   from the steps only when none was given (legit curated multi-phase names are preserved). Logic unit-checked
   standalone — fixes the exact ADMET case, keeps legit chains intact. This is the authoritative backstop: the
   run's label can no longer diverge from what it executes, regardless of any stale upstream hint.
2. **Chain-aware status** (`nextflow_executor.py`, `_get_nextflow_status_impl`): a `chain_...` id now resolves
   from the chain store (lazy import, avoids the circular dep) and returns a status-shaped payload instead of
   404. Non-chain ids fall through unchanged.

Both `py_compile` clean (py3.9). The name-binding rule verified against the bug case + 4 legit cases.

## Deferred follow-ups (prioritized — NOT in this PR)
1. **Frontend `chain_hint` guard (the upstream source):** enforce in code that a single-analysis request (ADMET
   etc.) drops a `chain_hint` inherited purely from prior turns (`galaxy-assistant.ts:7013-7022`; reconcile
   artifact name/steps at `:5229,5233`; stop deriving the submitted name independent of steps at
   `chain-execution.ts:206-209`). The backend fix already neutralizes the *label*; this stops a single analysis
   being mis-*chained* at all.
2. **Chain poller / rehydration (the hang):** register active chains durably and add a chain reconciler (the chain
   analogue of `CompletionPoller`/`orphan_finalizer`) that re-drives `_run_chain(chain_id, start_from=<current>)`
   when its thread is gone but the current phase's exec id is terminal.
3. **HALT → terminal policy:** decide whether a QC HALT should halt the chain (it already has an
   `awaiting_approval` state, `workflow_chain.py:648`) rather than advance/hang.
4. **Durability:** confirm `RUN_STATE_STORE=redis` + non-ephemeral `NEXTFLOW_WORK_DIR` on dev; make the
   Redis-unreachable fallback fail loud instead of silently degrading to per-worker InMemory.

## Do NOT re-run the chain until at least #2 lands
The backend fixes stop the mislabel and the status-404, but a chain can still **hang** on a worker recycle until
the poller/rehydration (#2) exists. A re-run now could still get stuck. Land #2 (and ideally #1) before the
next real chain execution.

---

## UPDATE 2026-10-06 — deferred #2 (chain poller/rehydration) now IMPLEMENTED
The hang fix is in (commit on `fix/chain-name-leak-and-status-20261006`): a per-worker
**chain reconciler** in `workflow_chain.py` — the chain analogue of CompletionPoller/orphan_finalizer.
- **Heartbeat** on each phase start + every 5s poll (`last_heartbeat`).
- **Sweep** every 60s: a chain is orphaned iff `status=running` AND no live local chain-thread AND
  heartbeat stale > 150s.
- **Cross-worker claim** via the existing SETNX lock (`acquire_completion_lock("chainrehydrate:<id>")`);
  fail-safe (no lock → no drive). Requires `RUN_STATE_STORE=redis` for cross-worker safety.
- **Reattach-not-relaunch:** re-drives by polling the current phase's existing run_id to terminal, then
  continues to later phases — never relaunches a running Batch job.
- Started per worker on first chain submit; tunables `BIOMATE_CHAIN_RECONCILE_STALE_S` / `_INTERVAL_S`.

Still deferred: the frontend `chain_hint` guard (#1), HALT→terminal policy (#3), and confirming
`RUN_STATE_STORE=redis` on dev (#4). With the reconciler in, a worker recycle no longer strands a chain,
so a controlled re-run is now reasonable **once this branch is deployed and `RUN_STATE_STORE=redis` is
confirmed on dev**.
