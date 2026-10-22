# 2026-10-22 — RadioRenalKB surrogate/Gate-A infrastructure + medchem_kb product scale-up

**Programme:** αvβ6 radioligand therapy (RLT) — renal-clearance-engineering thesis (BMA-DEC-001).
**Scope of this session:** (1) scale `medchem_kb` to a real product via free public ingestion; (2) stand
up the RadioRenalKB surrogate + Gate-A as executable, honest infrastructure.

---

## 1. medchem_kb → product scale (14,576 structured entries)

Wired the free, open, programmatic ingestions into `medchem_kb_product.summary()`
(`research/guangzhou_all_atom/cyclic_llm/`). All curated layers remain evidence-cited.

| Layer | Count | Source | Cost |
|---|---|---|---|
| ChEMBL target classes | 905 | ChEMBL `protein_classification` | $0 |
| ChEMBL mechanisms of action | 7,561 | ChEMBL `mechanism` | $0 |
| ChEMBL approved drugs (max_phase=4) | 4,225 | ChEMBL `molecule` | $0 |
| RDKit liability alerts | 1,585 | RDKit FilterCatalog | $0 |
| RDKit physchem descriptors | 210 | RDKit | $0 |
| TDC ADME/Tox datasets | 38 | PyTDC (NeurIPS'21) | $0 |
| Curated (metal / physchem / modality) | ~29 | hand-cited | — |
| **Total** | **14,576** | | **$0** |

No keys, local CPU, no GPU/spot. The 38 TDC datasets carry hundreds of thousands of labeled
molecules behind them. Files: `medchem_kb_product.py`, `medchem_kb_ingested_large.json`,
`admet_tdc_ingested.json`. Commit `8cb31233d`.

**Claim status:** this is a *capability* layer (assembled public canon), not a moat — same posture as
before, just at product scale. The moat is the renal corpus (§2).

---

## 2. RadioRenalKB — surrogate + Gate A, made executable and honest

### 2.1 Feature engine (`renal/renal_features.py`)
Deterministic sequence → interpretable renal features. Net charge at pH 7.4 via Henderson-Hasselbalch
on ionizable side chains + termini (head-to-tail cyclization handled), plus the metal-chelate complex
charge (DOTA-M(III) ≈ −1). Returns net charge, Lys/Arg/His counts, basic-residue fraction, length.

**No fabrication:** charge is a *calculation* on a *sourced* sequence; the sequence's citation is the
provenance. Sequences added so far: A20FMDV2 (Hausner 2007), DOTATATE/DOTATOC, PSMA-617.

**Mechanistic check holds** (megalin/charge thesis — higher net cationic charge → more tubular
reabsorption → worse retention):

| Construct | net charge (+chelate) | renal retention | consistent? |
|---|---|---|---|
| ¹⁷⁷Lu-A20FMDV2 | **+0.80** (1 Lys, 2 Arg) | 118 %ID/g @4h (renal injury + deaths) | ✓ worst |
| ¹⁷⁷Lu-PSMA-617 | **−1.20** | 0.42 Gy/GBq (benchmark) | ✓ best |

### 2.2 Gate A (`renal/renal_surrogate.py`)
Gate A (renal_corpus.gate_a_protocol): before any synthesis spend, an interpretable surrogate must
rank-order kidney retention **strictly better than net charge alone on ≥50 held-out published
constructs**. The harness assembles (feature, label) pairs where BOTH a sourced sequence and a
published renal label exist, then:
- usable n < 50 → **REFUSE_TO_CERTIFY** (prints the deficit + extraction target). A gate that fails
  loudly is the point — it blocks spend on a model that does not yet exist.
- usable n ≥ 50 → leave-one-out interpretable GBM vs net-charge baseline, Spearman, PASS/FAIL.

**Current verdict: REFUSE_TO_CERTIFY** — corpus=13, with_sequence=4, with_label=5, **usable=2**.
The seed is a schema scaffold, not a trainable asset. Commit `… renal_features + renal_surrogate`.

---

## 3. The real bottleneck (now exposed, not hidden): corpus extraction

Gate A cannot pass or fail until the corpus exists. The next phase is the proprietary asset: extract
**300–800 constructs** across PSMA/SSTR/GRPR/FAPI/RGD/bombesin with:
- primary-cited renal numbers (Gy/GBq human, or %ID/g preclinical, or T:K),
- `renal_protection` flag mandatory (stratify/exclude, never impute — mixing protected/unprotected
  silently corrupts the model),
- sequence (→ deterministic net charge via §2.1).

**Feasibility proven:** BioMate's own `search_literature` returns real open-access sources with the
numbers in full text — e.g. Baum 2021 ¹⁷⁷Lu-FAP-2286 first-in-human dosimetry (363 cites); Uijen 2022
¹⁷⁷Lu-PSMA-617 vs I&T 3D kidney dosimetry; ¹⁷⁷Lu-FAPI-XT phase-I dose-escalation (2026). The work is
sustained + accuracy-critical (citation integrity): search → fetch full text → extract number +
context → cite. This is "tedious literature work radiochemistry groups can't do at scale" — i.e. the moat.

## 4. Extraction run #1 — DONE (parallel, 5 agents): corpus 13 → 55

Five class-scoped extraction agents (PSMA / SSTR / FAP / GRPR+integrin / renal-protection-SAR) ran in
parallel, each returning primary-cited records through `renal_ingest.py`'s citation-integrity gate
(quarantines any record lacking a DOI/PMID, a renal label, or the mandatory `renal_protection` flag).
**42 constructs admitted, 0 quarantined → corpus = 55, 47 with renal labels.** Every number traces to a
real fetched source; agents excluded values they couldn't verify (paywalled DOTANOC, RBE-weighted ²²⁵Ac
Sv/MBq not converted to Gy/GBq, meeting abstracts flagged `verified="abstract"`).

### The key finding: the binding constraint is SEQUENCES, not dosimetry
Stratified Gate A (`unit-kind × species`; pooling incomparable units is invalid):

| stratum | labelled | with computable sequence |
|---|---|---|
| gy_per_gbq · human | 31 | 4 |
| log_pidg · mouse | 8 | 1 |
| gy_per_gbq · mouse | 5 | 0 |
| inv_tk · mouse | 3 | 0 |

Dosimetry is plentiful (47 labelled) but only **7/55 have a computable net charge**, and the best
homogeneous stratum has **4** sequence-bearing constructs (≪ 50). **Verdict: REFUSE_TO_CERTIFY.** The
next extraction must (1) attach one-letter sequences to the peptide constructs already collected,
(2) add a **SMILES→formal-charge** path so small-molecule radioligands (PSMA/FAPI urea/quinoline) get a
net charge, (3) keep unit + species + protection stratified, never pooled.

### Design levers captured (RadiopharmKB.QUANTIFIED_LEVER_EFFECTS) — 7 cited, paired effects
The magnitude each lever moves kidney retention (the generation loop's objective gradient, binder frozen):
- **Cleavable Met-Val-Lys linker** — the strongest absolute-retention lever: −70% (single) / −77% (dual
  MV-MVK) kidney @24h (Trachsel 2023); −30% for PSMA HTK01166 (Kuo 2020).
- **Net charge** — non-monotonic: −44% at net −1 (N-terminal), but **+25% at net −2 (C-terminal)**;
  placement and magnitude matter (Durante 2017). A precision lever, not "more negative = better."
- **Albumin binder** — raises absolute kidney dose ~6× but improves T:K 2.0–2.9×: a therapeutic-index
  lever, NOT renal-sparing (Kuo 2021).
- **Gelofusine (succinylated gelatin) co-infusion** — −61…−85% kidney for αvβ6 peptides (EJNMMI 2024).

### Next steps
1. Enrich existing corpus rows with sequences/SMILES (close the real gap) + add SMILES→formal-charge to
   `renal_features`; re-run stratified Gate A.
2. Extend extraction toward 300–800 cited constructs; re-run Gate A each batch (it is the spend gate).
3. Only on Gate-A **PASS**: re-aim the cyclic generation loop (`cyclic_denovo_adapter`) over
   spacer/linker/chelator (binder frozen), renal retention as objective — generating over exactly the
   levers in `QUANTIFIED_LEVER_EFFECTS` — with binding physics as a preserve guard.

**Do NOT** build the generation loop or commit synthesis spend before Gate A passes on real data.
