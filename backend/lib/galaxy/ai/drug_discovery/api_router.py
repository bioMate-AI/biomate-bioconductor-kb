"""
BioMate Drug Discovery API Router (FastAPI)

Endpoints:
  POST /api/drug-discovery/{campaign_id}/ingest-assay
       Upload a CRO/wet-lab assay CSV; updates compound ranking.

  GET  /api/drug-discovery/{campaign_id}/compounds
       Return current compound ranking for a campaign.

  GET  /api/drug-discovery/{campaign_id}/export/cro-order
       Export current proposal as WuXi / Pharmaron / Enamine CSV.

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

from fastapi import APIRouter, File, HTTPException, Query, UploadFile
from pydantic import BaseModel

log = logging.getLogger(__name__)

router = APIRouter(prefix="/api/drug-discovery", tags=["drug_discovery"])

# Per-campaign SQLite databases live in this directory.
_CAMPAIGN_DB_DIR = os.environ.get(
    "BIOMATE_CAMPAIGN_DB_DIR",
    str(Path(__file__).parent.parent.parent.parent.parent / "database" / "campaigns"),
)


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
    updated_ranks: list[dict]
    newly_failed: list[str]
    newly_passed: list[str]


@router.post("/{campaign_id}/ingest-assay", response_model=IngestAssayResponse)
async def ingest_assay(
    campaign_id: str,
    file: UploadFile = File(..., description="Assay CSV file"),
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
        svc = AssayIngestionService(_campaign_db(campaign_id))
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
        svc = AssayIngestionService(_campaign_db(campaign_id))
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
        svc = AssayIngestionService(_campaign_db(campaign_id))
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
async def register_model(campaign_id: str, body: RegisterModelRequest):
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
        from .custom_model_registry import CustomModelRegistry
        from .custom_model_wrapper import DockerModelWrapper, RESTModelWrapper
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        registry = CustomModelRegistry(_campaign_db(campaign_id))

        if body.mode == "docker":
            if not body.image:
                raise HTTPException(status_code=400, detail="image required for docker mode")
            wrapper = DockerModelWrapper(
                name=body.name,
                campaign_id=campaign_id,
                image=body.image,
                command=body.command or [],
                higher_is_better=body.higher_is_better,
            )
        elif body.mode == "rest":
            if not body.endpoint:
                raise HTTPException(status_code=400, detail="endpoint required for rest mode")
            wrapper = RESTModelWrapper(
                name=body.name,
                campaign_id=campaign_id,
                endpoint=body.endpoint,
                input_field=body.input_field or "smiles",
                output_field=body.output_field or "score",
                timeout_s=body.timeout_s or 30,
                higher_is_better=body.higher_is_better,
            )
        else:
            raise HTTPException(
                status_code=400,
                detail="mode must be 'docker' or 'rest' (python_function requires server-side registration)",
            )

        registry.register(wrapper)
    except HTTPException:
        raise
    except Exception as exc:
        log.exception("model registration failed")
        raise HTTPException(status_code=500, detail=str(exc))

    return {"status": "registered", "campaign_id": campaign_id, "model_name": body.name, "mode": body.mode}


@router.get("/{campaign_id}/models")
async def list_models(campaign_id: str):
    """List registered models and their run history for a campaign."""
    try:
        from .custom_model_registry import CustomModelRegistry
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    try:
        registry = CustomModelRegistry(_campaign_db(campaign_id))
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
):
    """
    Run a registered model against a list of SMILES.

    If smiles_list is omitted, runs against all compounds in the campaign DB.
    Returns per-compound scores and a run record for the audit log.
    """
    try:
        from .custom_model_registry import CustomModelRegistry
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    if not smiles_list:
        try:
            svc = AssayIngestionService(_campaign_db(campaign_id))
            ranks = svc.get_compound_ranks(campaign_id)
            smiles_list = [r["smiles"] for r in ranks if r.get("smiles")]
        except Exception as exc:
            raise HTTPException(status_code=500, detail=str(exc))

    if not smiles_list:
        raise HTTPException(status_code=404, detail="No SMILES available; upload assay data first.")

    try:
        registry = CustomModelRegistry(_campaign_db(campaign_id))
        scores, run_record = registry.run_named_model(campaign_id, model_name, smiles_list)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"Model '{model_name}' not registered for campaign '{campaign_id}'")
    except Exception as exc:
        log.exception("model run failed")
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "campaign_id": campaign_id,
        "model_name": model_name,
        "scores": scores,
        "run_record": run_record.__dict__ if hasattr(run_record, "__dict__") else str(run_record),
    }


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
