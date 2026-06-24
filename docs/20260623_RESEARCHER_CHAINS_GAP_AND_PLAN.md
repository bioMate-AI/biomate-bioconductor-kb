# Researcher Chains — Gap Audit & Implementation Plan

**Date:** 2026-06-23  
**Source:** Code audit of actual `.nf` files + Dockerfile inspection + DB state  
**Prior docs:** `20260617_RESEARCHER_FIT_DEGUI_ZHI.md`, `20260617_RESEARCHER_FIT_ZHONGMING_ZHAO.md`, `20260619_THREE_FACULTIES_WORKFLOW_ROLLUP.md`

---

## Corrected status (what the code actually says, not the docs)

| Chain | DB state | `.nf` state | Container | ECR | Blocker |
|---|---|---|---|---|---|
| Z01 TorchGWAS | chain id=69, 4 rationale rows live | **Real** — Phase A/B/C call `torchgwas` CLI; Phase D parses results but **no GWAS Catalog query** | `biomate/torchgwas:v1` Dockerfile exists | ❌ not pushed | Phase D novelty count is not real |
| Z02 FDA | chain id=70 **DEPRECATED** | none | none | — | Upstream = paper-reproduction repo, no inference CLI |
| ZZ01 turep→Scupa→ImmuneApp | chain id=71, 9 rationale rows live | **Does not exist** — no `.nf` files for turep, scupa, or immuneapp anywhere in the repo | none | — | Scupa license (NOASSERTION) + no `.nf` written |
| ZZ02 scGWAS | chain id=72, 4 rationale rows live | **Real** — Phase A/B call `java -jar scGWAS_r1.jar`; Phase C calls R significance script; PathwayCommons12 **baked into container** at `/opt/scgwas/data/` | `biomate/scgwas:v1` built locally, smoke passes | ❌ not pushed | Just needs ECR push (~30 min) |

---

## Gap 1 — Z01 Phase D: no GWAS Catalog comparison

**What exists:** Phase D parses `results.tsv.gz` and counts hits where `pvalue ≤ 5e-8`. Reports `genome_wide_hits_5e8` as a plain integer.

**What's missing:** The demo says "18 novel vs GWAS Catalog" — but Phase D never calls the GWAS Catalog. It has no way to distinguish novel loci from known ones.

**Fix:** Add an EBI GWAS Catalog REST API call inside Phase D. For each GW-sig locus (up to 20 to avoid rate limiting), query `/singleNucleotidePolymorphisms/search/findByChromBpLocationRange?chrom={chr}&bpLocationMin={pos-500000}&bpLocationMax={pos+500000}`. Loci with zero catalog hits in the ±500 kb window are flagged novel.

**Effort:** ~1–2 hours. All standard library (urllib). Graceful fallback if network unavailable.

**Status:** Implementing in this session.

---

## Gap 2 — ZZ02 scGWAS: container not in ECR

**What exists:** Full real `.nf`, Dockerfile, PathwayCommons12 baked, smoke test passes locally (verified 2026-06-19).

**What's missing:** `docker push` to ECR. Without this, AWS Batch can't pull the image and the workflow fails at dispatch.

**Fix:**
```bash
docker tag biomate/scgwas:v1 \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scgwas:v1
aws ecr get-login-password --region us-west-2 \
  | docker login --username AWS \
    --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scgwas:v1
```

**Requires:** AWS ECR write credentials on the machine doing the push. ~30 min wall time.

**Status:** Blocked on AWS creds. Document for next session with EC2 access.

---

## Gap 3 — ZZ01 turep/Scupa/ImmuneApp: no .nf files exist

**What exists:** Chain row in DB, 9 rationale rows, design spec. Nothing else.

**What's missing:** Three `.nf` wrappers:
- `turep/main.nf` — Python API (`load_model() → predict_tr(h5ad)`); pretrained weights auto-download
- `scupa_polarization/main.nf` — BLOCKED on NOASSERTION license; do not wrap until license resolved
- `immuneapp_hla_screen/main.nf` — MIT license, separate repo; medium effort

**Fix (partial):** Write `turep/main.nf` and `immuneapp_hla_screen/main.nf` as real wrappers. Stub `scupa_polarization/main.nf` with a license-blocked error message that fails fast with an informative exit code.

**Test data for turep:** Sade-Feldman 2018 melanoma TILs, GEO GSE120575 (16k cells, public).

**Status:** Implementing turep + immuneapp stubs in this session; Scupa remains blocked.

---

## Gap 4 — Z01 TorchGWAS container not in ECR

Same as ZZ02 — Dockerfile exists at `torchgwas_udip_phenotype_scan/container/Dockerfile` but push not done.

**Fix:** Same `docker tag + docker push` pattern as scGWAS.

---

## Gap 5 — MAGMA, LDSC, METAL: not wrapped (shared gap, both labs)

Both Zhi (Nat Commun 2026 Methods) and Zhao (Genome Biology 2022 Methods) use MAGMA as the upstream gene-scoring step that feeds TorchGWAS and scGWAS respectively. Without MAGMA, neither demo is paper-faithful.

| Tool | Role | Priority | Status |
|---|---|---|---|
| **MAGMA v1.10** | Gene-based test from GWAS sumstats → `.genes.out` feed for scGWAS and TorchGWAS | P1 — shared gap | ✅ Implemented `magma_gene_analysis/main.nf` + `container/Dockerfile` |
| **LDSC** | SNP-heritability + cross-trait rg | P2 — Zhi paper | ✅ `ldsc_heritability/main.nf` + `container/Dockerfile` |
| **METAL** | Multi-cohort meta-analysis | P2 — Zhi paper | ✅ `metal_meta_analysis/main.nf` + `container/Dockerfile` |
| **FUMA** | Functional annotation (web API or local) | P3 | Not started |

**MAGMA wrap design:**
- 3-phase: `MAGMA_ANNOTATE` (SNP→gene, `--annotate`) → `MAGMA_GENE_ANALYSIS` (`--gene-analysis`) → `MAGMA_FORMAT` (box-cox transform)
- Output: `{outfile}.magma.txt` (raw, for FUMA) + `{outfile}.magma_boxcox.txt` (for scGWAS `--gwas_sumstats`)
- Smoke: `--use_baked_toy true` generates synthetic chr1 sumstats, runs with `--gene-model snp-wise` (no LD ref needed)
- Production: `--gene_model multi` uses baked g1000_eur LD reference
- Container bakes: MAGMA v1.10 static binary + g1000_eur (~300 MB) + NCBI37.3 + NCBI38 gene.loc files
- License note: MAGMA is freeware academic use only — binary downloaded from ctg.cncr.nl at build time; container not redistributable outside BioMate

**Chain integration:**
- ZZ02: `magma_gene_analysis → scgwas_immune_cell` (pass `magma_boxcox.txt` as `--gwas_sumstats`)
- Z01: `torchgwas_udip_phenotype_scan → magma_gene_analysis` (feed TorchGWAS results.tsv.gz SNP-level output into MAGMA for gene-based enrichment)

---

## Gap 6 — PathwayCommons for ZZ02

**Not a gap.** PathwayCommons12 is baked into `biomate/scgwas:v1` at `/opt/scgwas/data/PathwayCommons12.All.hgnc.exPCDHA.MHC.NCBI37.tsv` — confirmed by Dockerfile line 39. The previous docs incorrectly flagged this as missing.

---

## Implementation order (this session)

1. ✅ Write this doc
2. ✅ **Z01 Phase D — GWAS Catalog API** → add real novelty comparison to `torchgwas_udip_phenotype_scan/main.nf`
3. ✅ **ZZ01 turep — create `.nf`** → `turep/main.nf` (real Python API wrap) + `turep/container/Dockerfile`
4. ✅ **ZZ01 immuneapp — create `.nf`** → `immuneapp_hla_screen/main.nf` + `immuneapp_hla_screen/container/Dockerfile`
5. ✅ **ZZ01 scupa — create blocked stub** → `scupa_polarization/main.nf` with license-blocked fast-fail

---

## Items blocked on external action

| Blocked item | Who unblocks | Ask |
|---|---|---|
| ZZ02 scGWAS ECR push | BioMate engineer with AWS creds | `docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scgwas:v1` |
| Z01 TorchGWAS ECR push | Same | Same pattern, `biomate/torchgwas:v1` |
| Scupa license | Zhao lab | Email to add MIT/Apache license to bsml320/Scupa |
| MAGMA wrap | Engineering | ~1 day; unblocks both Zhi and Zhao paper-faithful demos |
| Z02 FDA clean inference | Zhi lab | Ask: "do you have a `predict(target_fasta, ligand_sdf)` function?" |
| UKB credential for paper-faithful Z01 | UKB application | 3-month cycle; apply now |
