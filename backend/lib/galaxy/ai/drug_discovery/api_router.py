"""
BioMate Drug Discovery API Router (FastAPI)

Endpoints:
  POST /api/drug-discovery/{campaign_id}/ingest-assay
       Upload a CRO/wet-lab assay CSV; updates compound ranking.

  GET  /api/drug-discovery/{campaign_id}/compounds
       Return current compound ranking for a campaign.

  GET  /api/drug-discovery/{campaign_id}/export/cro-order
       Export current proposal as WuXi / Pharmaron / Enamine CSV.

  POST /api/drug-discovery/{campaign_id}/propose
       Run BayesianOptimizer.propose_next_round() against a virtual library.
       Body: {virtual_library_smiles: [...], n_propose: 10, diversity_weight: 0.2}

  POST /api/drug-discovery/{campaign_id}/lims/poll
       Pull reviewed Benchling assay results (explicit schema mapping) and ingest them.

  POST /api/drug-discovery/{campaign_id}/models/register
       Register a custom predictive model (Python function, Docker, or REST).

  GET  /api/drug-discovery/{campaign_id}/models
       List registered models and run history.

  POST /api/drug-discovery/{campaign_id}/models/{model_name}/run
       Run a registered model against the current compound set.

  GET  /api/drug-discovery/availability
       Batch commercial availability check (PubChem lookup).
"""

import logging
import os
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from pydantic import BaseModel

try:
    from ..compliance.audit_middleware import audit_regulated_action as _audit_fn
except ImportError:
    async def _audit_fn(*args, **kwargs):  # type: ignore[misc]
        pass  # no-op when compliance module not installed

log = logging.getLogger(__name__)

router = APIRouter(prefix="/api/drug-discovery", tags=["drug_discovery"])

# In-memory cache for last IND assembly per campaign (path → content).
# Allows the download endpoint to serve files without requiring the temp dir to persist.
_ind_cache: dict[str, dict] = {}  # campaign_id → {markdown_path, docx_path, markdown_content}


def _store_ind_document_hash(
    db_path: str,
    campaign_id: str,
    doc_hash: str,
    generated_at: str,
    markdown_path: Optional[str] = None,
) -> None:
    """Store the SHA-256 hash of a newly assembled IND document in the campaign DB."""
    import sqlite3
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS ind_document_hashes (
                campaign_id   TEXT NOT NULL,
                doc_hash      TEXT NOT NULL,
                generated_at  TEXT NOT NULL,
                frozen_at     TEXT,
                frozen_by     TEXT,
                sig_id        TEXT,
                is_frozen     INTEGER DEFAULT 0,
                markdown_path TEXT,
                PRIMARY KEY (campaign_id, doc_hash)
            )
        """)
        # Migration-safe: add markdown_path column if it doesn't exist yet
        try:
            conn.execute("ALTER TABLE ind_document_hashes ADD COLUMN markdown_path TEXT")
        except Exception:
            pass
        conn.execute("""
            INSERT OR REPLACE INTO ind_document_hashes
                (campaign_id, doc_hash, generated_at, is_frozen, markdown_path)
            VALUES (?, ?, ?, 0, ?)
        """, (campaign_id, doc_hash, generated_at, markdown_path))
        conn.commit()


def _get_latest_ind_hash(db_path: str, campaign_id: str) -> Optional[dict]:
    """Return the most recent ind_document_hashes row for a campaign, or None."""
    import sqlite3
    try:
        with sqlite3.connect(db_path) as conn:
            conn.row_factory = sqlite3.Row
            cur = conn.execute("""
                SELECT doc_hash, generated_at, frozen_at, frozen_by, sig_id, is_frozen,
                       markdown_path, reviewer_title, reviewer_credentials, review_scope
                FROM ind_document_hashes
                WHERE campaign_id = ?
                ORDER BY generated_at DESC
                LIMIT 1
            """, (campaign_id,))
            row = cur.fetchone()
            return dict(row) if row else None
    except Exception:
        return None


def _freeze_ind_document(
    db_path: str,
    campaign_id: str,
    sig_id: str,
    user_id: str,
    reviewer_title: Optional[str] = None,
    reviewer_credentials: Optional[str] = None,
    review_scope: Optional[str] = None,
) -> Optional[str]:
    """
    Mark the most recent IND document hash as frozen after eSig.

    If reviewer credentials are provided they are appended to the stored
    markdown as a regulatory disclosure block (FDA/EMA AI Guidance Jan 2026).
    Returns the frozen hash.
    """
    import sqlite3, json
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat()
    try:
        with sqlite3.connect(db_path) as conn:
            # Find latest unfrozen record (hash + markdown path)
            cur = conn.execute("""
                SELECT doc_hash, markdown_path FROM ind_document_hashes
                WHERE campaign_id = ? AND is_frozen = 0
                ORDER BY generated_at DESC LIMIT 1
            """, (campaign_id,))
            row = cur.fetchone()
            if not row:
                return None
            doc_hash, markdown_path = row[0], row[1] if len(row) > 1 else None

            # Add reviewer disclosure block to the markdown file
            if markdown_path:
                _append_reviewer_disclosure(
                    markdown_path, sig_id, user_id, now,
                    reviewer_title, reviewer_credentials, review_scope,
                )

            # Ensure reviewer columns exist (migration-safe)
            try:
                conn.execute("ALTER TABLE ind_document_hashes ADD COLUMN reviewer_title TEXT")
            except Exception:
                pass
            try:
                conn.execute("ALTER TABLE ind_document_hashes ADD COLUMN reviewer_credentials TEXT")
            except Exception:
                pass
            try:
                conn.execute("ALTER TABLE ind_document_hashes ADD COLUMN review_scope TEXT")
            except Exception:
                pass

            conn.execute("""
                UPDATE ind_document_hashes
                SET frozen_at = ?, frozen_by = ?, sig_id = ?, is_frozen = 1,
                    reviewer_title = ?, reviewer_credentials = ?, review_scope = ?
                WHERE campaign_id = ? AND doc_hash = ?
            """, (now, user_id, sig_id,
                  reviewer_title, reviewer_credentials, review_scope,
                  campaign_id, doc_hash))
            conn.commit()
            return doc_hash
    except Exception as exc:
        log.warning("_freeze_ind_document failed for campaign %s: %s", campaign_id, exc)
        return None


def _append_reviewer_disclosure(
    markdown_path: str,
    sig_id: str,
    user_id: str,
    signed_at: str,
    reviewer_title: Optional[str],
    reviewer_credentials: Optional[str],
    review_scope: Optional[str],
) -> None:
    """Append a 21 CFR Part 11 reviewer disclosure block to the frozen markdown."""
    try:
        from pathlib import Path
        p = Path(markdown_path)
        if not p.exists():
            return
        lines = ["\n\n---\n"]
        lines.append("## Electronic Signature Record\n\n")
        lines.append(f"**Signature ID:** `{sig_id}`  \n")
        lines.append(f"**Signed by:** {user_id}  \n")
        lines.append(f"**Signed at:** {signed_at} UTC  \n")
        if reviewer_title:
            lines.append(f"**Reviewer title:** {reviewer_title}  \n")
        if reviewer_credentials:
            lines.append(f"**Reviewer credentials:** {reviewer_credentials}  \n")
        if review_scope:
            lines.append(f"**Review scope:** {review_scope}  \n")
        lines.append(
            "\n*This document has been electronically signed and is frozen. "
            "Any subsequent modification invalidates this signature record. "
            "Signed per 21 CFR Part 11 §11.50 and FDA/EMA Joint Guidance on Good "
            "AI Practice in Drug Development (January 2026).*\n"
        )
        with open(p, "a", encoding="utf-8") as fh:
            fh.writelines(lines)
    except Exception as exc:
        log.warning("_append_reviewer_disclosure failed for %s: %s", markdown_path, exc)


def _store_pk_summary(db_path: str, campaign_id: str, pk_data: dict) -> None:
    """Persist pk_summary.json content to campaign SQLite DB for IND assembly."""
    import sqlite3, json
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS campaign_pk_predictions (
                campaign_id TEXT NOT NULL,
                stored_at   TEXT NOT NULL,
                pk_json     TEXT NOT NULL,
                PRIMARY KEY (campaign_id)
            )
        """)
        conn.execute("""
            INSERT OR REPLACE INTO campaign_pk_predictions (campaign_id, stored_at, pk_json)
            VALUES (?, datetime('now'), ?)
        """, (campaign_id, json.dumps(pk_data)))
        conn.commit()


def _load_pk_summary(db_path: str, campaign_id: str) -> Optional[dict]:
    """Read stored pk_summary for a campaign.  Returns None if not yet stored."""
    import sqlite3, json
    try:
        with sqlite3.connect(db_path) as conn:
            cur = conn.execute(
                "SELECT pk_json FROM campaign_pk_predictions WHERE campaign_id = ?",
                (campaign_id,)
            )
            row = cur.fetchone()
            return json.loads(row[0]) if row else None
    except Exception:
        return None

# Per-campaign SQLite databases live in this directory.
_CAMPAIGN_DB_DIR = os.environ.get(
    "BIOMATE_CAMPAIGN_DB_DIR",
    str(Path(__file__).parent.parent.parent.parent.parent / "database" / "campaigns"),
)

# Global registry of all campaigns (user_id → campaign metadata)
_CAMPAIGN_REGISTRY_DB = str(
    Path(__file__).parent.parent.parent.parent.parent / "database" / "campaigns_registry.db"
)


def _registry_conn():
    """Return a connection to the global campaign registry SQLite."""
    import sqlite3
    Path(_CAMPAIGN_REGISTRY_DB).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(_CAMPAIGN_REGISTRY_DB)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS campaigns (
            campaign_id   TEXT PRIMARY KEY,
            user_id       TEXT NOT NULL DEFAULT '',
            molecule_name TEXT NOT NULL DEFAULT '',
            target        TEXT NOT NULL DEFAULT '',
            indication    TEXT NOT NULL DEFAULT '',
            sponsor       TEXT NOT NULL DEFAULT '',
            objective     TEXT NOT NULL DEFAULT 'balance',
            created_at    TEXT NOT NULL
        )
    """)
    # Migration: modality selects the DMTA engine (small_molecule | peptide | biologic).
    cols = {r[1] for r in conn.execute("PRAGMA table_info(campaigns)")}
    if "modality" not in cols:
        conn.execute("ALTER TABLE campaigns ADD COLUMN modality TEXT NOT NULL DEFAULT 'small_molecule'")
    conn.commit()
    return conn


def _campaign_modality(campaign_id: str) -> str:
    """The campaign's DMTA modality (default small_molecule if unknown)."""
    try:
        conn = _registry_conn()
        row = conn.execute("SELECT modality FROM campaigns WHERE campaign_id = ?",
                           (campaign_id,)).fetchone()
        return (row["modality"] if row and row["modality"] else "small_molecule")
    except Exception:
        return "small_molecule"


def _campaign_service(campaign_id: str):
    """AssayIngestionService bound to the campaign's modality, so sequence
    (peptide/biologic) entities validate and rank without SMILES parsing."""
    from .assay_ingestion import AssayIngestionService
    return AssayIngestionService(_campaign_db(campaign_id), modality=_campaign_modality(campaign_id))


def _campaign_db(campaign_id: str) -> str:
    """Return the SQLite path for a campaign, creating the parent dir if needed."""
    Path(_CAMPAIGN_DB_DIR).mkdir(parents=True, exist_ok=True)
    # Restrict to safe characters to prevent path traversal.
    safe_id = "".join(c for c in campaign_id if c.isalnum() or c in "-_")
    if not safe_id:
        raise HTTPException(status_code=400, detail="Invalid campaign_id")
    return str(Path(_CAMPAIGN_DB_DIR) / f"{safe_id}.db")


# ---------------------------------------------------------------------------
# Track C — Assay data ingestion
# ---------------------------------------------------------------------------

class IngestAssayResponse(BaseModel):
    campaign_id: str
    ingested: int
    errors: list[str]
    warnings: list[str] = []
    updated_ranks: list[dict]
    newly_failed: list[str]
    newly_passed: list[str]


class StudyReportIngestResponse(BaseModel):
    campaign_id: str
    filename: str
    study_type: str
    species: Optional[str]
    route: Optional[str]
    noael: Optional[float]
    noael_unit: Optional[str]
    ld50: Optional[float] = None
    ld50_unit: Optional[str] = None
    micronucleus_result: Optional[str] = None
    duration: Optional[str]
    key_findings: str
    ames_result: Optional[bool]
    herg_ic50_um: Optional[float]
    glp: Optional[bool]
    study_id: Optional[str]
    sections_to_regenerate: list[str]
    warning: Optional[str] = None


@router.post("/{campaign_id}/ingest-study-report", response_model=StudyReportIngestResponse)
async def ingest_study_report(
    campaign_id: str,
    file: UploadFile = File(..., description="GLP study report PDF"),
    _audit: None = Depends(_audit_fn),
):
    """
    Upload a GLP nonclinical study report PDF.

    Extracts structured study parameters (NOAEL, species, route, study type,
    key findings) from the PDF conclusion section using PyMuPDF + regex.
    Stores extracted data in the campaign DB wetlab_data field.
    Returns the extracted parameters and which §2.6.3.x sections will regenerate.

    Supported study types: Ames, micronucleus, chromosomal aberration, hERG,
    single-dose, 28-day/90-day/26-week repeat-dose, carcinogenicity, reproductive tox.

    After upload, call POST /{campaign_id}/ind-assembly to regenerate the document
    with the new wet-lab data replacing computational placeholders.
    """
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are accepted")

    contents = await file.read()
    if len(contents) < 1024:
        raise HTTPException(status_code=400, detail="File too small — likely not a valid PDF")

    try:
        from .study_report_ingester import extract_from_pdf, merge_study_into_wetlab
    except ImportError as e:
        raise HTTPException(status_code=503, detail=f"Study report ingester unavailable: {e}")

    # Extract structured fields from the PDF
    extracted = extract_from_pdf(contents)
    if "error" in extracted:
        raise HTTPException(status_code=422, detail=extracted["error"])

    # Merge into campaign wetlab_data
    db_path = _campaign_db(campaign_id)
    try:
        import sqlite3, json as _json
        with sqlite3.connect(db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS campaign_wetlab (
                    campaign_id TEXT PRIMARY KEY,
                    wetlab_data TEXT NOT NULL DEFAULT '{}'
                )
            """)
            row = conn.execute(
                "SELECT wetlab_data FROM campaign_wetlab WHERE campaign_id = ?",
                (campaign_id,)
            ).fetchone()
            existing = _json.loads(row[0]) if row else {}
            merged = merge_study_into_wetlab(existing, extracted)
            conn.execute(
                "INSERT OR REPLACE INTO campaign_wetlab (campaign_id, wetlab_data) VALUES (?, ?)",
                (campaign_id, _json.dumps(merged))
            )
        log.info("[ingest-study-report] %s: stored %s study data", campaign_id, extracted.get("study_type"))
    except Exception as e:
        log.warning("[ingest-study-report] DB write failed: %s", e)

    # Determine which IND sections will regenerate
    st = extracted.get("study_type", "")
    section_map = {
        "ames": ["2.6.3.3"], "micronucleus": ["2.6.3.3"],
        "chromosomal_aberration": ["2.6.3.3"], "herg": ["2.6.3"],
        "single_dose": ["2.6.3.1"], "repeat_dose_28d": ["2.6.3.2"],
        "repeat_dose_90d": ["2.6.3.2"], "repeat_dose_26w": ["2.6.3.2"],
        "carcinogenicity": ["2.6.3.4"], "reproductive": ["2.6.3.5"],
        "pharmacokinetics": ["2.6.2"],
    }
    sections_to_regen = section_map.get(st, ["2.6.3"])

    warning = None
    if not extracted.get("noael") and st not in ("ames", "micronucleus", "chromosomal_aberration", "herg"):
        warning = "NOAEL could not be extracted automatically. Please verify the study conclusion section."

    return StudyReportIngestResponse(
        campaign_id=campaign_id,
        filename=file.filename,
        study_type=extracted.get("study_type", "unknown"),
        species=extracted.get("species"),
        route=extracted.get("route"),
        noael=extracted.get("noael"),
        noael_unit=extracted.get("noael_unit"),
        ld50=extracted.get("ld50"),
        ld50_unit=extracted.get("ld50_unit"),
        micronucleus_result=extracted.get("micronucleus_result"),
        duration=extracted.get("duration"),
        key_findings=extracted.get("key_findings", "")[:400],
        ames_result=extracted.get("ames_result"),
        herg_ic50_um=extracted.get("herg_ic50_um"),
        glp=extracted.get("glp", False),
        study_id=extracted.get("study_id"),
        sections_to_regenerate=sections_to_regen,
        warning=warning,
    )


@router.post("/{campaign_id}/ingest-assay", response_model=IngestAssayResponse)
async def ingest_assay(
    campaign_id: str,
    file: UploadFile = File(..., description="Assay CSV file"),
    _audit: None = Depends(_audit_fn),
):
    """
    Upload a CRO or wet-lab assay results CSV.

    Required CSV columns: compound_id, assay_type, value, unit, assay_date
    Optional columns: smiles, operator, operator_note

    Supported assay_type values: IC50, Ki, Kd, EC50, hERG, DILI, Ames,
    ClinTox, solubility, permeability, cell_viability, selectivity_ratio, custom

    Returns updated compound ranking after integrating the new measurements.
    """
    try:
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=f"Assay ingestion module unavailable: {exc}")

    contents = await file.read()
    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        svc = _campaign_service(campaign_id)
        result = svc.ingest(campaign_id, tmp_path)
    except Exception as exc:
        log.exception("assay ingestion failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=str(exc))
    finally:
        os.unlink(tmp_path)

    return IngestAssayResponse(
        campaign_id=campaign_id,
        ingested=result.get("ingested", 0),
        errors=result.get("errors", []),
        warnings=result.get("warnings", []),
        updated_ranks=result.get("updated_ranks", []),
        newly_failed=result.get("newly_failed", []),
        newly_passed=result.get("newly_passed", []),
    )


@router.get("/{campaign_id}/compounds")
async def get_compounds(campaign_id: str, limit: int = Query(50, ge=1, le=500)):
    """Return the current compound ranking for a campaign."""
    try:
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        svc = _campaign_service(campaign_id)
        ranks = svc.get_ranked_compounds(campaign_id)[:limit]
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {"campaign_id": campaign_id, "compounds": ranks, "count": len(ranks)}


# ---------------------------------------------------------------------------
# Track E — CRO compound order export
# ---------------------------------------------------------------------------

@router.get("/{campaign_id}/export/cro-order")
async def export_cro_order(
    campaign_id: str,
    fmt: str = Query("generic", regex="^(wuxi|pharmaron|enamine|generic)$"),
    _audit: None = Depends(_audit_fn),
):
    """
    Export the current compound proposal as a CRO-ready CSV.

    fmt: wuxi | pharmaron | enamine | generic (default)

    Returns the CSV content as plain text.
    """
    try:
        from .cro_order_export import CROOrderExporter
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        svc = _campaign_service(campaign_id)
        ranks = svc.get_ranked_compounds(campaign_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    if not ranks:
        raise HTTPException(
            status_code=404,
            detail=f"No compounds found for campaign '{campaign_id}'. "
                   "Upload assay data first via POST /{campaign_id}/ingest-assay.",
        )

    with tempfile.TemporaryDirectory() as tmp_dir:
        try:
            from .cro_order_export import CompoundOrderEntry

            exporter = CROOrderExporter(campaign_id, tmp_dir)
            for i, r in enumerate(ranks, 1):
                exporter.add_compound(CompoundOrderEntry(
                    compound_id=r.get("compound_id", f"CPND-{i:03d}"),
                    smiles=r.get("smiles", ""),
                    priority_rank=i,
                    requested_quantity_mg=r.get("quantity_mg", 10.0),
                    scientific_rationale=r.get("rationale", "BioMate campaign compound"),
                ))
            exports = exporter.export_all()
        except Exception as exc:
            log.exception("CRO export failed for campaign %s", campaign_id)
            raise HTTPException(status_code=500, detail=str(exc))

        key_map = {
            "wuxi": "wuxi_csv",
            "pharmaron": "pharmaron_csv",
            "enamine": "enamine_csv",
            "generic": "wuxi_csv",  # generic falls back to WuXi format
        }
        csv_path = exports.get(key_map.get(fmt, "wuxi_csv"), "")
        if not csv_path or not os.path.exists(csv_path):
            raise HTTPException(status_code=500, detail="Export file not generated")

        csv_text = Path(csv_path).read_text()

    from fastapi.responses import PlainTextResponse
    return PlainTextResponse(
        content=csv_text,
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{campaign_id}_{fmt}_order.csv"'},
    )


# ---------------------------------------------------------------------------
# Track D — Custom model wrapper
# ---------------------------------------------------------------------------

class RegisterModelRequest(BaseModel):
    name: str
    mode: str  # "python_function" | "docker" | "rest"
    # Docker mode
    image: Optional[str] = None
    command: Optional[list[str]] = None
    # REST mode
    endpoint: Optional[str] = None
    input_field: Optional[str] = "smiles"
    output_field: Optional[str] = "score"
    timeout_s: Optional[int] = 30
    # Scoring direction
    higher_is_better: bool = True
    weight: float = 1.0


@router.post("/{campaign_id}/models/register")
async def register_model(
    campaign_id: str,
    body: RegisterModelRequest,
    request: Request,
    _audit: None = Depends(_audit_fn),
):
    """
    Register a custom predictive model for this campaign.

    Supports three modes:
    - docker: BioMate calls a Docker container, passes SMILES list via stdin,
              reads JSON scores from stdout.
    - rest:   BioMate HTTP-POSTs SMILES to your endpoint, reads score from
              the specified JSON path.
    - python_function: (server-side only) attach a Python callable directly.
    """
    try:
        from .custom_model_registry import get_registry
        from .custom_model_wrapper import DockerModelWrapper, RESTModelWrapper
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        registry = get_registry(_campaign_db(campaign_id))

        if body.mode == "docker":
            if not body.image:
                raise HTTPException(status_code=400, detail="image required for docker mode")
            wrapper = DockerModelWrapper(
                name=body.name,
                campaign_id=campaign_id,
                image=body.image,
                command=body.command or [],
                weight=body.weight,
                higher_is_better=body.higher_is_better,
            )
        elif body.mode == "rest":
            if not body.endpoint:
                raise HTTPException(status_code=400, detail="endpoint required for rest mode")
            wrapper = RESTModelWrapper(
                name=body.name,
                campaign_id=campaign_id,
                endpoint=body.endpoint,
                input_key=body.input_field or "smiles",
                output_path=body.output_field or "score",
                timeout=body.timeout_s or 30,
                weight=body.weight,
                higher_is_better=body.higher_is_better,
            )
        else:
            raise HTTPException(
                status_code=400,
                detail="mode must be 'docker' or 'rest' (python_function requires server-side registration)",
            )

        mv = registry.register(wrapper, config={"registered_by": _request_actor(request)})
    except HTTPException:
        raise
    except Exception as exc:
        log.exception("model registration failed")
        raise HTTPException(status_code=500, detail=str(exc))

    return {"status": "registered", "campaign_id": campaign_id, "model_name": body.name,
            "mode": body.mode, "version": mv.version, "version_status": mv.status}


@router.get("/{campaign_id}/models")
async def list_models(campaign_id: str):
    """List registered models and their run history for a campaign."""
    try:
        from .custom_model_registry import get_registry
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        registry = get_registry(_campaign_db(campaign_id))
        models = registry.list_models(campaign_id)
        history = registry.get_run_log(campaign_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {"campaign_id": campaign_id, "models": models, "run_history": history}


@router.post("/{campaign_id}/models/{model_name}/run")
async def run_model(
    campaign_id: str,
    model_name: str,
    smiles_list: list[str] = None,
    _audit: None = Depends(_audit_fn),
):
    """
    Run a registered model against a list of SMILES.

    If smiles_list is omitted, runs against all compounds in the campaign DB.
    Returns per-compound scores and a run record for the audit log.
    """
    try:
        from .custom_model_registry import ArtifactIntegrityError, get_registry
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    if not smiles_list:
        try:
            svc = _campaign_service(campaign_id)
            ranks = svc.get_ranked_compounds(campaign_id)
            smiles_list = [r["smiles"] for r in ranks if r.get("smiles")]
        except Exception as exc:
            raise HTTPException(status_code=500, detail=str(exc))

    if not smiles_list:
        raise HTTPException(status_code=404, detail="No SMILES available; upload assay data first.")

    try:
        registry = get_registry(_campaign_db(campaign_id))
        scores, run_record = registry.run_named_model(campaign_id, model_name, smiles_list)
        active = registry.get_active_version(campaign_id, model_name)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc).strip("'\""))
    except ArtifactIntegrityError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except Exception as exc:
        log.exception("model run failed")
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "campaign_id": campaign_id,
        "model_name": model_name,
        "model_version": active.version if active else None,
        "scores": scores,
        "run_record": run_record.__dict__ if hasattr(run_record, "__dict__") else str(run_record),
    }


# ---------------------------------------------------------------------------
# Model versions — promotion, rollback, holdout comparison
# ---------------------------------------------------------------------------

def _request_actor(request: Request) -> str:
    """Caller identity as recorded by the compliance audit log."""
    try:
        from ..compliance.audit_middleware import _extract_user_id
        return _extract_user_id(request)
    except ImportError:
        return request.headers.get("X-BioMate-User-Id") or "anonymous"


def _version_errors(fn):
    from .custom_model_registry import (
        ArtifactIntegrityError, ModelRegistryError, PromotionBlocked,
    )
    try:
        return fn()
    except PromotionBlocked as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except ArtifactIntegrityError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except ModelRegistryError as exc:
        status = 404 if "has no version" in str(exc) else 422
        raise HTTPException(status_code=status, detail=str(exc))


class VersionDecisionRequest(BaseModel):
    reviewer: str            # named human decision-maker, recorded with the caller identity
    note: Optional[str] = None


class RollbackRequest(VersionDecisionRequest):
    to_version: Optional[int] = None


class HoldoutRow(BaseModel):
    smiles: str
    label: float


class CompareVersionsRequest(BaseModel):
    version_a: int
    version_b: int
    holdout: list[HoldoutRow]
    allow_training_overlap: bool = False


def _decision_actor(request: Request, reviewer: str) -> str:
    if not reviewer or not reviewer.strip():
        raise HTTPException(status_code=400, detail="reviewer is required")
    return f"{reviewer.strip()} (caller={_request_actor(request)})"


@router.get("/{campaign_id}/models/{model_name}/versions")
async def list_model_versions(campaign_id: str, model_name: str):
    from .custom_model_registry import get_registry
    registry = get_registry(_campaign_db(campaign_id))
    versions = registry.list_versions(campaign_id, model_name)
    if not versions:
        raise HTTPException(status_code=404, detail=f"Model '{model_name}' has no versions")
    active = next((v.version for v in versions if v.status == "active"), None)
    return {"campaign_id": campaign_id, "model_name": model_name, "active_version": active,
            "versions": [v.to_dict() for v in versions]}


@router.get("/{campaign_id}/models/{model_name}/versions/{version}")
async def get_model_version(campaign_id: str, model_name: str, version: int):
    from .custom_model_registry import get_registry
    registry = get_registry(_campaign_db(campaign_id))
    return _version_errors(lambda: registry.get_version(campaign_id, model_name, version).to_dict())


@router.post("/{campaign_id}/models/{model_name}/versions/{version}/promote")
async def promote_model_version(
    campaign_id: str, model_name: str, version: int, body: VersionDecisionRequest,
    request: Request, _audit: None = Depends(_audit_fn),
):
    """Make a candidate (gate passed, artifact hash verified) the single active version."""
    from .custom_model_registry import get_registry
    registry = get_registry(_campaign_db(campaign_id))
    actor = _decision_actor(request, body.reviewer)
    return _version_errors(lambda: registry.promote(
        campaign_id, model_name, version, actor=actor, note=body.note).to_dict())


@router.post("/{campaign_id}/models/{model_name}/versions/{version}/reject")
async def reject_model_version(
    campaign_id: str, model_name: str, version: int, body: VersionDecisionRequest,
    request: Request, _audit: None = Depends(_audit_fn),
):
    from .custom_model_registry import get_registry
    registry = get_registry(_campaign_db(campaign_id))
    actor = _decision_actor(request, body.reviewer)
    return _version_errors(lambda: registry.reject(
        campaign_id, model_name, version, actor=actor, note=body.note).to_dict())


@router.post("/{campaign_id}/models/{model_name}/rollback")
async def rollback_model_version(
    campaign_id: str, model_name: str, body: RollbackRequest,
    request: Request, _audit: None = Depends(_audit_fn),
):
    """Re-activate a previously active version (default: the most recently retired)."""
    from .custom_model_registry import get_registry
    registry = get_registry(_campaign_db(campaign_id))
    actor = _decision_actor(request, body.reviewer)
    return _version_errors(lambda: registry.rollback(
        campaign_id, model_name, actor=actor, to_version=body.to_version,
        note=body.note).to_dict())


@router.post("/{campaign_id}/models/{model_name}/compare")
async def compare_model_versions(
    campaign_id: str, model_name: str, body: CompareVersionsRequest,
    request: Request, _audit: None = Depends(_audit_fn),
):
    """Score two versions on the same holdout with identical metrics; the result is recorded.

    Refuses (422) when holdout molecules appear in either version's training data
    unless allow_training_overlap is set."""
    from .custom_model_registry import get_registry
    registry = get_registry(_campaign_db(campaign_id))
    holdout = [(r.smiles, r.label) for r in body.holdout]
    return _version_errors(lambda: registry.compare_versions(
        campaign_id, model_name, body.version_a, body.version_b, holdout,
        actor=_request_actor(request), allow_training_overlap=body.allow_training_overlap))


@router.get("/{campaign_id}/models/{model_name}/comparisons")
async def list_model_comparisons(campaign_id: str, model_name: str):
    from .custom_model_registry import get_registry
    registry = get_registry(_campaign_db(campaign_id))
    return {"campaign_id": campaign_id, "model_name": model_name,
            "comparisons": registry.list_comparisons(campaign_id, model_name)}


# ---------------------------------------------------------------------------
# Track F — Bayesian Optimizer propose (G7 gap closure)
# ---------------------------------------------------------------------------

class ProposeRequest(BaseModel):
    virtual_library_smiles: list[str]   # entity strings: SMILES, or sequences for peptide/biologic
    n_propose: int = 10
    diversity_weight: float = 0.2
    modality: str = "small_molecule"    # "small_molecule" | "peptide" | "biologic"


@router.post("/{campaign_id}/propose")
async def propose_next_round(
    campaign_id: str,
    body: ProposeRequest,
    _audit: None = Depends(_audit_fn),
):
    """
    Run BayesianOptimizer.propose_next_round() to select the next batch of
    compounds from a virtual library.

    Requires at least `n_initial` assay observations (from /ingest-assay) to
    have been ingested first so the surrogate GP model can be fitted.

    Body:
        virtual_library_smiles: list of SMILES to score under the surrogate.
        n_propose: how many compounds to select (default 10).
        diversity_weight: 0–1 weight for Tanimoto diversity penalty (default 0.2).

    Returns:
        proposed_smiles: selected SMILES (n_proposed may be below n_requested
            when library entries are invalid, duplicates or already measured;
            see surrogate_report.excluded_candidates),
        predicted_scores: surrogate predicted scores per objective,
        gp_stds: posterior std per objective and proposed compound,
        can_discriminate: False when the surrogate cannot confidently order
            any candidate pair — the scores then do not rank the compounds,
        surrogate_report: kernel, discrimination evidence, exclusions, warnings,
        round_metadata: acquisition details.
    """
    try:
        from .bayesian_optimizer import BayesianOptimizer
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    if not body.virtual_library_smiles:
        raise HTTPException(status_code=400, detail="virtual_library_smiles must not be empty")
    if body.n_propose < 1 or body.n_propose > len(body.virtual_library_smiles):
        raise HTTPException(
            status_code=400,
            detail=f"n_propose must be 1–{len(body.virtual_library_smiles)}"
        )

    try:
        svc = _campaign_service(campaign_id)
        ranked = svc.get_ranked_compounds(campaign_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to load campaign data: {exc}")

    if not ranked:
        raise HTTPException(
            status_code=404,
            detail=f"No assay data for campaign '{campaign_id}'. "
                   "Upload results first via POST /{campaign_id}/ingest-assay."
        )

    from .auto_retrain import build_training_rows, fit_campaign_optimizer, persist_round

    try:
        rows = build_training_rows(ranked)
        opt = fit_campaign_optimizer(_campaign_db(campaign_id), campaign_id, rows,
                                     modality=_campaign_modality(campaign_id))
        proposal = opt.propose_next_round(
            virtual_library_smiles=body.virtual_library_smiles,
            n_propose=body.n_propose,
            diversity_weight=body.diversity_weight,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except Exception as exc:
        log.exception("BayesianOptimizer.propose_next_round failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=str(exc))

    report = rows.report(len(ranked))
    # Persisting allocates the round in the campaign ledger, so this round is
    # numbered consistently with /retrain rounds and listed in /proposals.
    persist_round(_campaign_db(campaign_id), opt, proposal, "api_propose", report)

    return {
        "campaign_id": campaign_id,
        "training_report": report,
        "n_requested": body.n_propose,
        "n_proposed": len(proposal.proposed_compounds),
        "proposed_smiles": proposal.proposed_compounds,
        "predicted_scores": proposal.scores,
        "confidence_intervals": proposal.confidence_intervals,
        "ad_statuses": proposal.ad_statuses,
        "gp_stds": proposal.gp_stds,
        "can_discriminate": proposal.can_discriminate,
        "surrogate_report": proposal.surrogate_report,
        "round_metadata": {
            "round_number": proposal.round_number,
            "diversity_score": proposal.diversity_score,
            "acquisition_values": proposal.acquisition_values,
            "pareto_front_smiles": proposal.pareto_front_smiles,
            "timestamp": proposal.timestamp,
        },
    }


# ---------------------------------------------------------------------------
# Track G — Benchling LIMS polling (G3 gap closure)
# ---------------------------------------------------------------------------

class PollLimsRequest(BaseModel):
    mapping: Optional[dict] = None        # BenchlingSchemaMapping; omitted → stored mapping
    schema_id: Optional[str] = None       # selects the stored mapping when mapping is omitted
    since: Optional[str] = None           # RFC 3339 start for a first sync (default: full history)
    full_resync: bool = False             # ignore the stored watermark


_SECRET_QUERY_PARAMS = {"benchling_api_key", "api_key", "client_secret", "token", "access_token"}


@router.post("/{campaign_id}/lims/poll")
async def poll_lims(
    campaign_id: str,
    body: PollLimsRequest,
    request: Request,
    _audit: None = Depends(_audit_fn),
):
    """
    Pull reviewed, non-archived Benchling assay results for one assay-result
    schema into the campaign, then re-rank compounds.

    Credentials and the tenant URL come only from the server's environment /
    secret store (BENCHLING_TENANT_URL with BENCHLING_CLIENT_ID +
    BENCHLING_CLIENT_SECRET, or BENCHLING_API_KEY for trials); never from the
    request, so a caller cannot redirect server credentials to another host.

    Body: ``mapping`` (explicit per-schema field mapping, see
    drug_discovery.benchling_connector.BenchlingSchemaMapping) or ``schema_id``
    of a mapping stored by an earlier poll. Polls are incremental on the stored
    ``modifiedAt`` watermark and idempotent (rows are upserted on the Benchling
    result ID); results archived since the last poll are retracted.
    """
    leaked = sorted(_SECRET_QUERY_PARAMS & set(request.query_params))
    if leaked:
        raise HTTPException(status_code=400, detail=(
            f"Credentials must not be sent in the URL ({', '.join(leaked)}); they may now be in "
            "access logs, so rotate them. Configure Benchling credentials on the server instead."))
    try:
        from .benchling_connector import (
            BenchlingAPIError, BenchlingAssayPoller, BenchlingConfigError, BenchlingConnector,
            BenchlingMappingError, BenchlingSchemaMapping, SOURCE_SYSTEM, load_sync_state,
            save_sync_state,
        )
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    db_path = _campaign_db(campaign_id)
    schema_id = (body.mapping or {}).get("schema_id") or body.schema_id
    if not schema_id:
        raise HTTPException(status_code=400, detail="Give a mapping (with schema_id) or the schema_id "
                                                    "of a mapping stored by an earlier poll.")
    state = load_sync_state(db_path, campaign_id, schema_id)
    try:
        if body.mapping is not None:
            mapping = BenchlingSchemaMapping.from_dict(body.mapping)
        elif state is not None:
            mapping = BenchlingSchemaMapping.from_dict(state["mapping"])
        else:
            raise BenchlingMappingError(f"no stored mapping for schema '{schema_id}' in this campaign; "
                                        "send the mapping")
    except BenchlingMappingError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid Benchling mapping: {exc}")

    try:
        client = BenchlingConnector.from_env()
    except BenchlingConfigError as exc:
        raise HTTPException(status_code=503, detail=f"Benchling is not configured on this server: {exc}")

    notes: list[str] = []
    watermark = body.since
    if state is not None and not body.full_resync:
        if state["tenant_host"] != client.tenant_host:
            notes.append(f"Stored watermark belongs to tenant {state['tenant_host']}; "
                         f"reading {client.tenant_host} from the start.")
        elif state["mapping"] != mapping.to_dict():
            notes.append("Schema mapping changed since the last poll; re-reading the schema from the "
                         "start so every stored result is mapped the same way.")
        else:
            watermark = state["watermark"] or body.since

    try:
        polled = BenchlingAssayPoller(client, mapping).poll(modified_after=watermark)
    except (BenchlingAPIError, BenchlingConfigError) as exc:
        log.warning("Benchling LIMS poll failed for campaign %s: %s", campaign_id, exc)
        raise HTTPException(status_code=502, detail=f"Benchling API error: {exc}")

    try:
        svc = AssayIngestionService(db_path, modality=_campaign_modality(campaign_id))
        result = svc.ingest_rows(campaign_id, polled.rows)
        retracted = 0
        if polled.archived_result_ids:
            retraction = svc.retract_records(campaign_id, SOURCE_SYSTEM, polled.archived_result_ids)
            retracted = retraction["retracted"]
            result.update({k: retraction[k] for k in ("warnings", "updated_ranks")})
    except Exception as exc:
        log.exception("Benchling ingestion failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=f"Ingestion error: {exc}")

    save_sync_state(db_path, campaign_id, mapping, client.tenant_host, polled.next_watermark)
    return {
        "campaign_id": campaign_id,
        "source": "benchling",
        "tenant_host": client.tenant_host,
        "auth": client.auth_kind,
        "schema_id": mapping.schema_id,
        "status": "ingested" if (result["ingested"] or result["updated"] or retracted) else "no_new_data",
        "fetched": polled.fetched,
        "records_ingested": result["ingested"],
        "records_updated": result["updated"],
        "records_unchanged": result["unchanged"],
        "records_retracted": retracted,
        "skipped": polled.skipped,
        "errors": result["errors"],
        "warnings": result["warnings"],
        "notes": notes + result["notes"],
        "watermark": {"previous": polled.previous_watermark, "next": polled.next_watermark},
        "updated_ranks": result["updated_ranks"],
    }


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Phase 1 CRO — Model Validation (P1)
# ---------------------------------------------------------------------------

@router.get("/model-validation/{model_type}")
async def get_model_validation(
    model_type: str,
    drug_names: list[str] = Query(None, description="Optional drug name filter"),
    _audit: None = Depends(_audit_fn),
):
    """
    Return a regulatory-credible validation report for a BioMate predictive model.

    model_type: "pbpk" (more types planned: herg, ames, cyp_inhibition)

    Returns a ValidationReport containing:
      - per-compound: observed vs predicted Cmax/AUC, %PE, fold error
      - aggregate: AFE, AAFE, RMSE, R², within-2fold fraction
      - regulatory_summary: plain-English EMA PBPK guideline compliance statement
      - ema_criterion_met: true if ≥67% of predictions within 2-fold for both Cmax and AUC

    This report is suitable for attachment to computational study reports
    cited in IND pharmacology sections.
    """
    if model_type not in ("pbpk",):
        raise HTTPException(
            status_code=400,
            detail=f"model_type '{model_type}' not supported. Available: pbpk",
        )

    try:
        from .model_validation import ModelValidationService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=f"Model validation module unavailable: {exc}")

    try:
        svc = ModelValidationService()
        if model_type == "pbpk":
            report = svc.run_pbpk_validation(drug_names=drug_names)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:
        log.exception("Model validation failed for %s", model_type)
        raise HTTPException(status_code=500, detail=str(exc))

    return report.model_dump()


# ---------------------------------------------------------------------------
# Phase 3a — Auto-retrain: virtual library cache + latest proposal
# ---------------------------------------------------------------------------

@router.post("/{campaign_id}/virtual-library")
async def save_virtual_library(
    campaign_id: str,
    body: ProposeRequest,
    _audit: None = Depends(_audit_fn),
):
    """
    Cache a virtual library for the auto-retrain loop.

    The background auto-retrain daemon will re-score this library whenever
    new assay data is ingested, without requiring a manual /propose call.

    Body: same as /propose (virtual_library_smiles, n_propose, diversity_weight)
    """
    try:
        from .auto_retrain import save_virtual_library as _save_vl
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    if not body.virtual_library_smiles:
        raise HTTPException(status_code=400, detail="virtual_library_smiles must not be empty")

    try:
        _save_vl(
            _campaign_db(campaign_id),
            campaign_id,
            body.virtual_library_smiles,
            body.n_propose,
            body.diversity_weight,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "campaign_id": campaign_id,
        "status": "cached",
        "n_smiles": len(body.virtual_library_smiles),
        "n_propose": body.n_propose,
    }


class GenerateLibraryRequest(BaseModel):
    seed: str                      # seed amino-acid sequence
    max_size: int = 200
    conservative: bool = False     # restrict to conservative (within-group) substitutions
    n_propose: int = 10
    diversity_weight: float = 0.2


@router.post("/{campaign_id}/generate-library")
async def generate_library(
    campaign_id: str,
    body: GenerateLibraryRequest,
    _audit: None = Depends(_audit_fn),
):
    """Generate a candidate virtual library for a peptide/biologic campaign by
    enumerating point mutations of a seed sequence, and cache it for propose.
    Small-molecule generation is REINVENT4 (a separate generative workflow),
    not this deterministic sequence enumerator.
    """
    from .assay_schema import SEQUENCE_MODALITIES
    modality = _campaign_modality(campaign_id)
    if modality not in SEQUENCE_MODALITIES:
        raise HTTPException(
            status_code=400,
            detail="generate-library is for peptide/biologic campaigns; for small "
                   "molecules use REINVENT4 generative design.",
        )
    from .sequence_library import mutational_library
    from .auto_retrain import save_virtual_library
    lib = mutational_library(body.seed, conservative=body.conservative,
                             max_size=max(2, body.max_size))
    if len(lib) < 2:
        raise HTTPException(
            status_code=422,
            detail="Seed produced no candidates — provide a valid amino-acid sequence.",
        )
    save_virtual_library(_campaign_db(campaign_id), campaign_id, lib,
                         body.n_propose, body.diversity_weight)
    return {"campaign_id": campaign_id, "modality": modality,
            "library_size": len(lib), "seed": lib[0]}


@router.get("/{campaign_id}/auto-proposal")
async def get_auto_proposal(
    campaign_id: str,
    format: str = Query("json", regex="^(json|csv)$"),
):
    """
    Return the latest auto-retrain proposal for a campaign.

    Returns the Proposal shape expected by DrugDiscoveryAutoRetrain:
      { round, generated_at, trigger, can_discriminate,
        items: [{rank, smiles, score, std, ci_lo, ci_hi, ad}] }

    format=csv → downloadable CSV file
    """
    try:
        from .auto_retrain import get_latest_auto_proposal
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        proposal = get_latest_auto_proposal(_campaign_db(campaign_id), campaign_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    if proposal is None:
        raise HTTPException(status_code=404, detail="No proposals yet for this campaign.")

    if format == "csv":
        import csv as _csv
        import io
        from fastapi.responses import StreamingResponse

        shaped = _format_proposal(proposal)
        buf = io.StringIO()
        writer = _csv.DictWriter(buf, fieldnames=["rank", "smiles", "score", "std", "ci_lo",
                                                   "ci_hi", "ad"])
        writer.writeheader()
        writer.writerows(shaped["items"])
        filename = f"{campaign_id}_round{shaped['round']}_proposals.csv"
        return StreamingResponse(
            io.BytesIO(buf.getvalue().encode("utf-8")),
            media_type="text/csv",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )

    return _format_proposal(proposal)


@router.post("/{campaign_id}/retrain")
async def trigger_retrain(
    campaign_id: str,
    _audit: None = Depends(_audit_fn),
):
    """
    Manually trigger a GP refit + proposal round for the campaign.

    Uses the cached virtual library.  Returns the new proposal immediately.
    Also starts the background auto-retrain loop for this campaign if not
    already running.
    """
    try:
        from .auto_retrain import CampaignDataError, refit_and_propose, start_background_loop
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    db_path = _campaign_db(campaign_id)

    try:
        proposal = refit_and_propose(db_path, campaign_id, triggered_by="manual")
    except CampaignDataError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    if proposal is None:
        raise HTTPException(
            status_code=422,
            detail="Retrain failed: ensure assay data and a cached virtual library exist. "
                   "Call POST /{campaign_id}/virtual-library first.",
        )

    # Start background loop (idempotent)
    start_background_loop(db_path, campaign_id)

    return {
        "campaign_id": campaign_id,
        "proposal_id": proposal.id,
        "round_number": proposal.round_number,
        "n_proposed": len(proposal.proposed_smiles),
        "proposed_smiles": proposal.proposed_smiles,
        "scores": proposal.scores,
        "confidence_intervals": proposal.confidence_intervals,
        "gp_stds": proposal.gp_stds,
        "ad_statuses": proposal.ad_statuses,
        "created_at": proposal.created_at,
        "training_report": proposal.training_report,
        "can_discriminate": proposal.can_discriminate,
        "surrogate_report": proposal.surrogate_report,
    }


# ---------------------------------------------------------------------------
# Phase 3b — IND section assembly
# ---------------------------------------------------------------------------

class INDAssemblyRequest(BaseModel):
    molecule_name: str = "Investigational Compound"
    sponsor: str = "Sponsor"
    indication: str = "Investigational indication"
    target_name: str = "Investigational target"
    pk_summary: Optional[dict] = None      # pk_summary.json from predict_admet_properties run
    region: str = "ALL"                    # FDA | EMA | NMPA | PMDA | ALL
    glp_facility: str = ""                 # NMPA/CDE: GLP facility name for declaration
    glp_recognition: str = ""             # NMPA/CDE: GLP recognition statement
    ethnic_bridging_note: str = ""         # NMPA/PMDA: sponsor-provided ethnic bridging context
    wetlab_data: Optional[dict] = None     # measured wet-lab PK/safety data (overrides computational)
    # B3 per-org adaptation. When set, each _llm_narrative call reaches the
    # per-org prompt_rules YAML + few_shot_index via _build_rag_context.
    # The Node frontend should populate this from req.user.organization
    # (or req.user.id fallback for single-tenant users) before forwarding
    # the request — same source the regulatory_training_routes use.
    org_id: Optional[str] = None


@router.post("/{campaign_id}/ind-assembly")
async def assemble_ind_section(
    campaign_id: str,
    body: INDAssemblyRequest,
    _audit: None = Depends(_audit_fn),
):
    """
    Generate ICH M4 CTD Section 2.6.1 (Nonclinical Overview — Pharmacology).

    Combines:
      - PBPK model validation metrics (EMA-citable)
      - ADMET screening results from campaign data
      - Bayesian optimizer compound prioritization
      - Applicability domain assessment
      - 21 CFR Part 11 audit trail summary

    Returns paths to the generated Markdown and (if pandoc is installed) DOCX.

    Returns 409 if the document has already been frozen by an eSig.
    Use POST /{campaign_id}/ind-assembly/supersede to create a new version.
    """
    import hashlib

    # Freeze guard: reject regeneration if the current document is frozen
    db_path = _campaign_db(campaign_id)
    latest_hash_row = _get_latest_ind_hash(db_path, campaign_id)
    if latest_hash_row and latest_hash_row.get("is_frozen"):
        raise HTTPException(
            status_code=409,
            detail=(
                f"Document frozen after eSig (sig_id={latest_hash_row.get('sig_id')}, "
                f"frozen_by={latest_hash_row.get('frozen_by')}, "
                f"frozen_at={latest_hash_row.get('frozen_at')}). "
                f"Use POST /{campaign_id}/ind-assembly/supersede to create a new version."
            ),
        )

    try:
        from .ind_assembly import INDSectionAssembler
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    import tempfile
    output_dir = tempfile.mkdtemp(prefix=f"biomate_ind_{campaign_id}_")

    # Store pk_summary if provided, so it persists for future assemblies
    if body.pk_summary:
        try:
            _store_pk_summary(db_path, campaign_id, body.pk_summary)
        except Exception as exc:
            log.warning("Failed to store pk_summary for campaign %s: %s", campaign_id, exc)

    try:
        assembler = INDSectionAssembler(db_path)
        result = assembler.assemble(
            campaign_id=campaign_id,
            output_dir=output_dir,
            molecule_name=body.molecule_name,
            sponsor=body.sponsor,
            indication=body.indication,
            target_name=body.target_name,
            pk_summary=body.pk_summary,
            region=body.region,
            glp_facility=body.glp_facility,
            glp_recognition=body.glp_recognition,
            ethnic_bridging_note=body.ethnic_bridging_note,
            wetlab_data=body.wetlab_data,
            org_id=body.org_id,
        )
    except Exception as exc:
        log.exception("IND assembly failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=str(exc))

    # Read Markdown content to return inline
    markdown_content = Path(result.markdown_path).read_text(encoding="utf-8")

    # Compute and store document hash (hash of content already includes footer hash)
    doc_hash = hashlib.sha256(markdown_content.encode()).hexdigest()
    try:
        _store_ind_document_hash(db_path, campaign_id, doc_hash, result.generated_at,
                                 markdown_path=result.markdown_path)
    except Exception as exc:
        log.warning("Failed to store IND document hash for campaign %s: %s", campaign_id, exc)

    # Cache for download endpoint (include hash metadata)
    _ind_cache[campaign_id] = {
        "markdown_path": result.markdown_path,
        "docx_path": result.docx_path,
        "markdown_content": markdown_content,
        "doc_hash": doc_hash,
        "generated_at": result.generated_at,
    }

    # Serialize audit findings
    audit_findings_json = []
    for f in result.audit_findings:
        audit_findings_json.append({
            "severity": f.severity,
            "section": f.section,
            "guideline_id": f.guideline_id,
            "region": f.region,
            "code": f.code,
            "description": f.description,
            "suggestion": f.suggestion,
            "evidence": f.evidence,
        })

    return {
        "campaign_id": campaign_id,
        "sections": result.sections,
        "pandoc_available": result.pandoc_available,
        "docx_generated": result.docx_path is not None,
        "generated_at": result.generated_at,
        "warnings": result.warnings,
        "audit_findings": audit_findings_json,
        "audit_score": result.audit_score,
        "markdown_preview": markdown_content[:2000],
        "markdown_content": markdown_content,
        "markdown_path": result.markdown_path,
        "docx_path": result.docx_path,
        "doc_hash": doc_hash,
        "frozen": False,
    }


@router.get("/{campaign_id}/ind-assembly/download")
async def download_ind_file(
    campaign_id: str,
    format: str = Query("md", regex="^(md|docx)$"),
):
    """
    Download the last generated IND assembly file (Markdown or DOCX).
    Serves from the in-memory cache populated by the POST endpoint.

    Response headers include:
      X-Doc-Hash: SHA-256 of the document content
      X-Doc-Frozen: "true" if document has been eSig-frozen, "false" otherwise
      X-Frozen-At, X-Frozen-By: populated when frozen
    """
    from fastapi.responses import FileResponse, PlainTextResponse

    cached = _ind_cache.get(campaign_id)
    if not cached:
        raise HTTPException(status_code=404, detail="No IND assembly found for this campaign. Generate first.")

    # Retrieve freeze state from DB
    db_path = _campaign_db(campaign_id)
    hash_row = _get_latest_ind_hash(db_path, campaign_id)
    doc_hash = cached.get("doc_hash", hash_row.get("doc_hash", "") if hash_row else "")
    is_frozen = bool(hash_row and hash_row.get("is_frozen"))
    frozen_headers: dict = {
        "X-Doc-Hash": doc_hash,
        "X-Doc-Frozen": "true" if is_frozen else "false",
    }
    if is_frozen and hash_row:
        frozen_headers["X-Frozen-At"] = hash_row.get("frozen_at") or ""
        frozen_headers["X-Frozen-By"] = hash_row.get("frozen_by") or ""

    if format == "docx":
        docx_path = cached.get("docx_path")
        if not docx_path or not Path(docx_path).exists():
            raise HTTPException(status_code=404, detail="DOCX not available — pandoc may not be installed.")
        return FileResponse(
            docx_path,
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            filename=f"{campaign_id}_CTD_2.6.1.docx",
            headers=frozen_headers,
        )
    else:
        # Markdown — serve from cache (always available)
        content = cached.get("markdown_content") or ""
        if not content:
            md_path = cached.get("markdown_path")
            if md_path and Path(md_path).exists():
                content = Path(md_path).read_text(encoding="utf-8")
        if not content:
            raise HTTPException(status_code=404, detail="Markdown content not found in cache.")
        frozen_headers["Content-Disposition"] = f'attachment; filename="{campaign_id}_CTD_Module2.6.md"'
        return PlainTextResponse(
            content,
            media_type="text/markdown; charset=utf-8",
            headers=frozen_headers,
        )


@router.post("/{campaign_id}/ind-assembly/supersede")
async def supersede_ind_assembly(
    campaign_id: str,
    body: INDAssemblyRequest,
    _audit: None = Depends(_audit_fn),
):
    """
    Create a new IND document version when the current document is frozen after eSig.

    This endpoint bypasses the freeze guard and generates a fresh document. The new
    document will be stored as a new hash record and will require re-signing before
    it can be filed. The frozen record is preserved for audit traceability.

    Returns the same shape as POST /{campaign_id}/ind-assembly plus
      "supersedes": "<previous_frozen_hash>"
    """
    import hashlib

    db_path = _campaign_db(campaign_id)

    # Capture the frozen hash we are superseding (for audit trail)
    previous_row = _get_latest_ind_hash(db_path, campaign_id)
    superseded_hash = previous_row.get("doc_hash") if previous_row else None

    try:
        from .ind_assembly import INDSectionAssembler
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    import tempfile
    output_dir = tempfile.mkdtemp(prefix=f"biomate_ind_{campaign_id}_supersede_")

    if body.pk_summary:
        try:
            _store_pk_summary(db_path, campaign_id, body.pk_summary)
        except Exception as exc:
            log.warning("Failed to store pk_summary (supersede) for campaign %s: %s", campaign_id, exc)

    try:
        assembler = INDSectionAssembler(db_path)
        result = assembler.assemble(
            campaign_id=campaign_id,
            output_dir=output_dir,
            molecule_name=body.molecule_name,
            sponsor=body.sponsor,
            indication=body.indication,
            target_name=body.target_name,
            pk_summary=body.pk_summary,
            region=body.region,
            glp_facility=body.glp_facility,
            glp_recognition=body.glp_recognition,
            ethnic_bridging_note=body.ethnic_bridging_note,
            wetlab_data=body.wetlab_data,
            org_id=body.org_id,
        )
    except Exception as exc:
        log.exception("IND supersede assembly failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=str(exc))

    markdown_content = Path(result.markdown_path).read_text(encoding="utf-8")
    doc_hash = hashlib.sha256(markdown_content.encode()).hexdigest()

    try:
        _store_ind_document_hash(db_path, campaign_id, doc_hash, result.generated_at,
                                 markdown_path=result.markdown_path)
    except Exception as exc:
        log.warning("Failed to store supersede hash for campaign %s: %s", campaign_id, exc)

    _ind_cache[campaign_id] = {
        "markdown_path": result.markdown_path,
        "docx_path": result.docx_path,
        "markdown_content": markdown_content,
        "doc_hash": doc_hash,
        "generated_at": result.generated_at,
    }

    audit_findings_json = []
    for f in result.audit_findings:
        audit_findings_json.append({
            "severity": f.severity,
            "section": f.section,
            "guideline_id": f.guideline_id,
            "region": f.region,
            "code": f.code,
            "description": f.description,
            "suggestion": f.suggestion,
            "evidence": f.evidence,
        })

    log.info(
        "[ind_supersede] campaign=%s new_hash=%s supersedes=%s",
        campaign_id, doc_hash, superseded_hash,
    )

    return {
        "campaign_id": campaign_id,
        "sections": result.sections,
        "pandoc_available": result.pandoc_available,
        "docx_generated": result.docx_path is not None,
        "generated_at": result.generated_at,
        "warnings": result.warnings,
        "audit_findings": audit_findings_json,
        "audit_score": result.audit_score,
        "markdown_preview": markdown_content[:2000],
        "markdown_content": markdown_content,
        "markdown_path": result.markdown_path,
        "docx_path": result.docx_path,
        "doc_hash": doc_hash,
        "frozen": False,
        "supersedes": superseded_hash,
    }


# ---------------------------------------------------------------------------
# PK Predictions — link ADMET workflow outputs to campaign for IND §2.6.2
# ---------------------------------------------------------------------------

class PKSummaryRequest(BaseModel):
    pk_summary: dict


@router.post("/{campaign_id}/pk-summary")
async def store_pk_summary(
    campaign_id: str,
    body: PKSummaryRequest,
    _audit: None = Depends(_audit_fn),
):
    """
    Store pk_summary.json output from predict_admet_properties workflow.
    The stored data is automatically used in subsequent IND assembly requests
    to enrich §2.6.2 with compound-specific PK parameters.
    """
    try:
        _store_pk_summary(_campaign_db(campaign_id), campaign_id, body.pk_summary)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return {
        "campaign_id": campaign_id,
        "stored": True,
        "fu_plasma": body.pk_summary.get("fu_plasma"),
        "vd_lkg": body.pk_summary.get("vd_lkg"),
        "cl_hepatic_fraction": body.pk_summary.get("cl_hepatic_fraction"),
        "cl_renal_fraction": body.pk_summary.get("cl_renal_fraction"),
        "estimation_method": body.pk_summary.get("estimation_method"),
    }


@router.get("/{campaign_id}/pk-summary")
async def get_pk_summary(campaign_id: str):
    """Return the most recently stored pk_summary for a campaign, or 404 if not yet stored."""
    data = _load_pk_summary(_campaign_db(campaign_id), campaign_id)
    if data is None:
        raise HTTPException(status_code=404, detail="No PK predictions stored for this campaign. Run predict_admet_properties first.")
    return data


# ---------------------------------------------------------------------------
# Audit — Surface 3 endpoints
# ---------------------------------------------------------------------------

def _format_audit_record(r) -> dict:
    """
    Shape an AuditRecord into the frontend AuditRecord contract.

    Frontend expects: id, ts, who, kind, action, resource,
    payload_sha256, record_hash, prev_hash, detail?, meaning?, sig_id?
    """
    # Derive kind from action / user_id
    if r.action == "ESIG":
        kind = "esig"
    elif r.user_id.startswith("system:"):
        kind = "system"
    else:
        kind = "user"

    # Parse optional details fields: meaning=<...>, sig_id=<...>
    meaning: Optional[str] = None
    sig_id: Optional[str] = None
    if r.details:
        for part in r.details.split("|"):
            part = part.strip()
            if part.startswith("meaning="):
                meaning = part[len("meaning="):]
            elif part.startswith("sig_id="):
                sig_id = part[len("sig_id="):]

    return {
        "id":            r.id,
        "ts":            r.timestamp_utc,
        "who":           r.user_id,
        "kind":          kind,
        "action":        r.action,
        "resource":      f"{r.resource_type}/{r.resource_id}",
        "payload_sha256": r.payload_hash,
        "record_hash":   r.record_hash,
        "prev_hash":     r.previous_hash,
        "detail":        r.details or None,
        "meaning":       meaning,
        "sig_id":        sig_id,
    }


# ---------------------------------------------------------------------------
# De-novo generation — expose the existing closed generate->predict->select->rank
# loop over HTTP. DeNovoPipeline + get_generator + BayesianOptimizer already
# exist and are unit-tested (test_denovo_pipeline.py); only the endpoint was
# missing. Built-in RDKit objectives (QED / SA) keep the BRICS path fully
# self-contained (no external key, no retraining). The learned NIM generators
# (bionemo_genmol/molmim) are selectable and degrade HONESTLY to an empty ranked
# list + status note when NVIDIA_API_KEY is unset — never fabricated molecules.
# ---------------------------------------------------------------------------

class DeNovoRunRequest(BaseModel):
    seed_smiles: list                      # labelled seeds the GP is fit on
    generator: str = "brics"               # brics | bionemo_genmol | bionemo_molmim
    objectives: list = ["qed", "sa"]       # built-in RDKit objectives
    n_molecules: int = 50
    max_candidates: int = 2000
    n_propose: int = 10
    campaign_id: Optional[str] = None


def _builtin_objective(name: str):
    """ObjectiveSpec for a built-in RDKit objective, or None if unknown.

    'qed' -> drug-likeness (maximize) · 'sa' -> synthetic accessibility (minimize).
    Predictors omit molecules RDKit cannot parse (honest partial scoring), and
    return {} if RDKit is unavailable so the pipeline degrades rather than crashes.
    """
    from .denovo_pipeline import ObjectiveSpec
    key = (name or "").strip().lower()
    if key == "qed":
        def _qed(smiles_list: list) -> dict:
            try:
                from rdkit import Chem
                from rdkit.Chem import QED
            except Exception:
                return {}
            out = {}
            for smi in smiles_list:
                mol = Chem.MolFromSmiles(smi)
                if mol is not None:
                    out[smi] = float(QED.qed(mol))
            return out
        return ObjectiveSpec("qed", _qed, direction="maximize")
    if key in ("sa", "sa_score", "synthetic_accessibility"):
        def _sa(smiles_list: list) -> dict:
            from .cro_order_export import _sa_score
            out = {}
            for smi in smiles_list:
                v = _sa_score(smi)
                if v is not None:
                    out[smi] = float(v)
            return out
        return ObjectiveSpec("sa", _sa, direction="minimize")
    return None


@router.post("/denovo/run-round")
async def denovo_run_round(request: DeNovoRunRequest):
    """Run one closed de-novo generate -> predict -> GP-select -> rank iteration.

    Thin wiring over the existing DeNovoPipeline + get_generator + BayesianOptimizer.
    Honest: BRICS is deterministic enumeration (is_learned=False); NIM generators
    are learned but return an empty ranked list + status when no NVIDIA_API_KEY —
    never fabricated molecules.
    """
    from .generators import get_generator, GenerationSpec
    from .denovo_pipeline import DeNovoPipeline

    objectives = []
    for nm in (request.objectives or []):
        spec_obj = _builtin_objective(nm)
        if spec_obj is None:
            raise HTTPException(status_code=400, detail=f"Unknown objective {nm!r}; available: qed, sa")
        objectives.append(spec_obj)
    if not objectives:
        raise HTTPException(status_code=400, detail="At least one objective is required")
    if not request.seed_smiles:
        raise HTTPException(status_code=400, detail="seed_smiles must be a non-empty list")

    try:
        generator = get_generator(request.generator)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Isolated ephemeral DB for the optimizer's persistence. A stateless one-shot
    # round must NOT write bo_proposals into a shared/relative "galaxy_ai_tools.db"
    # (default), which — resolved against the backend CWD — could collide with the
    # real workflow DB. Use a per-request temp file and delete it afterward.
    _fd, _tmp_db = tempfile.mkstemp(prefix="denovo_", suffix=".db")
    os.close(_fd)
    pipeline = DeNovoPipeline(
        campaign_id=request.campaign_id or "denovo-adhoc",
        generator=generator,
        objectives=objectives,
        db_path=_tmp_db,
        n_initial=min(8, max(1, len(request.seed_smiles))),
    )
    spec = GenerationSpec(
        seed_smiles=request.seed_smiles[0],
        n_molecules=request.n_molecules,
        max_candidates=request.max_candidates,
    )
    try:
        result = pipeline.run_round(spec, seed_smiles=request.seed_smiles, n_propose=request.n_propose)
    except (ImportError, ValueError) as e:
        raise HTTPException(status_code=422, detail=str(e))
    finally:
        try:
            os.remove(_tmp_db)
        except OSError:
            pass

    # Return only JSON-safe fields (ranked is a list of plain dicts); omit the
    # RoundProposal object which may carry numpy arrays.
    return {
        "campaign_id": result.campaign_id,
        "generator_name": result.generator_name,
        "generator_is_learned": result.generator_is_learned,
        "generator_status": result.generator_status,
        "n_generated": result.n_generated,
        "n_scored": result.n_scored,
        "ranked": result.ranked,
        "notes": result.notes,
    }


@router.get("/audit")
async def query_audit_log(
    resource_id: Optional[str] = Query(None, description="campaign_id to filter by"),
    user: Optional[str] = Query(None),
    action: Optional[str] = Query(None),
    from_: Optional[str] = Query(None, alias="from", description="ISO 8601 UTC datetime"),
    limit: int = Query(PAGE_SIZE := 10, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """
    Query the 21 CFR Part 11 audit log (Surface 3).

    Returns paginated records in the shape expected by DrugDiscoveryAuditViewer:
      { records: AuditRecord[], total: number }
    """
    try:
        from ..compliance.audit_store import AuditStore
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        store = AuditStore()
        # Get one extra to count total without a separate COUNT query
        all_matching = store.get_records(
            resource_id=resource_id,
            user_id=user,
            action=action,
            since_utc=from_,
            limit=10_000,   # practical cap; real deployments stay well below this
        )
        total = len(all_matching)
        page = all_matching[offset: offset + limit]
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "records": [_format_audit_record(r) for r in page],
        "total": total,
    }


@router.get("/audit/verify")
async def verify_audit_chain(
    resource_id: Optional[str] = Query(None),
):
    """
    Run full hash-chain verification.

    Returns { valid, verified_at, broken_at?, total_records }.
    """
    try:
        from ..compliance.audit_store import AuditStore
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        store = AuditStore()
        result = store.verify_chain()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    from datetime import datetime, timezone
    return {
        "valid":          result.valid,
        "verified_at":    datetime.now(timezone.utc).isoformat(),
        "broken_at":      result.first_tampered_id,
        "total_records":  result.total_records,
    }


@router.get("/audit/export")
async def export_audit_log(
    campaign_id: Optional[str] = Query(None),
    format: str = Query("csv", regex="^(csv|json)$"),
):
    """
    Download the full audit log for a campaign as CSV or JSON.
    """
    import csv as _csv
    import io
    from fastapi.responses import StreamingResponse

    try:
        from ..compliance.audit_store import AuditStore
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        store = AuditStore()
        records = store.get_records(resource_id=campaign_id, limit=100_000)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    formatted = [_format_audit_record(r) for r in records]

    if format == "json":
        import json
        content = json.dumps(formatted, indent=2)
        media_type = "application/json"
        filename = f"audit_{campaign_id or 'all'}.json"
    else:
        buf = io.StringIO()
        if formatted:
            writer = _csv.DictWriter(buf, fieldnames=list(formatted[0].keys()),
                                     extrasaction="ignore")
            writer.writeheader()
            writer.writerows(formatted)
        content = buf.getvalue()
        media_type = "text/csv"
        filename = f"audit_{campaign_id or 'all'}.csv"

    return StreamingResponse(
        io.BytesIO(content.encode("utf-8")),
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ---------------------------------------------------------------------------
# Auto-Retrain — Surface 4 endpoints
# ---------------------------------------------------------------------------

@router.get("/{campaign_id}/retrain/status")
async def get_retrain_status(campaign_id: str):
    """
    Return loop status for polling by DrugDiscoveryAutoRetrain (every 5s).

    Response: { running, check_interval_s, last_retrain_at, next_check_in_s,
                last_trigger }
    """
    try:
        from .auto_retrain import is_loop_running, get_latest_auto_proposal, _loop_stop_events
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    running = is_loop_running(campaign_id)
    db_path = _campaign_db(campaign_id)

    last_proposal = None
    try:
        last_proposal = get_latest_auto_proposal(db_path, campaign_id)
    except Exception:
        pass

    check_interval_s = 60
    return {
        "running":          running,
        "check_interval_s": check_interval_s,
        "last_retrain_at":  last_proposal.created_at if last_proposal else None,
        "next_check_in_s":  check_interval_s,  # client reconciles against its own countdown
        "last_trigger":     last_proposal.triggered_by if last_proposal else None,
    }


@router.post("/{campaign_id}/retrain/start")
async def start_retrain_loop(
    campaign_id: str,
    _audit: None = Depends(_audit_fn),
):
    """Start the background auto-retrain loop (idempotent)."""
    try:
        from .auto_retrain import start_background_loop
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    start_background_loop(_campaign_db(campaign_id), campaign_id)
    return {"running": True}


@router.post("/{campaign_id}/retrain/stop")
async def stop_retrain_loop(
    campaign_id: str,
    _audit: None = Depends(_audit_fn),
):
    """Signal the background auto-retrain loop to stop."""
    try:
        from .auto_retrain import stop_background_loop
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    stop_background_loop(campaign_id)
    return {"running": False}


@router.post("/{campaign_id}/retrain/trigger")
async def trigger_retrain_now(
    campaign_id: str,
    _audit: None = Depends(_audit_fn),
):
    """
    Force an immediate GP refit + proposal round.

    Returns the new Proposal in the shape expected by DrugDiscoveryAutoRetrain:
      { round, generated_at, trigger, can_discriminate,
        items: [{rank, smiles, score, std, ci_lo, ci_hi, ad}] }
    """
    try:
        from .auto_retrain import CampaignDataError, refit_and_propose, start_background_loop
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    db_path = _campaign_db(campaign_id)
    try:
        proposal = refit_and_propose(db_path, campaign_id, triggered_by="manual")
    except CampaignDataError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    if proposal is None:
        raise HTTPException(
            status_code=422,
            detail=(
                "Retrain requires assay data and a cached virtual library. "
                "Call POST /{campaign_id}/virtual-library first."
            ),
        )

    start_background_loop(db_path, campaign_id)

    result = _format_proposal(proposal)
    # ADMET screening of the proposal is a separate, user-attributed (billed)
    # workflow run launched through /api/nextflow/execute; it is not started
    # implicitly here, and the response says so explicitly.
    result["admet_followup"] = {
        "submitted": False,
        "reason": "ADMET screening is not launched automatically by a retrain; "
                  "run an ADMET workflow on proposed_smiles as the requesting user.",
        "proposed_smiles": list(proposal.proposed_smiles),
    }
    return result


@router.get("/{campaign_id}/retrain")
async def trigger_retrain_legacy(
    campaign_id: str,
    _audit: None = Depends(_audit_fn),
):
    """
    Deprecated: use POST /{campaign_id}/retrain/trigger instead.
    Kept for backwards compatibility with earlier frontend code.
    """
    return await trigger_retrain_now(campaign_id, _audit)


def _format_proposal(proposal) -> dict:
    """
    Shape an AutoProposal into the Proposal contract expected by the frontend:
      { round, generated_at, trigger, can_discriminate,
        items: [{rank, smiles, score, std, ci_lo, ci_hi, ad}] }
    """
    from .auto_retrain import CAMPAIGN_OBJECTIVE

    smiles = proposal.proposed_smiles
    # BayesianOptimizer emits {objective: [value per proposed compound]}.
    scores = proposal.scores
    ci = proposal.confidence_intervals
    ad = proposal.ad_statuses  # list parallel to smiles
    stds = getattr(proposal, "gp_stds", None) or {}
    std_list = stds.get(CAMPAIGN_OBJECTIVE) if isinstance(stds, dict) else None

    if isinstance(scores, dict) and CAMPAIGN_OBJECTIVE in scores:
        scores = scores[CAMPAIGN_OBJECTIVE]
    if isinstance(ci, dict) and CAMPAIGN_OBJECTIVE in ci:
        ci = ci[CAMPAIGN_OBJECTIVE]

    # Normalise scores to a list aligned with smiles
    if isinstance(scores, dict):
        score_list = [float(scores.get(s, 0.0)) for s in smiles]
    elif isinstance(scores, list):
        score_list = [float(v) for v in scores]
    else:
        score_list = [0.0] * len(smiles)

    # Normalise CI: may be dict-of-lists {"lo": [...], "hi": [...]} or list of (lo, hi)
    ci_lo_list: list[float] = []
    ci_hi_list: list[float] = []
    if isinstance(ci, dict):
        ci_lo_list = [float(v) for v in ci.get("lo", ci.get("lower", [0.0] * len(smiles)))]
        ci_hi_list = [float(v) for v in ci.get("hi", ci.get("upper", [1.0] * len(smiles)))]
    elif isinstance(ci, list):
        for entry in ci:
            if isinstance(entry, (list, tuple)) and len(entry) >= 2:
                ci_lo_list.append(float(entry[0]))
                ci_hi_list.append(float(entry[1]))
            else:
                ci_lo_list.append(0.0)
                ci_hi_list.append(1.0)
    if not ci_lo_list:
        ci_lo_list = [0.0] * len(smiles)
        ci_hi_list = [1.0] * len(smiles)

    ad_list = list(ad) if ad else ["in_domain"] * len(smiles)

    items = []
    for i, smi in enumerate(smiles):
        items.append({
            "rank":    i + 1,
            "smiles":  smi,
            "score":   score_list[i] if i < len(score_list) else 0.0,
            # None for rounds persisted before posterior stds were stored.
            "std":     float(std_list[i]) if std_list and i < len(std_list) else None,
            "ci_lo":   ci_lo_list[i] if i < len(ci_lo_list) else 0.0,
            "ci_hi":   ci_hi_list[i] if i < len(ci_hi_list) else 1.0,
            "ad":      ad_list[i] if i < len(ad_list) else "in_domain",
        })

    return {
        "round":        proposal.round_number,
        "generated_at": proposal.created_at,
        "trigger":      proposal.triggered_by,
        "items":        items,
        "training_report": proposal.training_report,
        # False: predicted differences are within uncertainty, so the items are
        # not a ranking. None: round persisted before this was recorded.
        "can_discriminate": getattr(proposal, "can_discriminate", None),
        "surrogate_report": getattr(proposal, "surrogate_report", None) or {},
    }


@router.get("/{campaign_id}/proposals")
async def list_proposals(
    campaign_id: str,
    limit: int = Query(20, ge=1, le=100),
):
    """
    Return proposal history: { history: [{round, ts, n, trigger}] }
    """
    try:
        from .auto_retrain import list_auto_proposals
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        proposals = list_auto_proposals(_campaign_db(campaign_id), campaign_id, limit=limit)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "history": [
            {
                "round":   p.round_number,
                "ts":      p.created_at,
                "n":       len(p.proposed_smiles),
                "trigger": p.triggered_by,
            }
            for p in proposals
        ]
    }


@router.get("/{campaign_id}/virtual-library")
async def get_virtual_library(campaign_id: str):
    """
    Return cached virtual library metadata.

    Response: { n, saved_at, hash, n_propose, diversity_weight }
    404 if no library cached yet.
    """
    try:
        from .auto_retrain import load_virtual_library
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        vl = load_virtual_library(_campaign_db(campaign_id), campaign_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    if vl is None:
        raise HTTPException(status_code=404, detail="No virtual library cached for this campaign.")

    # Compute a stable hash of the library for the frontend to display
    import hashlib, json
    lib_hash = hashlib.sha256(json.dumps(vl["smiles_list"], sort_keys=True).encode()).hexdigest()

    return {
        "n":                len(vl["smiles_list"]),
        "saved_at":         vl["saved_at"],
        "hash":             lib_hash,
        "n_propose":        vl["n_propose"],
        "diversity_weight": vl["diversity_weight"],
    }


class VirtualLibraryBody(BaseModel):
    smiles: list[str]
    n_propose: int = 10
    diversity_weight: float = 0.2


@router.post("/{campaign_id}/virtual-library")
async def save_virtual_library_endpoint(
    campaign_id: str,
    body: VirtualLibraryBody,
    _audit: None = Depends(_audit_fn),
):
    """
    Cache a virtual library for the auto-retrain loop.

    Response: { n_valid, n_invalid, hash }
    """
    try:
        from .auto_retrain import save_virtual_library as _save_vl
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    if not body.smiles:
        raise HTTPException(status_code=400, detail="smiles must not be empty")

    # Validate SMILES with RDKit if available; otherwise accept all
    valid, invalid = [], []
    try:
        from rdkit import Chem
        for smi in body.smiles:
            (valid if Chem.MolFromSmiles(smi) is not None else invalid).append(smi)
    except ImportError:
        valid = list(body.smiles)

    if not valid:
        raise HTTPException(status_code=422, detail="No valid SMILES provided.")

    try:
        _save_vl(_campaign_db(campaign_id), campaign_id, valid, body.n_propose, body.diversity_weight)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    import hashlib, json
    lib_hash = hashlib.sha256(json.dumps(valid, sort_keys=True).encode()).hexdigest()
    return {"n_valid": len(valid), "n_invalid": len(invalid), "hash": lib_hash}


# ---------------------------------------------------------------------------
# Commercial availability check (standalone utility)
# ---------------------------------------------------------------------------

@router.get("/availability")
async def check_availability(
    smiles: list[str] = Query(..., description="SMILES strings to check"),
    mock: bool = Query(False, description="Use mock mode (no PubChem calls)"),
):
    """
    Batch commercial availability check via PubChem PUG REST.

    Returns per-compound availability status and vendor sources.
    """
    if len(smiles) > 100:
        raise HTTPException(status_code=400, detail="Maximum 100 SMILES per request")

    try:
        from .commercial_availability import CommercialAvailabilityChecker
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        checker = CommercialAvailabilityChecker(mock_mode=mock)
        compound_ids = [f"SMILES_{i}" for i in range(len(smiles))]
        results = checker.check_batch(smiles, compound_ids)
        summary = checker.availability_summary(results)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "summary": summary,
        "compounds": [
            {
                "smiles": r.smiles,
                "is_available": r.is_available,
                "sources": r.sources,
                "checked_at": r.checked_at,
            }
            for r in results
        ],
    }


# ---------------------------------------------------------------------------
# Campaign creation (Surface 7 — Campaign Wizard)
# ---------------------------------------------------------------------------

class CampaignCreateRequest(BaseModel):
    campaign_id: Optional[str] = None
    molecule_name: str = ""
    target: str = ""
    indication: str = ""
    sponsor: str = ""
    objective: str = "balance"   # "potency" | "admet" | "balance"
    user_id: str = ""
    virtual_library_smiles: list[str] = []
    modality: str = "small_molecule"   # "small_molecule" | "peptide" | "biologic"


@router.post("/campaigns")
async def create_campaign(body: CampaignCreateRequest):
    """
    Create a new drug discovery campaign.

    Provisions the per-campaign SQLite database, optionally seeds the
    virtual library, and activates the auto-retrain loop skeleton.

    Returns: { campaign_id, created_at, n_library }
    """
    import random, string
    from datetime import datetime, timezone

    # Generate ID if not provided
    if body.campaign_id and body.campaign_id.strip():
        campaign_id = body.campaign_id.strip()
    else:
        rand = "".join(random.choices(string.hexdigits[:16], k=8))
        campaign_id = f"cmp-{rand}"

    # Touch the campaign DB (creates the SQLite file + tables on first access)
    db_path = _campaign_db(campaign_id)

    try:
        from .assay_ingestion import AssayIngestionService
        svc = AssayIngestionService(db_path)
        svc.ensure_schema()
    except Exception:
        pass  # Schema init is best-effort; DB file is already created

    # Seed virtual library if provided
    n_library = 0
    if body.virtual_library_smiles:
        try:
            from .auto_retrain import save_virtual_library as _save_vl
            valid = body.virtual_library_smiles
            try:
                from rdkit import Chem
                valid = [s for s in body.virtual_library_smiles if Chem.MolFromSmiles(s) is not None]
            except ImportError:
                pass
            if valid:
                _save_vl(db_path, campaign_id, valid, n_propose=10, diversity_weight=0.2)
                n_library = len(valid)
        except Exception as exc:
            log.warning("Could not seed virtual library for campaign %s: %s", campaign_id, exc)

    created_at = datetime.now(timezone.utc).isoformat()

    # Register in global registry so GET /campaigns can list by user
    try:
        conn = _registry_conn()
        conn.execute(
            """
            INSERT OR REPLACE INTO campaigns
                (campaign_id, user_id, molecule_name, target, indication, sponsor, objective, created_at, modality)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                campaign_id,
                body.user_id or "",
                body.molecule_name,
                body.target,
                body.indication,
                body.sponsor,
                body.objective,
                created_at,
                getattr(body, "modality", "small_molecule") or "small_molecule",
            ),
        )
        conn.commit()
        conn.close()
    except Exception as exc:
        log.warning("Could not register campaign %s in registry: %s", campaign_id, exc)

    return {
        "campaign_id": campaign_id,
        "created_at": created_at,
        "molecule_name": body.molecule_name,
        "target": body.target,
        "indication": body.indication,
        "sponsor": body.sponsor,
        "objective": body.objective,
        "n_library": n_library,
    }


@router.get("/campaigns")
async def list_campaigns(user_id: str = Query("", description="Filter campaigns by user ID")):
    """
    List drug discovery campaigns.

    Optionally filtered to a specific user via ?user_id=...
    Returns campaigns in reverse-chronological order (newest first).
    """
    try:
        conn = _registry_conn()
        if user_id:
            rows = conn.execute(
                "SELECT * FROM campaigns WHERE user_id = ? ORDER BY created_at DESC",
                (user_id,),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM campaigns ORDER BY created_at DESC LIMIT 100"
            ).fetchall()
        conn.close()
        return {"campaigns": [dict(r) for r in rows]}
    except Exception as exc:
        log.warning("Could not list campaigns from registry: %s", exc)
        return {"campaigns": []}


# ---------------------------------------------------------------------------
# eSig endpoints (Surface 5 — Electronic Signature Modal)
# ---------------------------------------------------------------------------

# Global audit DB for user-level eSig secrets (not per-campaign)
_ESIG_DB_PATH = os.environ.get(
    "BIOMATE_ESIG_DB",
    str(Path(__file__).parent.parent.parent.parent.parent / "database" / "esig_global.db"),
)


def _esig_service():
    """Return a singleton ESignatureService backed by the global eSig DB."""
    try:
        from ..compliance.audit_store import AuditStore
        from ..compliance.esig import ESignatureService
        store = AuditStore(_ESIG_DB_PATH)
        return ESignatureService(store)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"eSig service unavailable: {exc}")


@router.get("/esig/status")
async def esig_status(user_id: str = Query(..., description="User ID to check enrollment")):
    """Return whether a user is enrolled for TOTP eSig."""
    svc = _esig_service()
    return {"user_id": user_id, "enrolled": svc.is_registered(user_id)}


@router.post("/esig/enroll")
async def esig_enroll(user_id: str = Query(...)):
    """
    Begin TOTP enrollment: generate a fresh secret and return the otpauth URI.

    The frontend renders this as a QR code (qrcode.react).
    The user must then call POST /esig/enroll/verify with a valid token to confirm.
    """
    svc = _esig_service()
    secret = svc.register_user(user_id)  # stores encrypted secret in DB
    # Build otpauth URI (RFC 6238)
    import urllib.parse
    label = urllib.parse.quote(f"BioMate:{user_id}")
    issuer = urllib.parse.quote("BioMate")
    qr_uri = f"otpauth://totp/{label}?secret={secret}&issuer={issuer}&algorithm=SHA1&digits=6&period=30"
    return {"user_id": user_id, "qr_uri": qr_uri, "secret": secret}


class EsigVerifyRequest(BaseModel):
    user_id: str
    totp_token: str


@router.post("/esig/enroll/verify")
async def esig_enroll_verify(body: EsigVerifyRequest):
    """
    Verify the first TOTP token after enrollment — confirms the user scanned
    the QR code correctly.  Returns {success: true} or raises 422.
    """
    try:
        from ..compliance.esig import TOTPService, ESignatureService
        from ..compliance.audit_store import AuditStore
        store = AuditStore(_ESIG_DB_PATH)
        svc = ESignatureService(store)
        secret = svc._load_secret(body.user_id)
        if not secret:
            raise HTTPException(status_code=404, detail="User not enrolled — call POST /esig/enroll first")
        ok = TOTPService.verify(secret, body.totp_token)
        if not ok:
            raise HTTPException(status_code=422, detail="Invalid TOTP token")
        return {"success": True, "user_id": body.user_id}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


class EsigSignRequest(BaseModel):
    user_id: str
    action: str          # e.g. "EXPORT_CRO_ORDER"
    meaning: str         # "I approve…" — permanently recorded
    totp_token: str
    # 21 CFR Part 11 §11.50 reviewer credentials (optional but recommended for IND actions)
    reviewer_title: Optional[str] = None        # e.g. "Director, Computational Pharmacology"
    reviewer_credentials: Optional[str] = None  # e.g. "PhD Pharmacology, 10 years IND experience"
    review_scope: Optional[str] = None          # e.g. "§2.6.1–§2.6.5 nonclinical pharmacology"


@router.post("/{campaign_id}/esig/sign")
async def esig_sign(campaign_id: str, body: EsigSignRequest):
    """
    Apply a 21 CFR Part 11 electronic signature to a regulatory action.

    The signature record is written to the campaign audit trail.
    Returns { sig_id, signed_at, action, meaning }.
    """
    try:
        from ..compliance.audit_store import AuditStore
        from ..compliance.esig import ESignatureService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    # Signing uses the campaign audit DB so the ESIG record is co-located
    # with the campaign's audit trail.
    try:
        store = AuditStore(_campaign_db(campaign_id))
        svc = ESignatureService(store)
        sig = svc.sign(
            user_id=body.user_id,
            action=body.action,
            meaning=body.meaning,
            totp_token=body.totp_token,
            reviewer_title=body.reviewer_title,
            reviewer_credentials=body.reviewer_credentials,
            review_scope=body.review_scope,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except Exception as exc:
        log.exception("eSig signing failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=str(exc))

    response: dict = {
        "sig_id": sig.sig_id,
        "signed_at": sig.timestamp_utc,
        "action": sig.action,
        "meaning": sig.meaning,
    }
    # Include reviewer credentials in response if provided
    if sig.reviewer_title:
        response["reviewer_title"] = sig.reviewer_title
    if sig.reviewer_credentials:
        response["reviewer_credentials"] = sig.reviewer_credentials
    if sig.review_scope:
        response["review_scope"] = sig.review_scope

    # Freeze IND document when signing an IND-related action
    if body.action in ("GENERATE_IND", "ASSEMBLE_IND"):
        frozen_hash = _freeze_ind_document(
            _campaign_db(campaign_id), campaign_id, sig.sig_id, body.user_id,
            reviewer_title=body.reviewer_title,
            reviewer_credentials=body.reviewer_credentials,
            review_scope=body.review_scope,
        )
        if frozen_hash:
            response["frozen_doc_hash"] = frozen_hash
            response["frozen"] = True
            log.info(
                "[esig_freeze] campaign=%s sig_id=%s doc_hash=%s frozen by %s",
                campaign_id, sig.sig_id, frozen_hash, body.user_id,
            )
        else:
            response["frozen"] = False

    return response


# ---------------------------------------------------------------------------
# Regulatory Skills DB — knowledge learned from approved documents
# ---------------------------------------------------------------------------

@router.get("/regulatory-skills/summary")
async def regulatory_skills_summary():
    """
    Return current state of the regulatory skills DB.

    Documents, skills, benchmarks, and narrative patterns
    extracted from EMA-accepted OSP Qualification Reports.
    """
    try:
        from .regulatory_skills_db import RegulatorySkillsDB
        db = RegulatorySkillsDB()
        return db.summary()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/regulatory-skills/ingest")
async def regulatory_skills_ingest(force_refresh: bool = False):
    """
    Download and ingest all authoritative regulatory sources.

    Sources: 6 OSP Qualification Reports (GPL, EMA-accepted).
    Idempotent — re-ingestion skipped unless force_refresh=true.
    Returns per-source status and skill counts.
    """
    try:
        from .regulatory_skills_db import RegulatorySkillsDB
        db = RegulatorySkillsDB()
        results = db.ingest_all(force_refresh=force_refresh)
        total_skills = sum(r.get("skills_added", 0) for r in results.values())
        return {
            "ingested_sources": len([r for r in results.values() if r.get("status") == "ingested"]),
            "total_skills_added": total_skills,
            "details": results,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/regulatory-skills/pbpk-benchmarks")
async def regulatory_skills_pbpk_benchmarks():
    """Return all PBPK benchmark records from approved OSP reports."""
    try:
        from .regulatory_skills_db import RegulatorySkillsDB
        db = RegulatorySkillsDB()
        return {"benchmarks": db.get_pbpk_benchmarks()}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/regulatory-skills/narratives")
async def regulatory_skills_narratives(
    ctd_section: Optional[str] = Query(None, description="Filter by CTD section, e.g. '2.6.2'"),
    pattern_type: Optional[str] = Query(None, description="Filter by pattern type: criterion_statement | regulatory_sentence"),
):
    """Return narrative patterns extracted from approved regulatory documents."""
    try:
        from .regulatory_skills_db import RegulatorySkillsDB
        db = RegulatorySkillsDB()
        return {"patterns": db.get_narrative_patterns(ctd_section=ctd_section, pattern_type=pattern_type)}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/regulatory-skills/compare-metrics")
async def regulatory_skills_compare_metrics(
    afe: float = Query(..., description="Absolute fold error from PBPK validation"),
    aafe: float = Query(..., description="Absolute average fold error"),
    within_2fold: float = Query(..., description="Fraction within 2-fold (0–1)"),
    region: str = Query("EMA", description="FDA | EMA | NMPA | PMDA"),
):
    """
    Compare PBPK metrics against EMA criterion and OSP-approved benchmark range.

    Returns pass/fail verdict and comparison context from approved reports.
    """
    try:
        from .regulatory_skills_db import RegulatorySkillsDB
        db = RegulatorySkillsDB()
        return db.compare_metrics(afe=afe, aafe=aafe, within_2fold=within_2fold, region=region)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
