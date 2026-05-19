# Research-Agent v2 — Live-SSE audit (4 use cases)

Date: 2026-05-19
Scope: `frontend/research_agent_v2/` sandbox; live-mock SSE mode
(`?live=mock&scenario=…&speed=2`). **Not** integrated into production.

## Result — ALL PASS

| Scenario | JS errs | Plan items | Compare card | Findings card | Pass |
|----------|--------:|-----------:|:------------:|:-------------:|:----:|
| drugscreen | 0 | 5/5 | ✅ (expected)        | ✅ 47 BBB-penetrant     | ✅ |
| cryosparc  | 0 | 5/5 | — (none expected)    | ✅ 3.1 Å reconstruction | ✅ |
| rnaseq     | 0 | 5/5 | — (none expected)    | ✅ 1,847 DEGs · 23 pwy  | ✅ |
| variant    | 0 | 5/5 | — (none expected)    | ✅ 3.84M PASS · ts/tv 2.04 | ✅ |

Raw assertion JSON: `audit.json` next to this file.

## How to reproduce

```
cd frontend/research_agent_v2
python3 -m http.server 8765 &
node audit.cjs
```

The harness opens each scenario in `?live=mock` mode at speed=2, captures
four screenshots (early / mid / late / final-fullpage), records a WebM
video of the entire session, and asserts: 0 JS errors, plan reaches 5
items, comparison card matches expected-or-not, findings card matches a
scenario-specific regex.

## Visual audit notes per scenario

### Drug screen — `screenshots/drugscreen_4_final.png`
- Plan checklist all green-✓ (Ingest, ADMET, hERG, Ames, ranking).
- **Auto-loop diff card** renders with crossed-out old values and the
  promoted new values: `logp_max 5.5 → 4.5`, `mw_max_da 600 → 480`,
  both tagged `autoloop`.
- **Recommendation card** with confidence chip ("high") and statistical
  reasoning ("Fisher exact, hERG fail-rate, p 0.008") — the
  comparison surface.
- Action toast `Action: compare_use_b_auto` visible bottom-right
  (10-s auto-proceed countdown firing — expected per design).
- **Findings card**: "47 BBB-penetrant candidates · Workflow done in
  38m 12s · 10000 samples" with table rows (hERG pass 96%, Ames 97%,
  composite 0.82). Right-panel domain header reads
  "DRUG DISCOVERY · WORKFLOW".

### Cryo-EM SPA — `screenshots/cryosparc_4_final.png`
- Plan checklist all 5 phases (A–E) green-✓.
- Chat thread shows the per-phase progression with the QC-flag advisory
  during Phase A (Motion Correction & CTF) — the CTF gate trip surfaces
  as an advisory not a hard block, consistent with the existing
  pharmacology/cryo workflow phase taxonomy.
- **Findings card**: "3.1 Å reconstruction · publication-ready" with
  resolution, particle count, B-factor, symmetry, EMDB-ready flag.
- Right panel correctly identifies the workflow as `CryoSPARC SPA`
  with phases mapped to `_CRYOSPARC_STEP_PHASES`.

### Bulk RNA-seq — `screenshots/rnaseq_4_final.png`
- Plan 5/5 done.
- Chat thread compresses the bulk of phase updates into a single
  collapse marker ("WF — 12 earlier updates · click to show") which is
  the ChatStream's intentional behavior; the high-information events
  (start, completion, findings) remain visible.
- **Findings card**: "1,847 DEGs · 23 enriched pathways · 34m 18s · 12
  samples" with the per-row stats (982/865 up/down, top GO term, top
  KEGG, alignment rate). Right panel shows `nf-core · fastp QC`.

### Variant calling — `screenshots/variant_4_final.png`
- Plan 5/5 done.
- Chat thread shows the advisory `QC flagged metric` (mapping rate
  94.8% < 95% threshold) emitted mid-run; the workflow completes
  normally because the gate is advisory, not blocking.
- **Findings card**: "3.84M PASS variants · ts/tv 2.04" with raw
  count, PASS count, ts/tv ratio, coverage, the advisory mapping-rate
  note carried through as a row, and the VEP annotation flag. Right
  panel shows `WGS Germline — GATK4` (3 phases, 8 processes).

## Known cosmetic items (non-blocking)

1. **Generic chat fallback strings** ("Step step…", "QC flagged
   metric.") appear when the backend narrator templates aren't
   matched. These came from rnaseq/variant tape events that emit
   `workflow.phase_started` without all `technical` fields filled.
   Mock tapes are deliberately sparse so they exercise the renderer's
   default path; real backend events from
   `workflow_chat_narrator.py` include the structured fields.
2. **Comparison card class name** doesn't match a `[class*=comparison]`
   selector — the audit checks via body-text regex (`Run A.*Run B`)
   instead, which is what visually matters. Not a bug.

## Artifacts

```
docs/20260519_research_agent_v2_audit/
├── AUDIT.md              (this file)
├── audit.json            (raw assertions)
├── screenshots/
│   ├── drugscreen_{1_early,2_mid,3_late,4_final}.png
│   ├── cryosparc_{1_early,2_mid,3_late,4_final}.png
│   ├── rnaseq_{1_early,2_mid,3_late,4_final}.png
│   └── variant_{1_early,2_mid,3_late,4_final}.png
└── videos/
    ├── drugscreen.webm
    ├── cryosparc.webm
    ├── rnaseq.webm
    └── variant.webm
```

## Next step

Real-backend SSE smoke. With a small drug-screen invocation running on
dev EC2, open
`http://127.0.0.1:8765/index.html?live=real&inv=<invocation_id>` and
verify the same plan + chat + findings render against actual
`/api/workflows/{inv}/events` traffic. Any new event `kind`s
discovered there go either into the backend narrator templates
(`workflow_chat_narrator.py`) or the translator's default branch
(`translateBiomateEvent` in `ResearchApp.jsx`).
