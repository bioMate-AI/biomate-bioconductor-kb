# 2026-11-13 — Findings/summary/report class continue (matrix)

Live tip at start of continue: `ecf9fedc` (`build-info.json`). Worktree branch: `sync/pr398-onto-dev`.

## Case matrix

| Domain | Issue | Fix | Test | Verified |
|--------|-------|-----|------|----------|
| **ml_training** | Findings ignored `metrics.json` → Ludwig fluff | `parseMlTrainingFindings` + class hollow refuse (shipped `19914c14` / docs) | `ml-training-findings.test.ts` | S3 sidecar healed; live tip must include fix ancestry |
| **ADMET** | Dual path OK; report/Findings aligned | Existing `_parseAdmetOutput` + `admet_report` descriptor | `findings-extract.test.ts` | Unit |
| **DESeq2 / RNA-seq DE** | Generic “Assessment completed…”; LLM when descriptor miss | Descriptor → `documentToLegacy` + `parseDeseq2Findings` flat belt | `findings-extract` + `genomics-flat-findings.test.ts` | Unit |
| **enrichGO** | TSV parsed as CSV → null → LLM fluff | Autodelim + `parseEnrichGoFindings` flat belt | `genomics-flat-findings.test.ts` | Unit |
| **WGS / variant / raredisease** | Context-only → LLM; HIGH buried | Descriptor → flat + `parseRarediseaseFindings` flat belt | findings-extract + genomics-flat | Unit |
| **Docking / Vina** | No deterministic affinity parser | `vina_docking` descriptor + hollow refuse for “no affinities” | `findings-extract.test.ts` Vina block | Unit |
| **Boltz / structure** | No pLDDT Key Results | `boltz_qc` / `boltz_summary` batch descriptors | `findings-extract.test.ts` Boltz block | Unit |
| **CryoEM / CryoSPARC** | Findings LLM-only while report had extracted metrics | `parseCryoEmFindings` (FSC, particles, acquisition) in `preProcessForFindings` | `cryo-em-findings.test.ts` | Unit |
| **RNA-seq / WGS QC (no DE)** | MultiQC HTML narrated; scores missed | `parseMultiqcFindings` (never outranks DE/enrich tables) | `multiqc-findings.test.ts` | Unit |
| **Sampling rank** | Bookkeeping crowded score files | `scoreFindingsSampleName` +8 for vina/boltz/cryo/FSC | `findings-quality.test.ts` | Unit |
| **Hollow sidecars** | Poison re-served forever | Class-wide `looksLikeHollowFindings` (docking/cryo/MultiQC admits) | `findings-quality.test.ts` | Unit |
| **UX chips** | Gate / fluff before scores | Headline rank prefers MAE/affinity/pLDDT/FSC/aligned | `findings-card.tsx` | Unit (existing card tests) |
| **download_all_zip** | “No outputs found” while Outputs tab full (`727de1b4`) | Canonical `runsOutputsService.list` **first**; empty Galaxy fallback to S3 | `download-all-handler.test.ts` (3) | Unit; suite `{ timeout: 45_000 }` + module S3 mock baked in |

## Pipeline (unchanged shape)

```
samples → scoreFindingsSampleName
       → preProcessForFindings (ADMET / DE / enrich / rare / ML / cryo / MultiQC)
       → matchDescriptor → documentToLegacy (skip LLM when records)
       → else LLM
       → refuse hollow on disk/S3/cache/report
```

## Tests run (this continue)

```bash
cd frontend && npx vitest run \
  server/cryo-em-findings.test.ts \
  server/multiqc-findings.test.ts \
  server/findings-quality.test.ts \
  shared/findings-extract.test.ts \
  server/ml-training-findings.test.ts \
  server/jobs/__tests__/download-all-handler.test.ts \
  client/src/components/findings-card.test.tsx \
  server/genomics-flat-findings.test.ts
# 67 + 4 genomics = green; download_all alone ~10s with baked suite timeout
# + npx tsc --noEmit -p .
```

## Still open (honest / intentional)

1. **Authenticated UI autopsy** for potency session still needs `drugtest@biomate.dev` (fixture gets 403).
2. **Chat stream prose** from original turns is not rewritten — After-run Findings/report only.
3. **Cryo FSC** often empty in older SPA reports (`fsc_curve: []`) — parser still surfaces particle/acquisition scores; resolution appears when `fsc_0143_resolution` is present.
4. **QC auto-loop** gate cards are separate from Findings; no change this round beyond chip ranking.
5. **Live sync blocked in this agent env** — branch pushed at `3245597fe2` (contains `67cb30ede2` + genomics belt + live tip merge `1001dec42f`). `scripts/sync_to_dev.sh` cannot reach `ssm.us-west-2.amazonaws.com` / STS from Cursor (proxy CONNECT 403 or DNS fail when proxy cleared). Operator: from a host with AWS creds + working SSM:
   `BIOMATE_SYNC_DB=0 bash scripts/sync_to_dev.sh` on worktree `/Users/kky/biomate-nextphase-ci-fix` @ `3245597fe2`.
