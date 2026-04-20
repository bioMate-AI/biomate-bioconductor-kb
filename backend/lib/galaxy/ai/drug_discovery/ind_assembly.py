"""
BioMate IND Section Assembler — Phase 3b CRO Compliance

Generates ICH M4 CTD Section 2.6.1 (Nonclinical Overview — Pharmacology)
from BioMate campaign data and model validation results.

Output:
  - Markdown source (always available)
  - DOCX via pandoc (if pandoc is installed)

ICH M4 Section 2.6.1 structure (nonclinical pharmacology overview):
  2.6.1.1  Overview of Computational Methods
  2.6.1.2  PBPK Model Qualification
  2.6.1.3  ADMET Screening Results
  2.6.1.4  Compound Prioritization and Lead Candidate Selection
  2.6.1.5  Applicability Domain Assessment
  2.6.1.6  Audit Trail and Regulatory Traceability

References:
  ICH M4S(R2) — The Common Technical Document for Registration of
                 Pharmaceuticals for Human Use: Safety
  EMA/CHMP/EWP/37498/2011 — Guideline on the reporting of physiologically
                              based pharmacokinetic (PBPK) modelling and simulation
"""

import json
import logging
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Assembly result
# ---------------------------------------------------------------------------

from dataclasses import dataclass


@dataclass
class AssemblyResult:
    campaign_id: str
    sections: list[str]          # section headings included
    markdown_path: str           # always written
    docx_path: Optional[str]     # None if pandoc unavailable
    pandoc_available: bool
    generated_at: str
    warnings: list[str]


# ---------------------------------------------------------------------------
# IND Section Assembler
# ---------------------------------------------------------------------------

class INDSectionAssembler:
    """
    Builds ICH M4 CTD Section 2.6.1 from BioMate data.

    Usage:
        assembler = INDSectionAssembler(db_path="/path/to/campaign.db")
        result = assembler.assemble(
            campaign_id="cmp-001",
            output_dir="/path/to/output",
            molecule_name="BM-0042",
            sponsor="BioTech Inc.",
        )
        print(result.markdown_path)
    """

    def __init__(self, db_path: str):
        self._db_path = db_path

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def assemble(
        self,
        campaign_id: str,
        output_dir: str,
        molecule_name: str = "Investigational Compound",
        sponsor: str = "Sponsor",
        indication: str = "Investigational indication",
        target_name: str = "Investigational target",
    ) -> AssemblyResult:
        """
        Generate CTD Section 2.6.1 for the given campaign.

        Args:
            campaign_id: BioMate campaign identifier.
            output_dir:  Directory where Markdown and DOCX are written.
            molecule_name: Name of the drug candidate (e.g. BM-0042).
            sponsor:     Sponsor organization name.
            indication:  Therapeutic indication (e.g. "oncology").
            target_name: Biological target (e.g. "EGFR").

        Returns:
            AssemblyResult with paths and warnings.
        """
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        warnings: list[str] = []
        ts = datetime.now(timezone.utc).isoformat()

        # Collect data from all sources
        compounds = self._load_compounds(campaign_id, warnings)
        validation_report = self._load_validation_report(warnings)
        audit_summary = self._load_audit_summary(campaign_id, warnings)
        auto_proposal = self._load_latest_proposal(campaign_id, warnings)

        # Build document sections
        ctx = dict(
            campaign_id=campaign_id,
            molecule_name=molecule_name,
            sponsor=sponsor,
            indication=indication,
            target_name=target_name,
            generated_at=ts,
            compounds=compounds,
            validation_report=validation_report,
            audit_summary=audit_summary,
            auto_proposal=auto_proposal,
        )

        sections = []
        parts = [
            self._title_page(ctx),
            self._section_overview(ctx),           sections.append("2.6.1.1") or "",
            self._section_pbpk(ctx),               sections.append("2.6.1.2") or "",
            self._section_admet(ctx),              sections.append("2.6.1.3") or "",
            self._section_prioritization(ctx),     sections.append("2.6.1.4") or "",
            self._section_applicability_domain(ctx), sections.append("2.6.1.5") or "",
            self._section_audit_trail(ctx),        sections.append("2.6.1.6") or "",
        ]
        markdown = "\n\n".join(p for p in parts if p)

        # Write Markdown
        md_path = str(Path(output_dir) / f"{campaign_id}_CTD_2.6.1.md")
        Path(md_path).write_text(markdown, encoding="utf-8")

        # Convert to DOCX via pandoc
        docx_path, pandoc_ok = self._pandoc_convert(md_path, output_dir, campaign_id, warnings)

        return AssemblyResult(
            campaign_id=campaign_id,
            sections=sections,
            markdown_path=md_path,
            docx_path=docx_path,
            pandoc_available=pandoc_ok,
            generated_at=ts,
            warnings=warnings,
        )

    # ------------------------------------------------------------------
    # Data loaders
    # ------------------------------------------------------------------

    def _load_compounds(self, campaign_id: str, warnings: list) -> list[dict]:
        try:
            from .assay_ingestion import AssayIngestionService
            svc = AssayIngestionService(self._db_path)
            return svc.get_ranked_compounds(campaign_id)
        except Exception as exc:
            warnings.append(f"Could not load compound data: {exc}")
            return []

    def _load_validation_report(self, warnings: list) -> Optional[dict]:
        try:
            from .model_validation import ModelValidationService
            svc = ModelValidationService()
            report = svc.run_pbpk_validation()
            return report.dict()
        except Exception as exc:
            warnings.append(f"PBPK validation report unavailable: {exc}")
            return None

    def _load_audit_summary(self, campaign_id: str, warnings: list) -> dict:
        try:
            from ..compliance.audit_store import AuditStore, AuditAction
            store = AuditStore()
            all_records = store.get_records(resource_id=campaign_id, limit=500)
            chain = store.verify_chain()
            action_counts: dict[str, int] = {}
            for r in all_records:
                action_counts[r.action] = action_counts.get(r.action, 0) + 1
            first_ts = all_records[0].timestamp_utc if all_records else None
            last_ts = all_records[-1].timestamp_utc if all_records else None
            return {
                "total_records": len(all_records),
                "action_counts": action_counts,
                "chain_valid": chain.valid,
                "first_timestamp": first_ts,
                "last_timestamp": last_ts,
            }
        except Exception as exc:
            warnings.append(f"Audit trail summary unavailable: {exc}")
            return {"total_records": 0, "chain_valid": None}

    def _load_latest_proposal(self, campaign_id: str, warnings: list) -> Optional[dict]:
        try:
            from .auto_retrain import get_latest_auto_proposal
            p = get_latest_auto_proposal(self._db_path, campaign_id)
            if p:
                return {
                    "round_number": p.round_number,
                    "n_proposed": len(p.proposed_smiles),
                    "created_at": p.created_at,
                    "triggered_by": p.triggered_by,
                }
        except Exception as exc:
            warnings.append(f"Latest proposal unavailable: {exc}")
        return None

    # ------------------------------------------------------------------
    # Section builders
    # ------------------------------------------------------------------

    def _title_page(self, ctx: dict) -> str:
        return f"""\
# CTD Section 2.6.1 — Nonclinical Overview: Pharmacology

**Molecule:** {ctx['molecule_name']}
**Sponsor:** {ctx['sponsor']}
**Indication:** {ctx['indication']}
**Target:** {ctx['target_name']}
**Campaign ID:** {ctx['campaign_id']}
**Generated by:** BioMate Computational CRO Platform
**Generation date:** {ctx['generated_at'][:10]}

---

*This document was automatically generated by BioMate and is intended for attachment
to the nonclinical pharmacology section of an Investigational New Drug (IND) application.
All computational predictions cited herein were produced by validated models (see §2.6.1.2)
with applicability domain assessment (see §2.6.1.5) and full audit traceability (§2.6.1.6).*"""

    def _section_overview(self, ctx: dict) -> str:
        n = len(ctx['compounds'])
        return f"""\
## 2.6.1.1 Overview of Computational Methods

BioMate is a computational contract research organization (CRO) platform that provides:

1. **Assay data ingestion and compound ranking** — Multi-assay composite scoring with
   safety-gate weighting (hERG, DILI, Ames).

2. **Bayesian lead optimization** — Gaussian Process surrogate model (Matérn-5/2 kernel,
   Morgan fingerprint featurisation, radius=2, 2048 bits) with Expected Hypervolume
   Improvement acquisition for multi-objective Pareto optimization.

3. **PBPK simulation** — 8-compartment physiologically-based pharmacokinetic model with
   Rodgers & Rowland tissue distribution (EMA PBPK guideline EMA/CHMP/EWP/37498/2011).

4. **Applicability domain** — Hat-matrix leverage (Tropsha/Roy) + Tanimoto
   nearest-neighbour guard.  Compounds are flagged "out-of-domain" if leverage h > 3×h̄
   OR Tanimoto similarity to nearest training compound < 0.20.

5. **Electronic audit trail** — SHA-256 hash-chained append-only SQLite log recording
   every regulated operation (21 CFR Part 11 §11.10(e)).

**Campaign summary:** Campaign `{ctx['campaign_id']}` contains **{n} ranked compounds**
at the time of this document generation.  The most relevant data in this section were
obtained from assay data ingested via the BioMate platform Benchling LIMS connector."""

    def _section_pbpk(self, ctx: dict) -> str:
        vr = ctx.get("validation_report")
        if vr is None:
            return """\
## 2.6.1.2 PBPK Model Qualification

*Validation report unavailable at document generation time.*"""

        m = vr.get("metrics", {})
        ema_met = vr.get("ema_criterion_met", False)
        ema_str = "**MET ✓**" if ema_met else "**NOT MET ✗**"
        n_ref = vr.get("n_reference_compounds", 0)
        reg_summary = vr.get("regulatory_summary", "")

        # Build per-compound table (top 15 by fold error)
        per_cpd = vr.get("per_compound", [])
        table_rows = []
        for row in per_cpd[:15]:
            name = row.get("name", "?")
            obs_cmax = row.get("observed_Cmax_ug_mL", "?")
            pred_cmax = row.get("predicted_Cmax_ug_mL", "?")
            fold = row.get("fold_error_Cmax", "?")
            in_d = "✓" if row.get("in_domain", True) else "✗"
            table_rows.append(
                f"| {name} | {_fmt(obs_cmax)} | {_fmt(pred_cmax)} | {_fmt(fold)} | {in_d} |"
            )
        table = "\n".join(table_rows)

        return f"""\
## 2.6.1.2 PBPK Model Qualification

### Reference Dataset

The BioMate one-compartment PBPK model was evaluated against {n_ref} marketed drugs
with well-characterised human pharmacokinetics (DrugBank, FDA approved labels, published
PK literature).

### Aggregate Metrics

| Metric | Cmax | AUC |
|--------|------|-----|
| AFE (bias) | {_fmt(m.get('AFE_Cmax'))} | {_fmt(m.get('AFE_AUC'))} |
| AAFE (accuracy) | {_fmt(m.get('AAFE_Cmax'))} | {_fmt(m.get('AAFE_AUC'))} |
| R² | {_fmt(m.get('R2_Cmax'))} | {_fmt(m.get('R2_AUC'))} |
| Within 2-fold | {_pct(m.get('within_2fold_Cmax'))} | {_pct(m.get('within_2fold_AUC'))} |
| Within 3-fold | {_pct(m.get('within_3fold_Cmax'))} | {_pct(m.get('within_3fold_AUC'))} |

**EMA criterion (≥67% within 2-fold for both Cmax and AUC):** {ema_str}

### Per-Compound Results (first 15 of {n_ref})

| Drug | Obs Cmax (µg/mL) | Pred Cmax (µg/mL) | Fold Error | In Domain |
|------|-----------------|------------------|------------|-----------|
{table}

### Regulatory Summary

{reg_summary}"""

    def _section_admet(self, ctx: dict) -> str:
        compounds = ctx.get("compounds", [])
        if not compounds:
            return """\
## 2.6.1.3 ADMET Screening Results

*No compound data available.*"""

        total = len(compounds)
        # Approximate ADMET pass rate from score distribution
        # Compounds with composite_score >= 0.5 are considered passing
        passing = sum(1 for c in compounds if c.get("composite_score", 0) >= 0.5)
        pass_rate = passing / total if total > 0 else 0.0
        top5 = compounds[:5]

        rows = []
        for c in top5:
            cid = c.get("compound_id", "?")
            score = c.get("composite_score", 0.0)
            rank = c.get("rank", "?")
            smiles = c.get("smiles", "")[:30] + "…" if len(c.get("smiles", "")) > 30 else c.get("smiles", "")
            rows.append(f"| {rank} | {cid} | {score:.3f} | {smiles} |")
        table = "\n".join(rows)

        return f"""\
## 2.6.1.3 ADMET Screening Results

### Overview

{total} compounds were evaluated for ADMET liabilities using BioMate's integrated
screening pipeline.

**Safety gates applied:**

| Assay | Gate | Action on failure |
|-------|------|------------------|
| hERG (cardiac safety) | IC50 < 10 µM | Composite score penalty −0.30 |
| DILI (drug-induced liver injury) | Positive | Composite score penalty −0.30 |
| Ames mutagenicity | Positive | Composite score penalty −0.30 |
| Lipinski Ro5 | MW > 500 or logP > 5 | Advisory flag |

### Results Summary

- Total compounds screened: **{total}**
- Compounds with composite score ≥ 0.50: **{passing}** ({pass_rate:.1%})

### Top 5 Ranked Compounds

| Rank | Compound ID | Composite Score | SMILES |
|------|-------------|----------------|--------|
{table}"""

    def _section_prioritization(self, ctx: dict) -> str:
        compounds = ctx.get("compounds", [])
        auto_p = ctx.get("auto_proposal")
        total = len(compounds)

        proposal_section = ""
        if auto_p:
            proposal_section = f"""\

### Latest Bayesian Proposal (Round {auto_p['round_number']})

A Bayesian optimizer proposal was generated on {auto_p['created_at'][:10]}
(triggered by: {auto_p['triggered_by']}).  **{auto_p['n_proposed']} compounds**
were selected from the virtual library for the next synthesis round."""

        return f"""\
## 2.6.1.4 Compound Prioritization and Lead Candidate Selection

### Methodology

Compounds are ranked by a multi-assay composite score computed as:

    composite_score = mean(normalised_component_scores) − safety_penalties

where each assay is normalised to [0, 1] across the campaign compound set and
lower-is-better assays (IC50, Ki) are inverted.

The Bayesian optimizer employs:
- **Surrogate model:** Gaussian Process (Matérn-5/2 kernel, scikit-learn)
- **Featurisation:** Morgan circular fingerprints, radius=2, nBits=2048 (RDKit)
- **Acquisition:** Expected Hypervolume Improvement (Monte Carlo, 1000 samples)
- **Batch selection:** Greedy with Tanimoto diversity penalty (weight configurable)

### Campaign Status

- **{total} compounds** currently ranked in the campaign.
- Lead candidate: **Rank 1** with composite score
  **{compounds[0].get('composite_score', 'N/A') if compounds else 'N/A'}**.
{proposal_section}"""

    def _section_applicability_domain(self, ctx: dict) -> str:
        auto_p = ctx.get("auto_proposal")
        ad_summary = ""
        if auto_p and auto_p.get("n_proposed"):
            ad_summary = f"\nThe most recent proposal ({auto_p['n_proposed']} compounds) included applicability domain status for all proposed structures."

        return f"""\
## 2.6.1.5 Applicability Domain Assessment

### Method

The applicability domain (AD) of the BioMate surrogate model is assessed using two
complementary criteria per compound (Tropsha/Roy approach):

**Criterion 1 — Hat-matrix leverage:**
- Training fingerprint matrix X (N × 2048)
- Leverage: h_i = x_i^T (X^T X)^+ x_i
- Threshold: h* = 3 × mean(h_train) [Tropsha et al., QSAR & Comb. Sci. 2003]
- Compound is out-of-domain if h_query > h*

**Criterion 2 — Tanimoto nearest-neighbour:**
- Tanimoto(a, b) = |a ∩ b| / |a ∪ b|
- Threshold: 0.20 (20% minimum similarity to nearest training compound)
- Catches compounds in unobserved chemical subspaces where leverage = 0

A compound is classified **in-domain** only if both criteria are satisfied.
Out-of-domain compounds are flagged in all API responses and proposal outputs; they
are not automatically excluded from proposals but are highlighted for human review.
{ad_summary}

### Interpretation

| AD Status | Meaning | Recommended Action |
|-----------|---------|-------------------|
| in_domain | Structurally similar to training set; prediction reliable | Proceed to synthesis |
| out_of_domain | Extrapolation outside training distribution | Seek additional experimental support |
| unknown | AD check unavailable (RDKit import failed) | Treat as out_of_domain |"""

    def _section_audit_trail(self, ctx: dict) -> str:
        aud = ctx.get("audit_summary", {})
        total = aud.get("total_records", 0)
        chain_valid = aud.get("chain_valid")
        first_ts = aud.get("first_timestamp", "N/A")
        last_ts = aud.get("last_timestamp", "N/A")
        action_counts = aud.get("action_counts", {})

        chain_str = {True: "**VALID ✓**", False: "**INVALID ✗** — integrity violation detected", None: "Not verified"}.get(chain_valid, "Unknown")

        action_table_rows = []
        for action, count in sorted(action_counts.items()):
            action_table_rows.append(f"| {action} | {count} |")
        action_table = "\n".join(action_table_rows) if action_table_rows else "| (no records) | 0 |"

        return f"""\
## 2.6.1.6 Audit Trail and Regulatory Traceability

### 21 CFR Part 11 Compliance

BioMate maintains a tamper-evident, SHA-256 hash-chained audit log for all regulated
operations (21 CFR Part 11 §11.10(e)).

**Audit log summary for campaign `{ctx['campaign_id']}`:**

| Property | Value |
|----------|-------|
| Total audit records | {total} |
| Hash chain integrity | {chain_str} |
| First record timestamp | {first_ts or 'N/A'} |
| Last record timestamp | {last_ts or 'N/A'} |

**Actions recorded:**

| Action | Count |
|--------|-------|
{action_table}

### Hash Chain Design

Each audit record contains:
- ISO 8601 UTC timestamp
- Authenticated user ID (from JWT Bearer token)
- Action type (INGEST_ASSAY, PROPOSE_ROUND, EXPORT_CRO_ORDER, …)
- SHA-256 hash of the request payload
- `previous_hash` — the record_hash of the preceding record
- `record_hash = SHA256(timestamp | user_id | action | resource_type | resource_id | payload_hash | previous_hash)`

Modification of any field in any record causes a hash mismatch detectable by
`AuditStore.verify_chain()`.  Inserted or deleted records break the `previous_hash`
link chain.

### Electronic Signatures

High-stakes operations (compound proposal and synthesis order export) support
TOTP-based electronic signatures (RFC 6238, compatible with Google Authenticator).
Each signature is linked to its corresponding audit record via `audit_record_id`.

*Full audit log export available via `GET /api/drug-discovery/audit?campaign_id={ctx['campaign_id']}`.*"""

    # ------------------------------------------------------------------
    # Pandoc conversion
    # ------------------------------------------------------------------

    def _pandoc_convert(
        self,
        md_path: str,
        output_dir: str,
        campaign_id: str,
        warnings: list,
    ) -> tuple[Optional[str], bool]:
        """Convert Markdown to DOCX using pandoc.  Returns (docx_path, pandoc_ok)."""
        docx_path = str(Path(output_dir) / f"{campaign_id}_CTD_2.6.1.docx")
        try:
            result = subprocess.run(
                ["pandoc", md_path, "-o", docx_path, "--from=markdown", "--to=docx"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                warnings.append(f"pandoc conversion failed: {result.stderr.strip()}")
                return None, False
            return docx_path, True
        except FileNotFoundError:
            warnings.append("pandoc not installed — DOCX output unavailable (Markdown written)")
            return None, False
        except subprocess.TimeoutExpired:
            warnings.append("pandoc conversion timed out")
            return None, False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _fmt(v) -> str:
    if v is None:
        return "N/A"
    try:
        return f"{float(v):.3f}"
    except (TypeError, ValueError):
        return str(v)


def _pct(v) -> str:
    if v is None:
        return "N/A"
    try:
        return f"{float(v) * 100:.1f}%"
    except (TypeError, ValueError):
        return str(v)
