"""
CRO-ready compound order export for BioMate drug discovery campaigns.

Generates structured CSV and Markdown exports that Contract Research
Organisations (WuXi AppTec, Pharmaron, Enamine) can directly process,
filling Gap 7 in BioMate's drug discovery opportunity analysis.
"""
import csv
import json
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# RDKit optional import — degrade gracefully if not installed
# ---------------------------------------------------------------------------
try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors, DataStructs
    from rdkit.Chem import rdMolDescriptors
    _RDKIT_AVAILABLE = True
except ImportError:
    _RDKIT_AVAILABLE = False
    log.info("RDKit not available; MW and diversity estimates will be 'N/A'.")


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class CompoundOrderEntry:
    """A single compound to be included in a CRO order."""

    compound_id: str
    smiles: str
    priority_rank: int
    requested_quantity_mg: float
    scientific_rationale: str
    admet_flags: list[str] = field(default_factory=list)
    purity_spec_percent: float = 95.0
    salt_form: str = "free base"
    docking_score: Optional[float] = None
    assay_context: Optional[str] = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _estimate_mw(smiles: str) -> str:
    """Return MW string from SMILES via RDKit, or 'N/A'."""
    if not _RDKIT_AVAILABLE:
        return "N/A"
    try:
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return "N/A"
        return f"{Descriptors.ExactMolWt(mol):.2f}"
    except Exception:
        return "N/A"


def _sa_score(smiles: str) -> Optional[float]:
    """Return synthetic accessibility score (1=easy, 10=hard) or None."""
    if not _RDKIT_AVAILABLE:
        return None
    try:
        from rdkit.Chem import RDConfig
        import sys
        sa_path = os.path.join(RDConfig.RDContribDir, "SA_Score")
        if sa_path not in sys.path:
            sys.path.append(sa_path)
        import sascorer  # type: ignore[import]
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return None
        return sascorer.calculateScore(mol)
    except Exception:
        return None


def _morgan_fp(smiles: str):
    """Return a Morgan fingerprint object or None."""
    if not _RDKIT_AVAILABLE:
        return None
    try:
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return None
        return rdMolDescriptors.GetMorganFingerprintAsBitVect(mol, radius=2, nBits=2048)
    except Exception:
        return None


def _avg_tanimoto_diversity(entries: list[CompoundOrderEntry]) -> str:
    """Compute mean pairwise Tanimoto distance across all compound pairs."""
    if not _RDKIT_AVAILABLE:
        return "N/A"
    fps = [_morgan_fp(e.smiles) for e in entries]
    fps = [fp for fp in fps if fp is not None]
    if len(fps) < 2:
        return "N/A"
    distances: list[float] = []
    for i in range(len(fps)):
        for j in range(i + 1, len(fps)):
            sim = DataStructs.TanimotoSimilarity(fps[i], fps[j])
            distances.append(1.0 - sim)
    if not distances:
        return "N/A"
    avg = sum(distances) / len(distances)
    return f"{avg:.4f}"


# ---------------------------------------------------------------------------
# Exporter
# ---------------------------------------------------------------------------

class CROOrderExporter:
    """Generate CRO-ready order files for a BioMate drug discovery campaign.

    Supports WuXi AppTec, Pharmaron, and Enamine Real Space CSV formats plus
    a Markdown scientific summary and a JSON QC report.
    """

    def __init__(self, campaign_id: str, output_dir: str):
        self.campaign_id = campaign_id
        self.output_dir = output_dir
        self._compounds: list[CompoundOrderEntry] = []
        os.makedirs(self.output_dir, exist_ok=True)

    # ------------------------------------------------------------------
    # Compound management
    # ------------------------------------------------------------------

    def add_compound(self, entry: CompoundOrderEntry) -> None:
        """Add a compound to the current order set."""
        self._compounds.append(entry)

    # ------------------------------------------------------------------
    # CSV exports
    # ------------------------------------------------------------------

    def export_wuxi_csv(self, filename: str = "wuxi_order.csv") -> str:
        """Export in WuXi AppTec format.

        Columns: Compound_ID, SMILES, Quantity_mg, Purity_%, Salt_Form,
                 Priority, Scientific_Rationale.
        """
        path = os.path.join(self.output_dir, filename)
        fieldnames = [
            "Compound_ID", "SMILES", "Quantity_mg", "Purity_%",
            "Salt_Form", "Priority", "Scientific_Rationale",
        ]
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for e in sorted(self._compounds, key=lambda x: x.priority_rank):
                writer.writerow({
                    "Compound_ID": e.compound_id,
                    "SMILES": e.smiles,
                    "Quantity_mg": e.requested_quantity_mg,
                    "Purity_%": e.purity_spec_percent,
                    "Salt_Form": e.salt_form,
                    "Priority": e.priority_rank,
                    "Scientific_Rationale": e.scientific_rationale,
                })
        log.info("WuXi CSV written: %s", path)
        return path

    def export_pharmaron_csv(self, filename: str = "pharmaron_order.csv") -> str:
        """Export in Pharmaron format.

        Columns: ID, Structure_SMILES, MW_estimate, Priority_Rank,
                 Requested_Amount_mg, Purity_Requirement, Rationale.
        MW is calculated from SMILES via RDKit if available, else 'N/A'.
        """
        path = os.path.join(self.output_dir, filename)
        fieldnames = [
            "ID", "Structure_SMILES", "MW_estimate", "Priority_Rank",
            "Requested_Amount_mg", "Purity_Requirement", "Rationale",
        ]
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for e in sorted(self._compounds, key=lambda x: x.priority_rank):
                writer.writerow({
                    "ID": e.compound_id,
                    "Structure_SMILES": e.smiles,
                    "MW_estimate": _estimate_mw(e.smiles),
                    "Priority_Rank": e.priority_rank,
                    "Requested_Amount_mg": e.requested_quantity_mg,
                    "Purity_Requirement": f"{e.purity_spec_percent}%",
                    "Rationale": e.scientific_rationale,
                })
        log.info("Pharmaron CSV written: %s", path)
        return path

    def export_enamine_csv(self, filename: str = "enamine_order.csv") -> str:
        """Export in Enamine Real Space format.

        Columns: SMILES, Catalog_ID (blank), Amount_mg, Priority.
        """
        path = os.path.join(self.output_dir, filename)
        fieldnames = ["SMILES", "Catalog_ID", "Amount_mg", "Priority"]
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for e in sorted(self._compounds, key=lambda x: x.priority_rank):
                writer.writerow({
                    "SMILES": e.smiles,
                    "Catalog_ID": "",
                    "Amount_mg": e.requested_quantity_mg,
                    "Priority": e.priority_rank,
                })
        log.info("Enamine CSV written: %s", path)
        return path

    # ------------------------------------------------------------------
    # Markdown scientific summary
    # ------------------------------------------------------------------

    def export_scientific_summary(
        self, filename: str = "compound_set_rationale.md"
    ) -> str:
        """Generate a Markdown document with campaign rationale and ADMET summary.

        Sections:
          - Campaign metadata
          - Summary table (rank, compound ID, SMILES, rationale)
          - ADMET pre-filter summary (flagged compounds)
          - SA score distribution (mock note if RDKit unavailable)
          - Executive summary paragraph
        """
        path = os.path.join(self.output_dir, filename)
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        compounds = sorted(self._compounds, key=lambda x: x.priority_rank)

        lines: list[str] = [
            f"# Compound Set Scientific Summary",
            f"",
            f"**Campaign ID:** {self.campaign_id}  ",
            f"**Generated:** {now}  ",
            f"**Total compounds:** {len(compounds)}  ",
            f"",
            f"---",
            f"",
            f"## Compound Summary Table",
            f"",
            f"| Rank | Compound ID | SMILES | Rationale |",
            f"|------|-------------|--------|-----------|",
        ]
        for e in compounds:
            smiles_short = e.smiles if len(e.smiles) <= 40 else e.smiles[:37] + "..."
            rationale_short = (
                e.scientific_rationale
                if len(e.scientific_rationale) <= 80
                else e.scientific_rationale[:77] + "..."
            )
            lines.append(
                f"| {e.priority_rank} | {e.compound_id} | `{smiles_short}` | {rationale_short} |"
            )

        # ADMET pre-filter summary
        flagged = [e for e in compounds if e.admet_flags]
        lines += [
            f"",
            f"---",
            f"",
            f"## ADMET Pre-filter Summary",
            f"",
        ]
        if flagged:
            lines.append(
                f"{len(flagged)} of {len(compounds)} compounds carry ADMET flags "
                f"and require additional review before ordering.\n"
            )
            lines.append("| Compound ID | ADMET Flags |")
            lines.append("|-------------|-------------|")
            for e in flagged:
                lines.append(f"| {e.compound_id} | {', '.join(e.admet_flags)} |")
        else:
            lines.append("All compounds passed ADMET pre-filters — no flags raised.")

        # SA score distribution
        lines += [
            f"",
            f"---",
            f"",
            f"## Synthetic Accessibility (SA) Score Distribution",
            f"",
        ]
        if _RDKIT_AVAILABLE:
            sa_scores = [(e.compound_id, _sa_score(e.smiles)) for e in compounds]
            available_scores = [(cid, s) for cid, s in sa_scores if s is not None]
            if available_scores:
                vals = [s for _, s in available_scores]
                lines.append(f"| Compound ID | SA Score (1=easy, 10=hard) |")
                lines.append(f"|-------------|---------------------------|")
                for cid, s in available_scores:
                    lines.append(f"| {cid} | {s:.2f} |")
                lines.append(f"")
                lines.append(
                    f"**Mean SA score:** {sum(vals)/len(vals):.2f} "
                    f"(range {min(vals):.2f}–{max(vals):.2f})"
                )
            else:
                lines.append("SA scores could not be computed (invalid SMILES).")
        else:
            lines.append(
                "_RDKit not installed — SA scores unavailable. "
                "Install rdkit-pypi for synthetic accessibility estimates._"
            )

        # Executive summary
        rationale_blob = " ".join(
            e.scientific_rationale for e in compounds[:5]
        )
        exec_summary = (
            f"This compound set was selected for Campaign {self.campaign_id} "
            f"based on integrated docking, ADMET prediction, and assay context. "
            f"Top-ranked compounds were prioritised as follows: {rationale_blob[:300]}. "
            f"ADMET pre-filters identified {len(flagged)} compound(s) requiring "
            f"additional scrutiny. The full ranked list and vendor order files are "
            f"provided in the accompanying CSV exports."
        )
        lines += [
            f"",
            f"---",
            f"",
            f"## Executive Summary",
            f"",
            exec_summary,
            f"",
        ]

        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        log.info("Scientific summary written: %s", path)
        return path

    # ------------------------------------------------------------------
    # QC report
    # ------------------------------------------------------------------

    def export_qc_report(self, filename: str = "qc_summary.json") -> str:
        """Write a JSON QC report for the current compound set.

        Fields: n_compounds, admet_pass_rate, priority_distribution,
                diversity_estimate, timestamp.
        """
        path = os.path.join(self.output_dir, filename)

        n = len(self._compounds)
        n_clean = sum(1 for e in self._compounds if not e.admet_flags)
        admet_pass_rate = (n_clean / n) if n > 0 else 0.0

        top10 = sum(1 for e in self._compounds if e.priority_rank <= 10)
        mid = sum(1 for e in self._compounds if 11 <= e.priority_rank <= 20)
        tail = sum(1 for e in self._compounds if e.priority_rank >= 21)

        report = {
            "campaign_id": self.campaign_id,
            "n_compounds": n,
            "admet_pass_rate": round(admet_pass_rate, 4),
            "priority_distribution": {
                "top10": top10,
                "11-20": mid,
                "21+": tail,
            },
            "diversity_estimate": _avg_tanimoto_diversity(self._compounds),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        with open(path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2)
        log.info("QC report written: %s", path)
        return path

    # ------------------------------------------------------------------
    # Convenience: export all
    # ------------------------------------------------------------------

    def export_all(self, prefix: str = "") -> dict[str, str]:
        """Run all four exports and return a mapping of format name → file path.

        Args:
            prefix: Optional filename prefix (e.g. campaign slug).
        """
        def _name(base: str) -> str:
            return f"{prefix}{base}" if prefix else base

        return {
            "wuxi_csv": self.export_wuxi_csv(_name("wuxi_order.csv")),
            "pharmaron_csv": self.export_pharmaron_csv(_name("pharmaron_order.csv")),
            "enamine_csv": self.export_enamine_csv(_name("enamine_order.csv")),
            "scientific_summary": self.export_scientific_summary(
                _name("compound_set_rationale.md")
            ),
            "qc_report": self.export_qc_report(_name("qc_summary.json")),
        }
