# Batch C — BLOCKED_REQUIRED coldstart seeds (2026-11-14)

Addresses inventory §2 (`docs/20261114_COLDSTART_FAILED_WORKFLOWS_INVENTORY.md`): seed
required params where legitimate sample/e2e inputs exist; leave Cryo map-postprocess
honestly blocked (no fake movies / force-Confirm).

## Per-case outcome

| Case | Workflow | Missing param(s) | Decision |
|------|----------|------------------|----------|
| `analysis-domain-str-0` | CryoSPARC SPA | `movies_path` | **Seeded** — `s3://biomate-cryo-data/empiar-10028/Micrographs/` from cryo catalog + `cryo_inputs.json` (staged EMPIAR-10028 subset). Deterministic Prepared-input KV → param strip. |
| `analysis-domain-str-2` | CryoSPARC SPA (wrong tool for intent) | `movies_path` | **Intentionally blocked** — postprocess example only has EMD-5995 map URL; SPA needs movies. Context now forbids inventing `movies_path`. Panel shows Fix now + honest blocked hint. |
| `analysis-domain-fgen-0` | nf-core/crisprseq | `analysis` | **Seeded** — `analysis=screening` in crisprHits prepared context; KV seed fills enum so Confirm enables. Count TSV already attached. |
| `analysis-try-sample-data-11` | Chemoproteomics Pulldown | `input_file` (+ pulldown/control) | **Seeded** — attach LFQ-Analyst `proteinGroups.txt` + design; `input_file=proteinGroups.txt`, `pulldown_sample=H1`, `control_sample=L1`. |
| `design-predict-filter-sm-3` | openfe_rbfe | `ligand_a` (SDF) | **Seeded** — demo `imatinib.sdf` / `dasatinib.sdf` (RDKit from public actives SMILES) + `receptor=1IEP.pdb` in docking/RBFE context. |

## Product changes (not harness)

1. `frontend/shared/prepared-inputs-params.ts` — parse `param=value` from `[Prepared inputs]` / message; apply onto `workflow_ga`.
2. `galaxy-assistant.ts` — seed before attachment bind; withdraw clarifications for filled KV / backend / attachment params.
3. Cold-start catalog + examples — context KV + chemoproteomics files + openfe SDFs.
4. Panel footer — `panel-blocked-required-hint` + Fix now when clinic-hard / file inputs unbound.

## Verify

```bash
cd frontend && npx vitest run \
  shared/prepared-inputs-params.test.ts \
  client/src/components/cold-start-demo-catalog.test.ts \
  client/src/components/cold-start-examples.test.ts

# Optional deep re-run (dev, exclusive lock):
BIOMATE_DEEP_FILTER='^(analysis-domain-str-0|analysis-domain-str-2|analysis-domain-fgen-0|analysis-try-sample-data-11|design-predict-filter-sm-3)$' \
  ./e2e/run_coldstart_deep.sh
```

Expect: str-0 / fgen-0 / try-11 / sm-3 leave `BLOCKED_REQUIRED` (Confirm enabled or launch path); str-2 stays `BLOCKED_REQUIRED` with Fix now visible and no invented movies.
