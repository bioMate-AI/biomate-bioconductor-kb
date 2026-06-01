# Plan A — MHC class I predictor survey (commercial product)

**Date:** 2026-05-29  
**Context:** NetMHCpan is blocked for BioMate commercialization (DTU academic license). This survey double-checks alternatives for Plan A full-GP epitope runs.

**Related:** [Computational audit](../../../docs/20260529_ANDV_COMPUTATIONAL_AUDIT_AND_MANUSCRIPT_TOOLS.md) · `science_sprint/track_plan_a_multitool.py` · `nf-core/epitopeprediction`

---

## Executive summary

| Stack | Use in BioMate |
|-------|----------------|
| **MHCnuggets + MHCflurry** | **Ship now** — already in `nf-core/epitopeprediction`, Apache-licensed |
| **FennOmix-MHC** | **Evaluate next** — Apache 2.0 PLM foundation model (2024–2025) |
| **NetMHCpan / MixMHC / ImmuneApp / MUNIS / BigMHC** | **Manuscript or licensed only** — not default product engines |

Default multitool sprint: `tools=mhcnuggets,mhcflurry` (replaces `netmhcpan`).

---

## Tier 1 — Commercial-safe (embed in product)

| Tool | Paper / release | License | In nf-core? | Plan A 8-allele panel |
|------|-----------------|---------|-------------|------------------------|
| **MHCnuggets** 2.4.x | 2018–2019; Bioconda 2025 | Apache | ✅ | ✅ Done (`PLAN_A_FULL_GP.tsv`, 113 binders) |
| **MHCflurry** 2.2 (PyTorch, Mar 2026) | Cell Systems 2018/2020 | **Apache 2.0** | ✅ module | ✅ Supported in `supported_alleles.json` |
| **FennOmix-MHC** | 2024–2025 foundation model | **Apache 2.0** | ❌ needs wrapper | TBD — `pip install fennomix-mhc` |
| **ESMCBA** | arXiv 2025 (ESM Cambrian PLM) | **MIT** | ❌ | TBD |

**Why not “old”?** MHCflurry is actively maintained (v2.2 PyTorch). MHCnuggets 2.4.x on Bioconda. Papers are 2018-era but software is current.

---

## Tier 2 — Academic SOTA (not default for SaaS)

| Tool | When | License / commercial |
|------|------|----------------------|
| **NetMHCpan 4.1/4.2** | DTU ongoing | ❌ *"Any use … commercialization is not allowed"* ([DTU terms](https://services.healthtech.dtu.dk/cgi-bin/sw_request?software=netMHCpan)) |
| **NetMHCiiPan** | DTU | ❌ Same |
| **MixMHCpred 3.0 / PRIME 2.1** | Gfeller lab 2023–2025 | ❌ For-profit requires LICR license |
| **BigMHC** | Nat Mach Intell 2023 | ❌ Academic license (JHU/Karchin) |
| **MUNIS** | Nat Mach Intell **2024** | ⚠️ Zenodo + CC-BY paper; not a product license |
| **ImmuneApp** | Nat Comm **2024** | ⚠️ GitHub MIT but paper **CC-BY-NC-ND**; authors: contact for commercial |
| **OnmiMHC** | Frontiers **2025** | ⚠️ GitHub: "academic use" |

These appear in 2024–2025 benchmarks as beating or matching NetMHCpan — but **license blocks embedding in BioMate** without negotiation.

---

## Tier 3 — Adjacent (not drop-in binding predictors)

| Tool | Role |
|------|------|
| **SwiftMHC** (bioRxiv 2025) | Affinity + 3D pMHC structures |
| **PepQueryMHC** (Genome Biology 2025) | Immunopeptidomics → tumor antigen prioritization |
| **PMGen** (Apache 2.0) | pMHC structure generation (Modeller license separate) |

---

## BioMate integration status

```text
nf-core/epitopeprediction valid tools:
  mhcnuggets, mhcnuggetsii, mhcflurry, netmhcpan*, netmhciipan*
  * requires licensed S3 tarball — rejected for product
```

| Action | Command / path |
|--------|----------------|
| Rerun MHCflurry on full GP only | `track_plan_a_multitool.py --tools mhcflurry --input s3://.../samplesheet_full_gp_s3.csv` |
| Full commercial multitool | `track_plan_a_multitool.py` (default `mhcnuggets,mhcflurry`) |
| Consensus rule (recommended) | High-confidence binder = both tools agree (or both rank in top ~2%) |

---

## Manuscript wording

- **Product / preprint:** "orthogonal open-source predictors (MHCnuggets and MHCflurry)"
- **Avoid:** claiming NetMHCpan multitool without DTU commercial license
- **Optional supplement:** cite MUNIS/ImmuneApp/MixMHC as external literature comparison only

---

## Roadmap

1. **Now:** MHCflurry rerun on publication full-GP samplesheet → merge with existing MHCnuggets TSV  
2. **Next:** Spike FennOmix-MHC Nextflow module (Apache 2.0, PLM-era)  
3. **Later:** Population coverage / immunogen design (separate from binding predictor choice)

**Version:** 1.0
