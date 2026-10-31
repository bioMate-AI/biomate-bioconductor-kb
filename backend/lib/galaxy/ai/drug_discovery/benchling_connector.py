"""
Benchling assay results → BioMate campaign assay rows.

The HTTP client (auth, tenant URL, retries, pagination, molecule lookup) is
integrations.benchling_connector.BenchlingConnector; this module adds what the
DMTA loop needs on top of it:

  - BenchlingSchemaMapping: an explicit per-schema field mapping. Nothing is
    guessed: the compound link field and its entity type, the value field,
    the assay type, the unit, the qualifier (operator) field, replicate /
    batch / run fields and the review policy are all configured.
  - BenchlingAssayPoller: lists reviewed, non-archived results of one schema
    modified since a watermark, resolves compound links in bulk to the
    registry ID (the compound identity) and canonicalised SMILES, and maps each
    result to the row contract of AssayIngestionService.ingest_rows (shared with
    CSV upload), keeping Benchling provenance on every row.
  - load_sync_state / save_sync_state: per campaign + schema mapping and
    modifiedAt watermark, stored in the campaign DB.

There is no mock mode: without a tenant URL and credentials the client raises.
Nothing here has been verified against a live Benchling tenant; tests use
recorded Benchling-shaped payloads.
"""
from __future__ import annotations

import json
import logging
import sqlite3
from dataclasses import asdict, dataclass, field, fields as dc_fields
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from integrations.benchling_connector import (  # noqa: F401 - re-exported for callers
    BenchlingAPIError, BenchlingConfigError, BenchlingConnector, normalize_tenant_url,
)

from .assay_schema import SUPPORTED_ASSAY_TYPES, VALID_OPERATORS

log = logging.getLogger(__name__)

SOURCE_SYSTEM = "benchling"
ENTITY_MOLECULE = "molecule"
ENTITY_CUSTOM = "custom_entity"
REVIEWED_ONLY = "reviewed_only"
INCLUDE_UNREVIEWED = "include_unreviewed"
_META_DATE_SOURCES = {"$createdAt": "createdAt", "$modifiedAt": "modifiedAt"}

# Skip reasons that can resolve later without the result itself being edited
# (a review is accepted, a molecule is registered); the watermark is held at
# the oldest such result so it is read again on the next poll.
RETRYABLE_SKIPS = {"not_reviewed", "unregistered_compound"}


class BenchlingMappingError(ValueError):
    """The schema mapping configuration is incomplete or inconsistent."""


@dataclass
class BenchlingSchemaMapping:
    """How one Benchling assay result schema maps to BioMate assay rows."""
    schema_id: str
    compound_field: str
    compound_entity_type: str                     # "molecule" | "custom_entity"
    value_field: str
    assay_type: Optional[str] = None              # fixed BioMate assay_type, or ...
    assay_type_field: Optional[str] = None        # ... a dropdown/text field holding it
    assay_type_values: Dict[str, str] = field(default_factory=dict)
    unit: Optional[str] = None                    # fixed unit, or ...
    unit_field: Optional[str] = None              # ... a dropdown/text field holding it
    unit_values: Dict[str, str] = field(default_factory=dict)
    operator_field: Optional[str] = None          # qualifier: '<', '>', '=', '~'
    operator_values: Dict[str, str] = field(default_factory=dict)
    assay_date_field: str = "$createdAt"          # a field name, "$createdAt" or "$modifiedAt"
    custom_entity_structure_field: Optional[str] = None
    replicate_field: Optional[str] = None
    batch_field: Optional[str] = None
    assay_run_field: Optional[str] = None
    review_policy: str = REVIEWED_ONLY
    exclude_invalid: bool = True                  # skip validationStatus == INVALID
    require_registered: bool = True               # compound identity = registry ID

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BenchlingSchemaMapping":
        if not isinstance(data, dict):
            raise BenchlingMappingError("mapping must be an object")
        known = {f.name for f in dc_fields(cls)}
        unknown = sorted(set(data) - known)
        if unknown:
            raise BenchlingMappingError(f"unknown mapping keys: {', '.join(unknown)}")
        try:
            mapping = cls(**data)
        except TypeError as exc:
            raise BenchlingMappingError(f"incomplete mapping: {exc}") from None
        mapping.validate()
        return mapping

    def validate(self) -> None:
        problems: List[str] = []
        for name in ("schema_id", "compound_field", "value_field"):
            if not getattr(self, name):
                problems.append(f"{name} is required")
        if self.compound_entity_type not in (ENTITY_MOLECULE, ENTITY_CUSTOM):
            problems.append("compound_entity_type must be 'molecule' or 'custom_entity'")
        if self.compound_entity_type == ENTITY_CUSTOM and not self.custom_entity_structure_field:
            problems.append("custom_entity_structure_field is required for custom_entity compounds")
        if bool(self.assay_type) == bool(self.assay_type_field):
            problems.append("give exactly one of assay_type or assay_type_field")
        if self.assay_type and self.assay_type not in SUPPORTED_ASSAY_TYPES:
            problems.append(f"assay_type '{self.assay_type}' is not supported "
                            f"({', '.join(sorted(SUPPORTED_ASSAY_TYPES))})")
        bad_types = sorted(v for v in self.assay_type_values.values() if v not in SUPPORTED_ASSAY_TYPES)
        if bad_types:
            problems.append(f"assay_type_values map to unsupported types: {', '.join(bad_types)}")
        if (self.unit is None) == (self.unit_field is None):
            problems.append("give exactly one of unit or unit_field")
        bad_ops = sorted(v for v in self.operator_values.values() if v not in VALID_OPERATORS)
        if bad_ops:
            problems.append(f"operator_values map to invalid operators: {', '.join(bad_ops)}")
        if self.review_policy not in (REVIEWED_ONLY, INCLUDE_UNREVIEWED):
            problems.append(f"review_policy must be '{REVIEWED_ONLY}' or '{INCLUDE_UNREVIEWED}'")
        if not self.assay_date_field:
            problems.append("assay_date_field is required (a field name, $createdAt or $modifiedAt)")
        elif self.assay_date_field.startswith("$") and self.assay_date_field not in _META_DATE_SOURCES:
            problems.append("assay_date_field may only use $createdAt or $modifiedAt as metadata sources")
        if problems:
            raise BenchlingMappingError("; ".join(problems))

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class BenchlingPollResult:
    schema_id: str
    fetched: int
    rows: List[Dict[str, Any]]
    skipped: List[Dict[str, Any]]
    archived_result_ids: List[str]
    previous_watermark: Optional[str]
    next_watermark: Optional[str]


# ── Field access ────────────────────────────────────────────────────────────

def _field(result: Dict[str, Any], name: Optional[str]) -> Optional[Dict[str, Any]]:
    if not name:
        return None
    value = (result.get("fields") or {}).get(name)
    return value if isinstance(value, dict) else None


def _field_text(f: Optional[Dict[str, Any]]) -> Any:
    """Value of a field as BioMate reads it: dropdowns by option name, others by value."""
    if f is None:
        return None
    if f.get("type") == "dropdown":
        return f.get("textValue") or f.get("displayValue")
    value = f.get("value")
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return f.get("textValue") or f.get("displayValue")


def _assay_date(result: Dict[str, Any], mapping: BenchlingSchemaMapping) -> str:
    meta = _META_DATE_SOURCES.get(mapping.assay_date_field)
    raw = result.get(meta) if meta else _field_text(_field(result, mapping.assay_date_field))
    raw = "" if raw is None else str(raw)
    # date fields are YYYY-MM-DD; datetimes are RFC 3339 → keep the date part.
    return raw[:10] if len(raw) >= 10 and raw[4:5] == "-" and raw[7:8] == "-" else raw


class BenchlingAssayPoller:
    """Fetch, resolve and map one schema's assay results (see module docstring)."""

    def __init__(self, client: BenchlingConnector, mapping: BenchlingSchemaMapping):
        mapping.validate()
        self.client = client
        self.mapping = mapping

    def poll(self, modified_after: Optional[str] = None) -> BenchlingPollResult:
        m = self.mapping
        results = self.client.list_assay_results(m.schema_id, modified_after=modified_after,
                                                 archive_reason="NOT_ARCHIVED")
        archived: List[Dict[str, Any]] = []
        if modified_after:
            # Results archived since the last poll are withdrawn from the campaign.
            archived = self.client.list_assay_results(m.schema_id, modified_after=modified_after,
                                                      archive_reason="ANY_ARCHIVED")

        skipped: List[Dict[str, Any]] = []
        candidates: List[Dict[str, Any]] = []
        for r in results:
            reason = self._admission_problem(r)
            if reason:
                skipped.append(self._skip(r, reason))
            else:
                candidates.append(r)

        links: Dict[str, str] = {}
        for r in list(candidates):
            link = (_field(r, m.compound_field) or {}).get("value")
            if isinstance(link, list):
                skipped.append(self._skip(r, "multi_compound_link", values=link))
                candidates.remove(r)
            elif not link:
                skipped.append(self._skip(r, "missing_compound_link"))
                candidates.remove(r)
            else:
                links[r["id"]] = link

        compounds = self._resolve_compounds(set(links.values()))
        rows: List[Dict[str, Any]] = []
        for r in candidates:
            compound = compounds.get(links[r["id"]])
            if compound is None:
                skipped.append(self._skip(r, "compound_not_found", entity_id=links[r["id"]]))
                continue
            if not compound["registry_id"] and m.require_registered:
                skipped.append(self._skip(r, "unregistered_compound", entity_id=links[r["id"]]))
                continue
            rows.append(self._to_row(r, compound))

        return BenchlingPollResult(
            schema_id=m.schema_id,
            fetched=len(results),
            rows=rows,
            skipped=skipped,
            archived_result_ids=[a["id"] for a in archived if a.get("id")],
            previous_watermark=modified_after,
            next_watermark=self._next_watermark(modified_after, results + archived, skipped),
        )

    # ── internals ──

    def _admission_problem(self, r: Dict[str, Any]) -> Optional[str]:
        if r.get("archiveRecord"):
            return "archived"
        if self.mapping.review_policy == REVIEWED_ONLY and r.get("isReviewed") is not True:
            return "not_reviewed"
        if self.mapping.exclude_invalid and (r.get("validationStatus") or "").upper() == "INVALID":
            return "validation_invalid"
        return None

    @staticmethod
    def _skip(r: Dict[str, Any], reason: str, **extra: Any) -> Dict[str, Any]:
        return {"benchling_result_id": r.get("id"), "reason": reason,
                "modified_at": r.get("modifiedAt"), **extra}

    def _resolve_compounds(self, entity_ids: set) -> Dict[str, Dict[str, Any]]:
        """entity id → {registry_id, smiles, original_smiles, entity_id, name}."""
        m = self.mapping
        if not entity_ids:
            return {}
        if m.compound_entity_type == ENTITY_MOLECULE:
            return {mid: {"entity_id": mid, "registry_id": mol.get("entityRegistryId"),
                          "smiles": mol.get("canonicalizedSmiles") or "",
                          "original_smiles": mol.get("originalSmiles"), "name": mol.get("name")}
                    for mid, mol in self.client.get_molecules(entity_ids).items()}
        entities = self.client.get_custom_entities(entity_ids)
        structure_links: Dict[str, str] = {}
        resolved: Dict[str, Dict[str, Any]] = {}
        for eid, ent in entities.items():
            sf = _field(ent, m.custom_entity_structure_field) or {}
            value = sf.get("value")
            entry = {"entity_id": eid, "registry_id": ent.get("entityRegistryId"),
                     "smiles": "", "original_smiles": None, "name": ent.get("name")}
            if sf.get("type") == "molecule_link" and isinstance(value, str) and value:
                structure_links[eid] = value
            elif isinstance(value, str):
                entry["smiles"] = value.strip()
            resolved[eid] = entry
        if structure_links:
            molecules = self.client.get_molecules(set(structure_links.values()))
            for eid, mid in structure_links.items():
                mol = molecules.get(mid) or {}
                resolved[eid]["smiles"] = mol.get("canonicalizedSmiles") or ""
                resolved[eid]["original_smiles"] = mol.get("originalSmiles")
                resolved[eid]["structure_molecule_id"] = mid
        return resolved

    def _to_row(self, r: Dict[str, Any], compound: Dict[str, Any]) -> Dict[str, Any]:
        m = self.mapping
        value = _field_text(_field(r, m.value_field))
        assay_type = m.assay_type
        if m.assay_type_field:
            raw = _field_text(_field(r, m.assay_type_field))
            assay_type = m.assay_type_values.get(raw, raw) if raw is not None else ""
        unit = m.unit
        if m.unit_field:
            raw = _field_text(_field(r, m.unit_field))
            unit = m.unit_values.get(raw, raw) if raw is not None else ""
        operator = "="
        if m.operator_field:
            raw = _field_text(_field(r, m.operator_field))
            if raw not in (None, ""):
                operator = m.operator_values.get(str(raw).strip(), str(raw).strip())
        run = _field(r, m.assay_run_field)
        provenance = {
            "benchling_result_id": r.get("id"),
            "schema_id": (r.get("schema") or {}).get("id") or m.schema_id,
            "assay_run_id": run.get("value") if run else None,
            "entry_id": r.get("entryId"),
            "project_id": r.get("projectId"),
            "creator_id": (r.get("creator") or {}).get("id"),
            "created_at": r.get("createdAt"),
            "modified_at": r.get("modifiedAt"),
            "is_reviewed": r.get("isReviewed"),
            "validation_status": r.get("validationStatus"),
            "compound_entity_type": m.compound_entity_type,
            "compound_entity_id": compound["entity_id"],
            "entity_registry_id": compound["registry_id"],
            "original_smiles": compound.get("original_smiles"),
            "replicate": _field_text(_field(r, m.replicate_field)),
            "batch": _field_text(_field(r, m.batch_field)),
            "tenant_host": self.client.tenant_host,
        }
        return {
            "compound_id": compound["registry_id"] or compound["entity_id"],
            "smiles": compound["smiles"],
            "assay_type": assay_type or "",
            "value": "" if value is None else value,
            "unit": "" if unit is None else unit,
            "operator": operator,
            "assay_date": _assay_date(r, m),
            "source_system": SOURCE_SYSTEM,
            "source_record_id": r.get("id"),
            "source_row": f"benchling:{r.get('id')}",
            "provenance": {k: v for k, v in provenance.items() if v is not None},
        }

    @staticmethod
    def _next_watermark(previous: Optional[str], seen: List[Dict[str, Any]],
                        skipped: List[Dict[str, Any]]) -> Optional[str]:
        held = [s["modified_at"] for s in skipped if s["reason"] in RETRYABLE_SKIPS and s.get("modified_at")]
        if held:
            return min(held)
        stamps = [r["modifiedAt"] for r in seen if r.get("modifiedAt")]
        return max(stamps) if stamps else previous


# ── Sync state (campaign DB) ────────────────────────────────────────────────

def _ensure_state_table(conn: sqlite3.Connection) -> None:
    conn.execute("""
        CREATE TABLE IF NOT EXISTS benchling_sync_state (
            campaign_id     TEXT NOT NULL,
            schema_id       TEXT NOT NULL,
            tenant_host     TEXT NOT NULL,
            mapping_json    TEXT NOT NULL,
            watermark       TEXT,
            last_polled_at  TEXT NOT NULL,
            PRIMARY KEY (campaign_id, schema_id)
        )
    """)


def load_sync_state(db_path: str, campaign_id: str, schema_id: str) -> Optional[Dict[str, Any]]:
    with sqlite3.connect(db_path) as conn:
        _ensure_state_table(conn)
        row = conn.execute("""
            SELECT tenant_host, mapping_json, watermark, last_polled_at FROM benchling_sync_state
            WHERE campaign_id = ? AND schema_id = ?
        """, (campaign_id, schema_id)).fetchone()
    if row is None:
        return None
    return {"tenant_host": row[0], "mapping": json.loads(row[1]), "watermark": row[2],
            "last_polled_at": row[3]}


def save_sync_state(db_path: str, campaign_id: str, mapping: BenchlingSchemaMapping,
                    tenant_host: str, watermark: Optional[str]) -> None:
    with sqlite3.connect(db_path) as conn:
        _ensure_state_table(conn)
        conn.execute("""
            INSERT OR REPLACE INTO benchling_sync_state
            (campaign_id, schema_id, tenant_host, mapping_json, watermark, last_polled_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (campaign_id, mapping.schema_id, tenant_host, json.dumps(mapping.to_dict(), sort_keys=True),
              watermark, datetime.now(timezone.utc).isoformat()))
        conn.commit()
