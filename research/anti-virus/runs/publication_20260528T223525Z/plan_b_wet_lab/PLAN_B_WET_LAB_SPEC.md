# Plan B — ANDV GP mRNA / LNP Wet-Lab Synthesis Specification

**Campaign:** `publication_20260528T223525Z`  
**Generated:** 2026-06-03  
**Purpose:** CRO-facing bundle for mRNA construct synthesis and LNP formulation (in silico validated).

---

## 1. Antigen

| Field | Value |
|-------|-------|
| UniProt | **Q9E006** (ANDV GP envelope polyprotein) |
| Protein length | 1138 aa |
| CDS (input) | 3414 nt — reverse-translated human codon table |
| Local FASTA | `assets/andv_gp_cds_reverse_translated.fasta` |
| Optimized CDS (Batch) | `s3://biomate-nextflow-work/nextflow/outputs/plan_b_andv_gp/20260528T223525Z/codon/` |

### Codon optimization results

- **737 / 1138 codons modified (64.76%)**
- Batch run: `839ff0f7-5146-4e25-8ba8-01e202401a6d`
- CAI (P0 validation): **1.0** (threshold ≥ 0.9) — PASS

**Action for CRO:** Pull `optimized_sequence.txt` from S3 codon outdir; verify ORF integrity before IVT.

---

## 2. mRNA construct (P0 QC summary)

Source: `plan_b_p0/andv_p0_mrna_validation_report.json`

| Check | Result | Threshold |
|-------|--------|-----------|
| CAI | 1.0 | ≥ 0.9 |
| 5′ window MFE | −182.7 kcal/mol | ≤ −150.0 |
| Premature stop in ORF | None | Required |
| **Overall** | **PASS** | — |

### Recommended full construct assembly (typical mRNA vaccine)

| Component | Specification |
|-----------|---------------|
| 5′ UTR | Use platform standard (e.g. α-globin or T7-optimized) |
| ORF | Optimized ANDV GP CDS from codon step |
| 3′ UTR | Platform standard (e.g. AES-mtRNR1) |
| Poly(A) | 100–120 nt (platform default) |

**Note:** P0 report validates codon-adapted ORF + 5′ structure only. Full UTR/poly(A) assembly is platform-dependent — spike gold-standard workflow **12819** passed separately (`plan_b_p0/spike_12819/`).

---

## 3. RNA secondary structure (5′ proximal)

| Metric | Value |
|--------|-------|
| Window | First 500 nt of CDS (T→U) |
| MFE | **−182.7 kcal/mol** |
| Base pairs | 161 |
| Retry run | `9b615452-8e7c-4e52-bc19-9a04c923250b` |

---

## 4. LNP formulation (in silico ranking)

Source: `plan_b_lnp/lnp_results.json`

### Recommended composition (mol %)

| Component | mol % |
|-----------|-------|
| Ionizable lipid (IL) | 50 |
| Helper lipid | 10 |
| Cholesterol | 38.5 |
| PEG-lipid | 1.5 |

### Predicted properties

| Property | Value |
|----------|-------|
| Predicted size | 80 nm |
| Predicted encapsulation efficiency | 20% |
| Endosomal escape score | 0.202 |
| Tissue targeting (liver) | 0.85 |

### Critical caveat — reformulate before animal studies

| Issue | Detail |
|-------|--------|
| Ionizable lipid pKa | **9.5** — flagged **SUBOPTIMAL** (too basic; poor endosomal ionization) |
| NP-PK stealth | **POOR** — t½ ~1.9 h blood; recommend PEG ≥ 0.15 chains/nm² or PEG MW ≥ 5000 Da |

**Wet-lab recommendation:** Start with above composition for **in vitro** transfection QC; iterate ionizable lipid pKa (target ~6.0–6.5) before in vivo PK claims.

---

## 5. Nanoparticle PK model (12867)

Source: `plan_b_np_pk/np_pk_results.json`

| Parameter | Value |
|-----------|-------|
| Blood t½ | 1.9 h |
| Liver uptake @ 24 h | 80.3% ID |
| Spleen uptake @ 24 h | 24.1% ID |
| MPS clearance risk | MEDIUM |
| Stealth rating | POOR (<2 h) |

---

## 6. Suggested wet-lab workflow

1. **Synthesize** optimized GP ORF mRNA (IVT, cap1, CleanCap or ARCA per platform)
2. **QC:** CE/HPLC, dsRNA, endotoxin, identity
3. **Formulate** LNP at recommended mol %; measure size/PDI/EE
4. **In vitro:** GP expression in HEK293 or relevant cell line (Western / flow)
5. **Iterate** LNP pKa/PEG if circulation extension required
6. **Optional:** Pseudotype or authentic ANDV BSL-4 neutralization (not in scope of this spec)

---

## 7. Artifact index

| Path | Content |
|------|---------|
| `plan_b_codon/` | Codon optimization JSON/log |
| `plan_b_lnp/lnp_results.json` | LNP ranking |
| `plan_b_p0/andv_p0_mrna_validation_report.json` | ANDV P0 QC |
| `plan_b_np_pk/np_pk_results.json` | PK simulation |
| `assets/andv_gp_full_Q9E006.fasta` | Protein reference |
| `assets/andv_gp_cds_reverse_translated.fasta` | Input CDS |

---

## 8. Manuscript cross-reference

Draft: `research/anti-virus/docs/MANUSCRIPT_PLAN_B_CODON_v1_0.md`  
Figures: `research/anti-virus/runs/manuscript_figures_v1/plan_b/`
