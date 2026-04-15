# BioMate Independent Evaluation Harness

Self-contained evaluation suite for benchmarking BioMate against published competitor benchmarks and BioMate-specific benchmark datasets.

## Directory layout

```
evaluation/
├── core/                     # Shared infrastructure
│   ├── biomate_client.py     # HTTP client for BioMate API
│   ├── llm_judge.py          # LLM-as-judge for open-answer scoring
│   ├── base_adapter.py       # Abstract base class for all benchmark adapters
│   └── results_store.py      # SQLite-backed results persistence
│
├── adapters/                 # One file per external benchmark
│   ├── biomni_eval1_adapter.py
│   ├── sgi_bench_runner.py
│   ├── bixbench_adapter.py
│   ├── routing_adapter.py
│   ├── prereq_recovery_adapter.py
│   ├── license_gating_adapter.py
│   ├── bioagentbench_adapter.py
│   ├── sciagentbench_adapter.py
│   └── pharmabench_adapter.py
│
├── datasets/                 # BioMate-unique benchmark datasets (our own)
│   ├── cross_domain_routing/ # 150 annotated routing queries (14 domains)
│   ├── prereq_recovery/      # 40 multi-turn recovery trajectories
│   ├── license_gating/       # 30 credential-scenario test cases
│   ├── qc_governance/        # Controlled-defect QC benchmark
│   ├── protocol_thresholds/  # Protocol-aware QC threshold benchmark
│   ├── drug_discovery_e2e/   # 15 PDBbind systems for drug pipeline eval
│   └── audit_trail_fair/     # FAIR reproducibility benchmark
│
├── runners/                  # Executable scripts
│   ├── run_all.py            # Master runner (--suite flag)
│   ├── run_biomni_eval1.py
│   ├── run_sgi_bench.py
│   ├── run_bixbench.py
│   ├── run_routing.py
│   ├── run_prereq_recovery.py
│   ├── run_license_gating.py
│   └── generate_report.py   # Competitive markdown report
│
├── scripts/                  # Setup and dataset construction utilities
│   ├── setup_eval_user.py    # Create BioMate eval account, verify endpoints
│   ├── download_benchmarks.sh # Clone external repos, cache HF datasets
│   └── inject_qc_defects.py  # QC governance: download, inject, run QC, label
│
├── results/                  # Output directory (gitignored except .gitkeep)
├── config.yaml               # Endpoint, model, and path configuration
└── requirements.txt
```

## Quick start

```bash
cd /home/yzhang/biomate/evaluation

# 1. Install dependencies
pip install -r requirements.txt

# 2. Download external benchmark repos + datasets
bash scripts/download_benchmarks.sh

# 3. Start BioMate backend (if not already running)
cd /home/yzhang/biomate/backend && bash start_backend.sh &
cd /home/yzhang/biomate/evaluation

# 4. Create eval user and verify endpoints
python scripts/setup_eval_user.py

# 5. Smoke test (5 tasks, ~5 min)
python runners/run_all.py --suite p0 --max-tasks 5 --output results/smoke/

# 6. Full P0 benchmarks (~4h, ~$15 API cost)
python runners/run_all.py --suite p0 --output results/

# 7. Generate competitive report
python runners/generate_report.py --results-dir results/ --output results/report.md
```

## Suites

| Suite | Benchmarks | Est. time | Est. cost |
|---|---|---|---|
| `p0` | BiomniEval1 + SGI-Bench + routing | ~4h | ~$15 |
| `p1` | p0 + BixBench + BioAgentBench + prereq_recovery | ~8h | ~$40 |
| `p2` | p1 + SciAgentBench + PharmaBench + license_gating | ~12h | ~$60 |
| `all` | Everything | ~20h | ~$100 |
| `datasets_only` | Only BioMate-unique datasets (no external) | ~2h | ~$5 |

## Benchmark status

| Benchmark | Type | Status | Notes |
|---|---|---|---|
| BiomniEval1 | External | Ready | Loader already in repo |
| SGI-Bench | External | Ready | 503 samples on disk, adapter exists |
| Cross-domain routing | BioMate-unique | Dataset ready | 150 queries in datasets/ |
| Prereq recovery | BioMate-unique | Dataset ready | 40 trajectories in datasets/ |
| License gating | BioMate-unique | Dataset ready | 30 cases in datasets/ |
| BixBench | External | Adapter stub | Needs BixBench repo clone |
| BioAgentBench | External | Adapter stub | Needs dataset download |
| ScienceAgentBench | External | Adapter stub | Needs repo clone |
| PharmaBench | External | Adapter stub | Needs repo clone |
| QC Governance | BioMate-unique | Dataset spec | Needs defect injection + labeling |
| Protocol Thresholds | BioMate-unique | Dataset spec | Needs 20 datasets + labeling |
| Drug Discovery E2E | BioMate-unique | Dataset spec | Needs PDBbind access |
| Audit Trail FAIR | BioMate-unique | Dataset spec | Needs 3 independent reviewers |

## Competitor reference scores

See `../docs/papers/20260401_COMPETITOR_BENCHMARK_LANDSCAPE.md` for all published scores with citations.

## Adding a new benchmark

1. Create `adapters/my_benchmark_adapter.py` subclassing `core.base_adapter.BenchmarkAdapter`
2. Implement `load_tasks()` → `List[BenchmarkTask]` and `score(task, response)` → `float`
3. Add a runner in `runners/run_my_benchmark.py`
4. Register in `runners/run_all.py` under the appropriate suite
