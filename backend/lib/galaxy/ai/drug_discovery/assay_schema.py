"""
Assay row schema and validator for BioMate assay data ingestion.

Every assay_type has an EndpointRule describing the units it accepts and the
physically possible range of its normalised value; rows outside that range
are rejected with an explanation.

Validation is row-level (AssayCSVValidator.validate_rows), so CSV uploads and
LIMS connectors share one contract; validate()/validate_csv() wrap it for CSV.

Censored values: operator '<' or '>' marks the value as a bound, not a
measurement. The operator is kept and the normalised row carries
``censored: True``; ranking and training treat such rows as bounds (see
assay_ingestion and auto_retrain.build_training_rows).

Compound identity is compared on the *parent* structure (structure_identity):
listed counterions are stripped and the remainder neutralised, so a salt and
its free base under one compound_id are one compound (reported as a note),
while different parents under one ID are a conflict. A structure with several
distinct non-counterion components (co-drug, mixture, unlisted counterion)
keeps every component in its parent key and is flagged, never collapsed.
"""
import csv
import logging
import math
from dataclasses import dataclass, field
from datetime import datetime
from typing import Iterable, Optional

log = logging.getLogger(__name__)

REQUIRED_COLUMNS = {"compound_id", "assay_type", "value", "unit", "assay_date"}
OPTIONAL_COLUMNS = {"smiles", "operator", "operator_note"}

VALID_OPERATORS = {"<", ">", "=", "~"}
# Operators that make the value a bound rather than a measurement.
CENSORING_OPERATORS = {"<", ">"}

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
    from rdkit import Chem, RDLogger, rdBase
    from rdkit.Chem.MolStandardize import rdMolStandardize
    from rdkit.Chem.SaltRemover import SaltRemover
    RDLogger.DisableLog("rdApp.*")
    _RDKIT_AVAILABLE = True
except ImportError:  # pragma: no cover - RDKit is a backend dependency
    Chem = None
    _RDKIT_AVAILABLE = False
    log.warning("RDKit unavailable: compound identity falls back to exact SMILES text, "
                "so equivalent spellings or salt forms of one structure are reported as conflicts.")

# Pharmaceutical counterions not in RDKit's default Salts.txt. Like RDKit's
# list, a pattern only strips a fragment it matches entirely, and the list
# takes priority over fragment size (oxalate is stripped from ethylamine
# oxalate although it is the larger fragment).
_EXTRA_COUNTERION_SMARTS = (
    "OC(=O)CC(O)(CC(=O)O)C(=O)O",      # citrate
    "OC(=O)CCC(=O)O",                  # succinate
    "OC(=O)CC(O)C(=O)O",               # malate
    "CC(O)C(=O)O",                     # lactate
    "[CH](=O)O",                       # formate
    "c1ccccc1S(=O)(=O)O",              # besylate
    "CCS(=O)(=O)O",                    # esylate
    "[Zn,Al]",                         # metal cations beyond the default Li/Na/K/Ca/Mg
)

_SALT_REMOVER = None


def _salt_remover():
    global _SALT_REMOVER
    if _SALT_REMOVER is None:
        remover = SaltRemover()
        for smarts in _EXTRA_COUNTERION_SMARTS:
            pattern = Chem.MolFromSmarts(smarts)
            if pattern is not None:
                remover.salts.append(pattern)
        _SALT_REMOVER = remover
    return _SALT_REMOVER


# Structure flags carried on rows and stored with them.
FLAG_SALT_STRIPPED = "salt_stripped"
FLAG_NEUTRALISED = "charge_neutralised"
FLAG_MULTI_COMPONENT = "multi_component"
FLAG_REPEATED_COMPONENT = "repeated_component"
FLAG_ALL_COUNTERIONS = "all_fragments_listed_counterions"


@dataclass(frozen=True)
class StructureIdentity:
    """As-submitted structure and the parent used for identity comparison."""
    submitted: str                  # canonical isomeric SMILES of the whole input
    parent: str                     # canonical parent: counterions removed, neutralised
    stripped: tuple = ()            # canonical SMILES of removed counterion fragments
    flags: tuple = ()

    @property
    def is_multi_component(self) -> bool:
        return FLAG_MULTI_COMPONENT in self.flags


#: Modalities whose entity column holds an amino-acid sequence, not a SMILES.
SEQUENCE_MODALITIES = ("peptide", "biologic")


def sequence_identity(seq: str) -> "tuple[Optional[StructureIdentity], Optional[str]]":
    """Identity for a peptide/biologic entity: the (uppercased, non-alpha-
    stripped) sequence is its own parent key — no chemical parsing. Mirrors the
    no-RDKit branch of structure_identity, so the whole pipeline (dedup,
    known-structure checks, ranking, build_training_rows) is reused unchanged.
    """
    s = "".join(c for c in (seq or "").upper() if c.isalpha())
    if not s:
        return None, None
    return StructureIdentity(submitted=s, parent=s), None


def _entity_identity(entity: str, modality: str):
    """Dispatch to sequence or chemical identity by modality."""
    if modality in SEQUENCE_MODALITIES:
        return sequence_identity(entity)
    return structure_identity(entity)


def structure_identity(smiles: str) -> "tuple[Optional[StructureIdentity], Optional[str]]":
    """Return (StructureIdentity, error). Empty input → (None, None)."""
    smiles = (smiles or "").strip()
    if not smiles:
        return None, None
    if not _RDKIT_AVAILABLE:
        return StructureIdentity(submitted=smiles, parent=smiles), None
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None, f"SMILES '{smiles}' could not be parsed as a chemical structure"
    blocker = rdBase.BlockLogs() if hasattr(rdBase, "BlockLogs") else None  # standardizer INFO spam
    try:
        return _identity_of(mol), None
    finally:
        del blocker


def _identity_of(mol) -> StructureIdentity:
    submitted = Chem.MolToSmiles(mol, isomericSmiles=True)
    flags: list = []
    try:
        cleaned = rdMolStandardize.Cleanup(mol)   # disconnects metals, normalises groups
    except Exception:  # pragma: no cover - RDKit sanitisation edge cases
        cleaned = mol
    fragments = Chem.GetMolFrags(cleaned, asMols=True)
    remover = _salt_remover()
    kept, stripped = [], []
    for frag in fragments:
        if len(fragments) > 1 and remover.StripMol(frag, dontRemoveEverything=False).GetNumAtoms() == 0:
            stripped.append(Chem.MolToSmiles(frag, isomericSmiles=True))
        else:
            kept.append(frag)
    if not kept:
        # Every fragment is a listed counterion (e.g. sodium acetate): the
        # carbon-containing fragments are the compound; with none, keep all.
        organic = [f for f in fragments if any(a.GetSymbol() == "C" for a in f.GetAtoms())]
        kept = organic or list(fragments)
        stripped = [Chem.MolToSmiles(f, isomericSmiles=True) for f in fragments
                    if not any(f is k for k in kept)]
        flags.append(FLAG_ALL_COUNTERIONS)
    if stripped:
        flags.append(FLAG_SALT_STRIPPED)
    uncharger = rdMolStandardize.Uncharger()
    parents = []
    for frag in kept:
        before = Chem.MolToSmiles(frag, isomericSmiles=True)
        after = Chem.MolToSmiles(uncharger.uncharge(frag), isomericSmiles=True)
        if after != before and FLAG_NEUTRALISED not in flags:
            flags.append(FLAG_NEUTRALISED)
        parents.append(after)
    unique = sorted(set(parents))
    if len(unique) < len(parents):
        flags.append(FLAG_REPEATED_COMPONENT)
    if len(unique) > 1:
        flags.append(FLAG_MULTI_COMPONENT)
    return StructureIdentity(submitted=submitted, parent=".".join(unique),
                             stripped=tuple(sorted(stripped)), flags=tuple(flags))


def canonical_structure(smiles: str) -> "tuple[Optional[str], Optional[str]]":
    """Return (identity key, error): the canonical parent structure. Empty → (None, None)."""
    ident, err = structure_identity(smiles)
    return (ident.parent if ident else None), err


def check_identity(
    rows: "list[dict]",
    known_structures: "Optional[dict[str, set[str]]]" = None,
    known_forms: "Optional[dict[str, set[str]]]" = None,
) -> "tuple[list[dict], list[str], list[str]]":
    """Reject rows whose compound_id maps to more than one parent structure.

    ``rows`` carry ``compound_id``, ``smiles``, ``structure_key`` (the parent
    key), ``submitted_structure`` and ``source_row``. ``known_structures`` maps
    compound_id → parent keys already stored for the campaign;
    ``known_forms`` maps compound_id → stored as-submitted canonical forms.

    - If the campaign already holds exactly one parent for the ID, rows with
      a different parent are rejected; matching rows are kept.
    - If the campaign already holds several parents for the ID, or this batch
      alone gives it several (with none stored), the identity is ambiguous
      and every row for that ID in the batch is rejected.
    Rows without SMILES carry no identity claim and are only rejected when
    the ID is ambiguous. Returns (accepted, errors, notes); notes report salt
    forms recognised as one parent and multi-component structures.
    """
    known = known_structures or {}
    forms_known = known_forms or {}
    batch: "dict[str, dict[str, str]]" = {}
    for r in rows:
        if r.get("structure_key"):
            batch.setdefault(r["compound_id"], {}).setdefault(r["structure_key"], r["smiles"])

    accepted: "list[dict]" = []
    errors: "list[str]" = []
    for r in rows:
        cid = r["compound_id"]
        stored = known.get(cid, set())
        in_batch = batch.get(cid, {})
        key = r.get("structure_key")
        prefix = f"Row {r.get('source_row', '?')}: compound_id '{cid}'"
        if len(stored) > 1:
            errors.append(f"{prefix} already maps to several parent structures in this campaign "
                          f"({', '.join(sorted(stored))}); resolve that identity conflict "
                          "before adding data. Row rejected.")
        elif len(stored) == 1:
            if key and key not in stored:
                errors.append(f"{prefix} has SMILES '{r['smiles']}' (parent {key}), but this "
                              f"campaign already records it as {next(iter(stored))}. Row rejected.")
            else:
                accepted.append(r)
        elif len(in_batch) > 1:
            errors.append(f"{prefix} is given conflicting structures in this file "
                          f"({', '.join(sorted(in_batch))}; this row: {r['smiles'] or 'no SMILES'}), "
                          "so its identity is ambiguous. Row rejected.")
        else:
            accepted.append(r)

    notes: "list[str]" = []
    by_cid: "dict[str, list[dict]]" = {}
    for r in accepted:
        if r.get("structure_key"):
            by_cid.setdefault(r["compound_id"], []).append(r)
    for cid in sorted(by_cid):
        rs = by_cid[cid]
        parent = rs[0]["structure_key"]
        forms = {r.get("submitted_structure") or r["smiles"] for r in rs} | forms_known.get(cid, set())
        if len(forms) > 1:
            notes.append(f"compound_id '{cid}': submitted forms {', '.join(sorted(forms))} share the "
                         f"parent structure {parent} (salt/free-base or charge state); "
                         "treated as one compound, as-submitted SMILES kept per row.")
        if any(FLAG_MULTI_COMPONENT in r.get("structure_flags", ()) for r in rs):
            notes.append(f"compound_id '{cid}': structure has several distinct non-counterion "
                         f"components ({parent}); kept as a multi-component parent, not collapsed. "
                         "Confirm whether it is a co-drug, a mixture or an unlisted counterion.")
    return accepted, errors, notes


def find_identity_conflicts(
    rows: "list[dict]",
    known_structures: "Optional[dict[str, set[str]]]" = None,
) -> "tuple[list[dict], list[str]]":
    """check_identity without notes (kept for existing callers)."""
    accepted, errors, _notes = check_identity(rows, known_structures)
    return accepted, errors


# ── Row-level validation ────────────────────────────────────────────────────

@dataclass
class AssayValidationResult:
    rows: "list[dict]" = field(default_factory=list)
    errors: "list[str]" = field(default_factory=list)
    notes: "list[str]" = field(default_factory=list)


def read_assay_csv(csv_path: str) -> "tuple[list[dict], list[str], bool]":
    """Parse a CSV into raw rows. Returns (rows, errors, fatal).

    Each row carries ``source_row`` (its line number). ``fatal`` is True when
    the file cannot be used at all (missing, empty, missing columns).
    """
    rows: "list[dict]" = []
    try:
        with open(csv_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames is None:
                return rows, ["CSV file is empty or has no header row."], True
            headers = {h.strip() for h in reader.fieldnames if h}
            missing = REQUIRED_COLUMNS - headers
            if missing:
                return rows, [f"Missing required columns: {', '.join(sorted(missing))}"], True
            for row_num, raw_row in enumerate(reader, start=2):
                row = {k.strip(): (v.strip() if v else "") for k, v in raw_row.items() if k}
                row["source_row"] = row_num
                rows.append(row)
    except FileNotFoundError:
        return [], [f"File not found: {csv_path}"], True
    except Exception as exc:
        return rows, [f"Unexpected error reading CSV: {exc}"], True
    return rows, [], False


def _clean(value):
    if value is None:
        return ""
    return value.strip() if isinstance(value, str) else value


class AssayCSVValidator:
    """Validate and normalise assay rows (from CSV files or LIMS connectors)."""

    def validate_rows(
        self,
        raw_rows: "Iterable[dict]",
        known_structures: "Optional[dict[str, set[str]]]" = None,
        known_forms: "Optional[dict[str, set[str]]]" = None,
        modality: str = "small_molecule",
    ) -> AssayValidationResult:
        """Validate rows given as dicts with the CSV column names.

        Values may be strings or numbers. ``source_row`` labels error messages
        (a CSV line number or a LIMS record label). ``source_system``,
        ``source_record_id`` and ``provenance`` pass through unchanged.
        ``known_structures`` (compound_id → parent keys already in the
        campaign) extends the identity check beyond this batch.
        """
        result = AssayValidationResult()
        valid: "list[dict]" = []
        for index, raw in enumerate(raw_rows, start=1):
            row = {k: _clean(v) for k, v in raw.items() if k}
            label = row.get("source_row", index)
            row_errors = self._validate_row(row, label)
            ident, structure_error = _entity_identity(str(row.get("smiles", "") or ""), modality)
            if structure_error:
                row_errors.append(f"Row {label}: {structure_error}.")
            if row_errors:
                result.errors.extend(row_errors)
                continue
            normalised = self._normalise_row(row)
            normalised["structure_key"] = ident.parent if ident else None
            normalised["submitted_structure"] = ident.submitted if ident else None
            normalised["parent_smiles"] = ident.parent if ident else ""
            normalised["structure_flags"] = list(ident.flags) if ident else []
            normalised["source_row"] = label
            valid.append(normalised)
        result.rows, identity_errors, result.notes = check_identity(valid, known_structures, known_forms)
        result.errors.extend(identity_errors)
        return result

    def validate_csv(
        self,
        csv_path: str,
        known_structures: "Optional[dict[str, set[str]]]" = None,
        known_forms: "Optional[dict[str, set[str]]]" = None,
    ) -> AssayValidationResult:
        raw_rows, errors, fatal = read_assay_csv(csv_path)
        if fatal:
            return AssayValidationResult(errors=errors)
        result = self.validate_rows(raw_rows, known_structures, known_forms)
        result.errors = errors + result.errors
        return result

    def validate(
        self,
        csv_path: str,
        known_structures: "Optional[dict[str, set[str]]]" = None,
    ) -> "tuple[list[dict], list[str]]":
        """Parse and validate a CSV file → (valid_rows, error_messages).

        valid_rows are normalised dicts including ``value_uM`` (the value in
        the endpoint's ``unit_normalized``) and ``censored``.
        """
        result = self.validate_csv(csv_path, known_structures)
        return result.rows, result.errors

    def _validate_row(self, row: dict, row_num) -> "list[str]":
        errs: "list[str]" = []

        compound_id = str(row.get("compound_id", "") or "")
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
            if isinstance(raw_value, bool):
                raise TypeError("boolean is not a measurement")
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

        assay_date = str(row.get("assay_date", "") or "")
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
        elif operator in CENSORING_OPERATORS and rule is not None and rule.allowed_values is not None:
            errs.append(
                f"Row {row_num}: operator '{operator}' is not meaningful for {assay_type}, "
                "a categorical flag; give the observed flag value with '=' or no operator."
            )

        return errs

    def _normalise_row(self, row: dict) -> dict:
        unit = row["unit"]
        rule = ENDPOINT_RULES[row["assay_type"]]
        raw_value = float(row["value"])
        operator = row.get("operator", "") or ""

        normalised = {
            "compound_id": str(row["compound_id"]),
            "smiles": str(row.get("smiles", "") or ""),
            "assay_type": row["assay_type"],
            "value": raw_value,
            "value_uM": raw_value * rule.units[unit],
            "unit": unit,
            "unit_normalized": rule.normalized_unit,
            "operator": operator,
            "censored": operator in CENSORING_OPERATORS,
            "operator_note": str(row.get("operator_note", "") or ""),
            "assay_date": row["assay_date"],
        }
        for key in ("source_system", "source_record_id", "provenance"):
            if row.get(key) not in (None, ""):
                normalised[key] = row[key]
        return normalised
