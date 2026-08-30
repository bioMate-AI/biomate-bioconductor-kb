# Diagrams

Two formats:
- **Inline Mermaid** below — renders directly on GitHub / most Markdown viewers.
- **draw.io XML** in [`diagrams/`](diagrams/) — open any `*.drawio.xml` directly in [draw.io / diagrams.net](https://app.diagrams.net) (File → Open) or the VS Code Draw.io extension.

| draw.io file | Mermaid section |
|--------------|-----------------|
| `diagrams/01_overall_architecture.drawio.xml` | [1](#1-overall-system-architecture) |
| `diagrams/02_chat_to_workflow.drawio.xml` | [2](#2-chat--workflow-generation-sequence) |
| `diagrams/03_execution_runstate.drawio.xml` | [3](#3-run--execution--sse--finalize), [4](#4-run-state-persistence--orphan-completion) |
| `diagrams/04_data_stores.drawio.xml` | [7](#7-data-stores) |
| `diagrams/05_qc_autoloop.drawio.xml` | [5](#5-qc-gate--auto-loop) |

---

## 1. Overall system architecture

```mermaid
flowchart TB
  subgraph Client["Browser — React SPA (frontend/client)"]
    UI["Chat + right-panel viewer\n(v1 components/ = default)"]
    UIV2["v2/ ResearchApp\n(opt-in: ?ui=v2)"]
    UI -. "useUiFlavor flag\n(mutually exclusive)" .- UIV2
  end
  subgraph Node["Node/Express (frontend/server) — host :5000 / container :3000"]
    RT["routes.ts (308 handlers)"]
    GA["galaxy-assistant.ts\n(LLM chat + gen)"]
    SSE["workflow-sse.ts +\ngalaxy-state-poller.ts"]
    AUTH["auth-service / oauth / mfa"]
  end
  subgraph Galaxy["Galaxy backend — Python/gunicorn (4 workers) — host :8081 / container :8080"]
    AI["ai_assistant.py\n(orchestrator)"]
    SEARCH["unified_workflow_search\n(FTS5 + BGE vec)"]
    NEX["nextflow_executor.py\n(launch/track/finalize)"]
    RUNS["ai/runs/ (run-state, poller)"]
    BILL["ai/billing/ (router, quota)"]
    QC["QC gates + autoloop"]
  end
  subgraph Cloud["Cloud / managed"]
    BATCH["AWS Batch\nCPU + GPU queues"]
    EC2["EC2 + CryoSPARC API"]
    S3[("S3\nbiomate-nextflow-work")]
    REDIS[("Redis / ElastiCache\nrun-state + billing ledger")]
    PG[("PostgreSQL\napp + LTM")]
    LLM["LLM providers\nAnthropic/Google/OpenAI/…"]
    STRIPE["Stripe"]
  end

  UI -->|"HTTPS + SSE"| RT
  RT --> GA --> LLM
  RT -->|"proxy /api/*"| AI
  AI --> SEARCH
  AI --> NEX
  NEX -->|"tasks"| BATCH --> S3
  NEX -.->|"head = local subprocess"| NEX
  AI -.-> EC2
  NEX <--> RUNS
  RUNS <--> REDIS
  BILL <--> REDIS
  QC --> NEX
  Node --> PG
  Galaxy --> PG
  RT --> STRIPE
  NEX -->|"/internal/sse-inject"| SSE --> UI
```

## 2. Chat → workflow generation (sequence)

```mermaid
sequenceDiagram
  participant U as Browser
  participant N as Node (galaxy-assistant.ts)
  participant B as Backend (ai_assistant.py)
  participant S as Search (FTS5+BGE)
  participant L as LLM
  U->>N: POST /api/chat/stream
  N->>L: classify intent + stream tokens
  N->>B: POST /api/ai_assistant/generate_workflow
  B->>B: LTM correction inject → fast-path shortcuts
  B->>S: iterative search trials (limit=5)
  S-->>B: ranked candidates (additive score + RRF)
  alt medium conf / close top-2
    B->>L: _llm_verify_routing (temp 0)
  end
  B->>B: disambiguation gate?
  B->>B: confidence tier → reuse / adapt / NextflowComposer
  B->>L: (compose only) emit DSL2 .nf
  B->>B: rule + LLM param prefill + schema guardrail
  B-->>N: workflow_ga (name, domain, params, nextflow_path)
  N-->>U: AI text + workflow card
  U->>N: open card → GET /api/nextflow/steps (lazy)
```

## 3. Run → execution → SSE → finalize

```mermaid
sequenceDiagram
  participant U as Browser
  participant NX as nextflow_executor.py
  participant ST as run-state store (Redis)
  participant BA as AWS Batch
  participant FE as Node SSE (/internal/sse-inject)
  U->>NX: POST /api/nextflow/execute
  NX->>ST: write "configuring" (+ _runs[])
  NX-->>U: run_id (returns immediately)
  NX->>NX: _launch_nextflow_head (semaphore, FD-decoupled Popen)
  NX->>ST: set_pid
  NX->>BA: submit tasks (CPU/GPU queue)
  BA->>S3: publish outputs
  loop while running
    NX->>FE: POST progress (tail workflow-trace.txt)
    FE-->>U: SSE workflow.phase_*, qc_gate, autoloop
  end
  NX->>NX: _stream_logs → false-success/failure salvage
  NX->>ST: terminal state
  NX->>NX: _evaluate_qc_from_s3 + autoloop (advisory)
  NX-->>U: SSE terminal + chat narration
```

## 4. Run-state persistence & orphan completion

```mermaid
flowchart LR
  subgraph W1["gunicorn worker 1"]
    P1["CompletionPoller\n(every 5s)"]
  end
  subgraph W2["gunicorn worker 2 (recycled mid-run)"]
    H["orphaned Nextflow head\n(detached, start_new_session)"]
  end
  ST[("Redis run-state\nnextflow:run:* + :pid + :completing")]
  PG[("Postgres execution_runs")]
  P1 -->|"list_active_runs"| ST
  P1 -->|"pid gone? acquire lock"| ST
  P1 -->|"finalize_orphaned_run"| FIN["infer RC from disk/S3"]
  FIN -->|"update terminal"| ST
  FIN -->|"POST /internal/runs/by-invocation/:id/status"| PG
  H -.->|"survives worker death"| H
  note1["RUN_STATE_STORE=redis REQUIRED\nelse InMemory → fix silently inactive"]
```

## 5. QC gate / auto-loop

```mermaid
flowchart TB
  OUT["Run outputs on S3\n(toxicity_report.json / qc_report.json / …)"]
  EV["_evaluate_qc_from_s3\n(nextflow_executor.py:3179)"]
  TH["qc_thresholds.json\nRED_LINE/GOLD/SILVER/BRONZE"]
  OUT --> EV
  TH --> EV
  EV -->|"metric vs threshold"| DEC{action?}
  DEC -->|"pass"| DONE["advance / complete"]
  DEC -->|"advisory (≤1.3× / 1.15×)"| ADV["SSE autoloop_gate_results\n(warn, continue)"]
  DEC -->|"halt (hERG IC50<10µM,\nbiology-erasure)"| REM["param_tuner:\nwas→now remediation\nlogp_max 5.0→4.71"]
  REM -->|"SSE autoloop_update\n{remediations, suggested_params}"| UI["suggestions persisted\nby invocation_id"]
  note["ADMET auto-loop is ADVISORY —\nsuggests, does not auto-restart"]
```

## 6. Search & routing scoring

```mermaid
flowchart TB
  Q["user intent"] --> T["_build_intent_trials\n(query rewrites)"]
  T --> P0["Pass-0: fast-LLM catalog browse\n(+3.0 … +0.3)"]
  T --> P2["Pass-2: FTS5 / BM25\n(name×1.5, keywords, phrase,\nSOURCE_PRIORITY/15, domain±4,\ninput-type±4, tag±6, exec±2)"]
  T --> P1["Pass-1: BGE dense cosine\n(sim×0.5, cap 0.5, thr 0.55)"]
  P0 --> SUM["additive score"]
  P1 --> SUM
  P2 --> SUM
  SUM --> CLS{"_classify_match"}
  CLS -->|"≥12"| HI["high → template_reuse"]
  CLS -->|"≥6"| MED["medium → template_adapt"]
  CLS -->|"<6"| LOW["low → NextflowComposer"]
  RC["reclassify guardrail (PR#188):\ndomain subworkflows NOT −8"] -.-> SUM
```

## 7. Data stores

```mermaid
flowchart TB
  subgraph SQLite["SQLite (backend/database)"]
    AIDB[("galaxy_ai_tools.db 315MB\n4057 wf / 12301 tools\nFTS5 + vec0(384)")]
    UNI[("universe.sqlite\nGalaxy ORM (187 tbl)")]
    BENCH[("benchmark_knowledge.db")]
    REG[("regulatory_skills.db")]
  end
  subgraph PGc["PostgreSQL (Drizzle)"]
    APP[("app: users, workflow_executions,\nexecution_runs, instruments, billing")]
    LTM[("LTM: episodes, procedures,\npreferences, correction_log")]
  end
  subgraph RD["Redis (ElastiCache, shared)"]
    RS["run-state hashes"]
    LED["billing cost:{uid}:month:*"]
    WS["wfsess:*"]
  end
  subgraph S3g["S3"]
    WORK[("biomate-nextflow-work")]
    CRYO[("biomate-cryo-data")]
    BK[("db-backups/")]
  end
```

## 8. Auth & Galaxy provisioning

```mermaid
sequenceDiagram
  participant U as Browser
  participant AS as auth-service.ts
  participant PR as billing_router /internal/users/provision
  participant GX as Galaxy SQLite (galaxy_user)
  U->>AS: POST /api/auth/register (email, pw)
  AS->>AS: bcrypt(12) → insert users row
  AS->>PR: provisionGalaxyUser(id, email)
  PR->>GX: write galaxy_user (PBKDF2), mint api_key token_hex(16)
  PR-->>AS: {galaxy_user_id, api_key, username}
  AS->>AS: encrypt (AES-256-GCM) → users
  AS-->>U: set httpOnly cookie biomate_token (JWT HS256)
  note over AS: login stale-key detection re-provisions
```

## 9. Deploy / sync (sync_to_dev.sh)

```mermaid
flowchart TB
  DEV["dev machine\n(main repo /Users/kky/biomate)"]
  DEV -->|"pre-sync gate:\ntsc + vitest + py3.9 import"| GATE{pass?}
  GATE -->|"no"| STOP["STOP, fix locally"]
  GATE -->|"yes"| SNAP["docker commit …:rollback\n(no mounts → capture state)"]
  SNAP --> SYNC["SSM sync 4 layers:\nfrontend img, backend cp,\nGalaxy DBs, .nf"]
  SYNC --> HEALTH{"health gate:\n/api/version + /api/health +\ngenerate_workflow + DB query"}
  HEALTH -->|"pass"| OK["SYNC_RESULT=healthy → SNS"]
  HEALTH -->|"fail"| RB["rollback_sync → recreate\nfrom :rollback → recheck → SNS"]
```

## 10. Memory hierarchy (design vs code)

```mermaid
flowchart LR
  L1["L1 Volatile\n(design-only)"]:::ghost
  L2["L2 Redis session\n(not a memory store)"]:::ghost
  L3["L3 Postgres LTM\nFULLY IMPLEMENTED"]:::real
  L4["L4 SQLite FTS5 + vec\n= workflow/tool search"]:::partial
  EPI["project_episodes"] --> CONS["consolidateEpisodes\n(≥3 detected)"]
  CONS -.->|"STUB: never writes"| PROC["project_procedures"]
  PREF["user_preferences\nconfidence += 0.1 (cap 1.0)"] --> L3
  CORR["correction_log"] --> L3
  L3 --- EPI
  classDef real fill:#d5e8d4,stroke:#82b366;
  classDef partial fill:#fff2cc,stroke:#d6b656;
  classDef ghost fill:#f5f5f5,stroke:#999,stroke-dasharray:4;
```
