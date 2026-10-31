"""
CSV schema definition and validator for BioMate assay data ingestion.

Every assay_type has an EndpointRule describing the units it accepts and the
physically possible range of its normalised value; rows outside that range
are rejected with an explanation. Compound identity is checked by canonical
structure: one compound_id may not map to two different structures within a
campaign (see find_identity_conflicts).
"""
import csv
import logging
import math
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

log = logging.getLogger(__name__)

REQUIRED_COLUMNS = {"compound_id", "assay_type", "value", "unit", "assay_date"}
OPTIONAL_COLUMNS = {"smiles", "operator", "operator_note"}

VALID_OPERATORS = {"<", ">", "=", "~"}

# Concentration units → factor to µM.
UNIT_NORMALIZATION = {
    "nM": 1e-3,   # divide by 1000 → uM
    "mM": 1e3,    # multiply by 1000 → uM
    "uM": 1.0,
}

# Percent endpoints are bounded with this tolerance (percentage points) to
# allow normal assay noise around 0% and 100% while rejecting sign/unit errors.
PERCENT_TOLERANCE = 20.0


@dataclass(frozen=True)
class EndpointRule:
    """Accepted units and physical range of one assay endpoint.

    ``units`` maps each accepted unit to the factor that converts it to
    ``normalized_unit``. Bounds apply to the normalised value.
    """
    units: dict
    normalized_unit: str
    description: str
    lower: Optional[float] = None
    lower_inclusive: bool = True
    upper: Optional[float] = None
    allowed_values: Optional[frozenset] = None

    def check(self, value: float) -> Optional[str]:
        if self.allowed_values is not None and value not in self.allowed_values:
            allowed = ", ".join(f"{v:g}" for v in sorted(self.allowed_values))
            return f"must be one of {allowed} ({self.description}); got {value:g}"
        if self.lower is not None and (value < self.lower or
                                       (value == self.lower and not self.lower_inclusive)):
            op = ">=" if self.lower_inclusive else ">"
            return f"must be {op} {self.lower:g} {self.normalized_unit} ({self.description}); got {value:g}"
        if self.upper is not None and value > self.upper:
            return f"must be <= {self.upper:g} {self.normalized_unit} ({self.description}); got {value:g}"
        return None


def _positive_concentration(description: str) -> EndpointRule:
    return EndpointRule(units=dict(UNIT_NORMALIZATION), normalized_unit="uM",
                        description=description, lower=0.0, lower_inclusive=False)


# Dimensionless endpoints historically accepted "uM" (factor 1, value stored
# unchanged); that spelling stays valid. nM/mM are rejected for them because
# they would rescale a number that is not a concentration.
_DIMENSIONLESS_UNITS = {"": 1.0, "uM": 1.0}
_FLAG = EndpointRule(units={**_DIMENSIONLESS_UNITS, "flag": 1.0}, normalized_unit="flag",
                     description="binary safety flag: 1 = positive/fail, 0 = negative/pass",
                     allowed_values=frozenset({0.0, 1.0}))

ENDPOINT_RULES: dict[str, EndpointRule] = {
    "IC50": _positive_concentration("half-maximal inhibitory concentration"),
    "EC50": _positive_concentration("half-maximal effective concentration"),
    "Ki": _positive_concentration("inhibition constant"),
    "Kd": _positive_concentration("dissociation constant"),
    "hERG": _positive_concentration("hERG IC50"),
    "solubility": _positive_concentration("solubility concentration"),
    "permeability": EndpointRule(units=dict(UNIT_NORMALIZATION), normalized_unit="uM",
                                 description="permeability", lower=0.0),
    "pIC50": EndpointRule(units={"": 1.0, "-log10(M)": 1.0, "-log(M)": 1.0},
                          normalized_unit="-log10(M)",
                          description="pIC50 = -log10(IC50 in M); 1-13 spans 100 mM to 0.1 pM",
                          lower=1.0, upper=13.0),
    "percent_inhibition": EndpointRule(units={"%": 1.0}, normalized_unit="%",
                                       description="percent inhibition at a test concentration",
                                       lower=-PERCENT_TOLERANCE, upper=100.0 + PERCENT_TOLERANCE),
    "cell_viability": EndpointRule(units={**_DIMENSIONLESS_UNITS, "%": 1.0}, normalized_unit="%",
                                   description="percent viability relative to control",
                                   lower=-PERCENT_TOLERANCE, upper=200.0),
    "selectivity_ratio": EndpointRule(units={**_DIMENSIONLESS_UNITS, "ratio": 1.0, "fold": 1.0},
                                      normalized_unit="ratio",
                                      description="ratio of off-target to on-target potency",
                                      lower=0.0, lower_inclusive=False),
    "DILI": _FLAG,
    "Ames": _FLAG,
    "ClinTox": _FLAG,
    "custom": EndpointRule(units=dict(UNIT_NORMALIZATION), normalized_unit="uM",
                           description="custom endpoint (no physical range known)"),
}

SUPPORTED_ASSAY_TYPES = set(ENDPOINT_RULES)


# ── Structure identity ──────────────────────────────────────────────────────

try:
    from rdkit import Chem, RDLogger
    RDLogger.DisableLog("rdApp.*")
    _RDKIT_AVAILABLE = True
except ImportError:  # pragma: no cover - RDKit is a backend dependency
    Chem = None
    _RDKIT_AVAILABLE = False
    log.warning("RDKit unavailable: compound identity falls back to exact SMILES text, "
                "so equivalent spellings of one structure are reported as conflicts.")


def canonical_structure(smiles: str) -> tuple[Optional[str], Optional[str]]:
    """Return (canonical isomeric SMILES, error). Empty input → (None, None)."""
    smiles = (smiles or "").strip()
    if not smiles:
        return None, None
    if not _RDKIT_AVAILABLE:
        return smiles, None
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None, f"SMILES '{smiles}' could not be parsed as a chemical structure"
    return Chem.MolToSmiles(mol, isomericSmiles=True), None


def find_identity_conflicts(
    rows: list[dict],
    known_structures: Optional[dict[str, set[str]]] = None,
) -> tuple[list[dict], list[str]]:
    """Reject rows whose compound_id maps to more than one structure.

    ``rows`` carry ``compound_id``, ``smiles``, ``structure_key`` and
    ``source_row``. ``known_structures`` maps compound_id → canonical
    structures already stored for the campaign.

    - If the campaign already holds exactly one structure for the ID, rows
      with a different structure are rejected; matching rows are kept.
    - If the campaign already holds several structures for the ID, or this
      batch alone gives it several (with none stored), the identity is
      ambiguous and every row for that ID in the batch is rejected.
    Rows without SMILES carry no identity claim and are only rejected when
    the ID is ambiguous.
    """
    known = known_structures or {}
    batch: dict[str, dict[str, str]] = {}
    for r in rows:
        if r.get("structure_key"):
            batch.setdefault(r["compound_id"], {}).setdefault(r["structure_key"], r["smiles"])

    accepted: list[dict] = []
    errors: list[str] = []
    for r in rows:
        cid = r["compound_id"]
        stored = known.get(cid, set())
        in_batch = batch.get(cid, {})
        key = r.get("structure_key")
        prefix = f"Row {r.get('source_row', '?')}: compound_id '{cid}'"
        if len(stored) > 1:
            errors.append(f"{prefix} already maps to several structures in this campaign "
                          f"({', '.join(sorted(stored))}); resolve that identity conflict "
                          "before adding data. Row rejected.")
        elif len(stored) == 1:
            if key and key not in stored:
                errors.append(f"{prefix} has SMILES '{r['smiles']}' (canonical {key}), but this "
                              f"campaign already records it as {next(iter(stored))}. Row rejected.")
            else:
                accepted.append(r)
        elif len(in_batch) > 1:
            errors.append(f"{prefix} is given conflicting structures in this file "
                          f"({', '.join(sorted(in_batch))}; this row: {r['smiles'] or 'no SMILES'}), "
                          "so its identity is ambiguous. Row rejected.")
        else:
            accepted.append(r)
    return accepted, errors


class AssayCSVValidator:
    """Validate and normalise assay CSV files."""

    def validate(
        self,
        csv_path: str,
        known_structures: Optional[dict[str, set[str]]] = None,
    ) -> tuple[list[dict], list[str]]:
        """Parse and validate a CSV file.

        ``known_structures`` (compound_id → canonical structures already in
        the campaign) extends the identity check beyond this file.

        Returns:
            (valid_rows, error_messages) where valid_rows are dicts with
            normalised fields including `value_uM` (the value in the
            endpoint's `unit_normalized`).
        """
        valid_rows: list[dict] = []
        errors: list[str] = []

        try:
            with open(csv_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                if reader.fieldnames is None:
                    errors.append("CSV file is empty or has no header row.")
                    return valid_rows, errors

                headers = {h.strip() for h in reader.fieldnames if h}
                missing = REQUIRED_COLUMNS - headers
                if missing:
                    errors.append(f"Missing required columns: {', '.join(sorted(missing))}")
                    return valid_rows, errors

                for row_num, raw_row in enumerate(reader, start=2):
                    row = {k.strip(): (v.strip() if v else "") for k, v in raw_row.items() if k}
                    row_errors = self._validate_row(row, row_num)
                    structure_key, structure_error = canonical_structure(row.get("smiles", ""))
                    if structure_error:
                        row_errors.append(f"Row {row_num}: {structure_error}.")
                    if row_errors:
                        errors.extend(row_errors)
                        continue
                    normalised = self._normalise_row(row)
                    normalised["structure_key"] = structure_key
                    normalised["source_row"] = row_num
                    valid_rows.append(normalised)

        except FileNotFoundError:
            errors.append(f"File not found: {csv_path}")
        except Exception as exc:
            errors.append(f"Unexpected error reading CSV: {exc}")

        valid_rows, identity_errors = find_identity_conflicts(valid_rows, known_structures)
        errors.extend(identity_errors)
        return valid_rows, errors

    def _validate_row(self, row: dict, row_num: int) -> list[str]:
        errs: list[str] = []

        compound_id = row.get("compound_id", "")
        if not compound_id:
            errs.append(f"Row {row_num}: compound_id is required.")

        assay_type = row.get("assay_type", "")
        rule = ENDPOINT_RULES.get(assay_type)
        if rule is None:
            errs.append(
                f"Row {row_num}: unsupported assay_type '{assay_type}'. "
                f"Supported: {', '.join(sorted(SUPPORTED_ASSAY_TYPES))}"
            )

        unit = row.get("unit", "")
        if rule is not None and unit not in rule.units:
            accepted = ", ".join(f"'{u}'" for u in rule.units)
            errs.append(
                f"Row {row_num}: unsupported unit '{unit}' for {assay_type}. "
                f"Supported: {accepted}"
            )

        raw_value = row.get("value", "")
        try:
            value = float(raw_value)
            if not math.isfinite(value):
                errs.append(f"Row {row_num}: value must be finite.")
            elif rule is not None and unit in rule.units:
                normalised = value * rule.units[unit]
                if not math.isfinite(normalised):
                    errs.append(f"Row {row_num}: normalised value must be finite.")
                else:
                    problem = rule.check(normalised)
                    if problem:
                        errs.append(f"Row {row_num}: {assay_type} {problem}.")
        except (ValueError, TypeError):
            errs.append(f"Row {row_num}: value '{raw_value}' is not a valid number.")

        assay_date = row.get("assay_date", "")
        try:
            datetime.strptime(assay_date, "%Y-%m-%d")
        except ValueError:
            errs.append(f"Row {row_num}: assay_date '{assay_date}' must be YYYY-MM-DD.")

        operator = row.get("operator", "")
        if operator and operator not in VALID_OPERATORS:
            errs.append(
                f"Row {row_num}: operator '{operator}' must be one of "
                f"{', '.join(sorted(VALID_OPERATORS))} or empty."
            )

        return errs

    def _normalise_row(self, row: dict) -> dict:
        unit = row["unit"]
        rule = ENDPOINT_RULES[row["assay_type"]]
        raw_value = float(row["value"])

        return {
            "compound_id": row["compound_id"],
            "smiles": row.get("smiles", ""),
            "assay_type": row["assay_type"],
            "value": raw_value,
            "value_uM": raw_value * rule.units[unit],
            "unit": unit,
            "unit_normalized": rule.normalized_unit,
            "operator": row.get("operator", ""),
            "operator_note": row.get("operator_note", ""),
            "assay_date": row["assay_date"],
        }
