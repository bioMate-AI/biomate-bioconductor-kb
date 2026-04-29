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

  GET  /api/drug-discovery/{campaign_id}/lims/poll
       Poll Benchling LIMS for new assay data and ingest any new results.

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

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
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
    conn.commit()
    return conn


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
async def register_model(
    campaign_id: str,
    body: RegisterModelRequest,
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
    _audit: None = Depends(_audit_fn),
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
# Track F — Bayesian Optimizer propose (G7 gap closure)
# ---------------------------------------------------------------------------

class ProposeRequest(BaseModel):
    virtual_library_smiles: list[str]
    n_propose: int = 10
    diversity_weight: float = 0.2


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
        proposed_smiles: selected SMILES,
        proposed_scores: surrogate predicted scores per objective,
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
        svc = AssayIngestionService(_campaign_db(campaign_id))
        ranked = svc.get_ranked_compounds(campaign_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to load campaign data: {exc}")

    if not ranked:
        raise HTTPException(
            status_code=404,
            detail=f"No assay data for campaign '{campaign_id}'. "
                   "Upload results first via POST /{campaign_id}/ingest-assay."
        )

    try:
        import numpy as np
        from .bayesian_optimizer import CampaignDataset

        smiles_list = [r["smiles"] for r in ranked if r.get("smiles")]
        scores_list = [min(1.0, max(0.0, r.get("composite_score", 0.5))) for r in ranked]
        compound_ids = [r.get("compound_id", f"c{i}") for i, r in enumerate(ranked)]

        opt = BayesianOptimizer(campaign_id=campaign_id, db_path=_campaign_db(campaign_id))
        features = opt._featurise(smiles_list)
        dataset = CampaignDataset(
            compound_ids=compound_ids,
            smiles_list=smiles_list,
            features=features,
            objectives={"composite_score": np.array(scores_list)},
            objective_directions={"composite_score": "maximize"},
        )
        opt.fit(dataset)
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

    return {
        "campaign_id": campaign_id,
        "n_proposed": len(proposal.proposed_compounds),
        "proposed_smiles": proposal.proposed_compounds,
        "predicted_scores": proposal.scores,
        "confidence_intervals": proposal.confidence_intervals,
        "ad_statuses": proposal.ad_statuses,
        "gp_stds": proposal.gp_stds,
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

@router.get("/{campaign_id}/lims/poll")
async def poll_lims(
    campaign_id: str,
    benchling_api_key: str = Query(None, description="Benchling API key (overrides env BENCHLING_API_KEY)"),
    assay_schema_id: str   = Query(None, description="Benchling assay schema ID to poll"),
    since_hours: float     = Query(24.0, description="Look back N hours for new results"),
    _audit: None = Depends(_audit_fn),
):
    """
    Poll Benchling LIMS for new assay results and ingest them into the
    campaign compound ranking.

    The Benchling API key can be supplied via query param (for dev) or the
    BENCHLING_API_KEY environment variable (for production).

    Returns a summary of ingested records and updated compound ranks.
    """
    try:
        from .benchling_connector import BenchlingConnector
        from .assay_ingestion import AssayIngestionService
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    api_key = benchling_api_key or os.environ.get("BENCHLING_API_KEY", "")
    if not api_key:
        raise HTTPException(
            status_code=400,
            detail="Benchling API key required. Pass benchling_api_key query param "
                   "or set BENCHLING_API_KEY env var."
        )

    try:
        connector = BenchlingConnector(api_key=api_key)
        new_results = connector.list_assay_results(
            schema_id=assay_schema_id,
            since_hours=since_hours,
        )
    except Exception as exc:
        log.exception("Benchling LIMS poll failed for campaign %s", campaign_id)
        raise HTTPException(status_code=502, detail=f"Benchling API error: {exc}")

    if not new_results:
        return {
            "campaign_id": campaign_id,
            "status": "no_new_data",
            "records_ingested": 0,
            "message": f"No new Benchling results in the last {since_hours}h",
        }

    # Convert Benchling results to AssayIngestionService-compatible CSV rows
    import io, csv as csv_module, tempfile

    fieldnames = list(new_results[0].keys()) if new_results else ["compound_id", "smiles"]
    buf = io.StringIO()
    writer = csv_module.DictWriter(buf, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(new_results)
    csv_bytes = buf.getvalue().encode()

    try:
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            tmp.write(csv_bytes)
            tmp_path = tmp.name

        svc = AssayIngestionService(_campaign_db(campaign_id))
        result = svc.ingest(campaign_id, tmp_path)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Ingestion error: {exc}")
    finally:
        import os as _os
        try: _os.unlink(tmp_path)
        except: pass

    return {
        "campaign_id": campaign_id,
        "status": "ingested",
        "records_ingested": len(new_results),
        "ingestion_result": {
            "compounds_updated": result.compounds_updated if hasattr(result, "compounds_updated") else len(new_results),
            "new_compounds": result.new_compounds if hasattr(result, "new_compounds") else 0,
        },
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


@router.get("/{campaign_id}/auto-proposal")
async def get_auto_proposal(
    campaign_id: str,
    format: str = Query("json", regex="^(json|csv)$"),
):
    """
    Return the latest auto-retrain proposal for a campaign.

    Returns the Proposal shape expected by DrugDiscoveryAutoRetrain:
      { round, generated_at, trigger, items: [{rank, smiles, score, ci_lo, ci_hi, ad}] }

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
        writer = _csv.DictWriter(buf, fieldnames=["rank", "smiles", "score", "ci_lo", "ci_hi", "ad"])
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
        from .auto_retrain import refit_and_propose, start_background_loop
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    db_path = _campaign_db(campaign_id)

    try:
        proposal = refit_and_propose(db_path, campaign_id, triggered_by="manual")
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
        "ad_statuses": proposal.ad_statuses,
        "created_at": proposal.created_at,
    }


# ---------------------------------------------------------------------------
# Phase 3b — IND section assembly
# ---------------------------------------------------------------------------

class INDAssemblyRequest(BaseModel):
    molecule_name: str = "Investigational Compound"
    sponsor: str = "Sponsor"
    indication: str = "Investigational indication"
    target_name: str = "Investigational target"
    pk_summary: Optional[dict] = None  # pk_summary.json from predict_admet_properties run


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
    """
    try:
        from .ind_assembly import INDSectionAssembler
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    import tempfile
    output_dir = tempfile.mkdtemp(prefix=f"biomate_ind_{campaign_id}_")

    # Store pk_summary if provided, so it persists for future assemblies
    if body.pk_summary:
        try:
            _store_pk_summary(_campaign_db(campaign_id), campaign_id, body.pk_summary)
        except Exception as exc:
            log.warning("Failed to store pk_summary for campaign %s: %s", campaign_id, exc)

    try:
        assembler = INDSectionAssembler(_campaign_db(campaign_id))
        result = assembler.assemble(
            campaign_id=campaign_id,
            output_dir=output_dir,
            molecule_name=body.molecule_name,
            sponsor=body.sponsor,
            indication=body.indication,
            target_name=body.target_name,
            pk_summary=body.pk_summary,
        )
    except Exception as exc:
        log.exception("IND assembly failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=str(exc))

    # Read Markdown content to return inline
    markdown_content = Path(result.markdown_path).read_text(encoding="utf-8")

    # Cache for download endpoint
    _ind_cache[campaign_id] = {
        "markdown_path": result.markdown_path,
        "docx_path": result.docx_path,
        "markdown_content": markdown_content,
    }

    return {
        "campaign_id": campaign_id,
        "sections": result.sections,
        "pandoc_available": result.pandoc_available,
        "docx_generated": result.docx_path is not None,
        "generated_at": result.generated_at,
        "warnings": result.warnings,
        "markdown_preview": markdown_content[:2000],
        "markdown_content": markdown_content,
        "markdown_path": result.markdown_path,
        "docx_path": result.docx_path,
    }


@router.get("/{campaign_id}/ind-assembly/download")
async def download_ind_file(
    campaign_id: str,
    format: str = Query("md", regex="^(md|docx)$"),
):
    """
    Download the last generated IND assembly file (Markdown or DOCX).
    Serves from the in-memory cache populated by the POST endpoint.
    """
    from fastapi.responses import FileResponse, PlainTextResponse

    cached = _ind_cache.get(campaign_id)
    if not cached:
        raise HTTPException(status_code=404, detail="No IND assembly found for this campaign. Generate first.")

    if format == "docx":
        docx_path = cached.get("docx_path")
        if not docx_path or not Path(docx_path).exists():
            raise HTTPException(status_code=404, detail="DOCX not available — pandoc may not be installed.")
        return FileResponse(
            docx_path,
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            filename=f"{campaign_id}_CTD_2.6.1.docx",
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
        return PlainTextResponse(
            content,
            media_type="text/markdown; charset=utf-8",
            headers={"Content-Disposition": f'attachment; filename="{campaign_id}_CTD_Module2.6.md"'},
        )


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
      { round, generated_at, trigger, items: [{rank, smiles, score, ci_lo, ci_hi, ad}] }
    """
    try:
        from .auto_retrain import refit_and_propose, start_background_loop
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    db_path = _campaign_db(campaign_id)
    proposal = refit_and_propose(db_path, campaign_id, triggered_by="manual")

    if proposal is None:
        raise HTTPException(
            status_code=422,
            detail=(
                "Retrain requires assay data and a cached virtual library. "
                "Call POST /{campaign_id}/virtual-library first."
            ),
        )

    start_background_loop(db_path, campaign_id)

    # Submit ADMET screening Nextflow workflow for the proposed SMILES
    nf_run_id: Optional[str] = None
    try:
        import json as _json
        import urllib.request as _urllib
        proposed_smiles = [item.get("smiles", "") for item in (proposal.items or []) if item.get("smiles")]
        if proposed_smiles:
            _nf_port = int(os.environ.get("NEXTFLOW_EXECUTOR_PORT", "8082"))
            _nf_url = f"http://localhost:{_nf_port}/api/nextflow/run"
            _payload = _json.dumps({
                "workflow_id": "admet_screening",
                "params": {
                    "smiles_list": ",".join(proposed_smiles[:20]),
                    "campaign_id": campaign_id,
                    "n_compounds": len(proposed_smiles[:20]),
                },
                "tags": {"campaign_id": campaign_id, "trigger": "auto_retrain"},
            }).encode()
            _req = _urllib.Request(_nf_url, data=_payload, headers={"Content-Type": "application/json"}, method="POST")
            with _urllib.urlopen(_req, timeout=5) as _resp:
                _resp_data = _json.loads(_resp.read())
                nf_run_id = _resp_data.get("run_id")
    except Exception as _exc:
        log.info("ADMET Nextflow submit skipped (executor not reachable): %s", _exc)

    result = _format_proposal(proposal)
    if nf_run_id:
        result["nf_run_id"] = nf_run_id
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


@router.post("/{campaign_id}/retrain")
async def trigger_retrain_post_legacy(
    campaign_id: str,
    _audit: None = Depends(_audit_fn),
):
    """Deprecated legacy path — delegates to /retrain/trigger."""
    return await trigger_retrain_now(campaign_id, _audit)


def _format_proposal(proposal) -> dict:
    """
    Shape an AutoProposal into the Proposal contract expected by the frontend:
      { round, generated_at, trigger, items: [{rank, smiles, score, ci_lo, ci_hi, ad}] }
    """
    smiles = proposal.proposed_smiles
    scores = proposal.scores  # dict keyed by smiles or list
    ci = proposal.confidence_intervals
    ad = proposal.ad_statuses  # list parallel to smiles

    # Normalise scores to a list aligned with smiles
    if isinstance(scores, dict):
        score_list = [float(scores.get(s, 0.0)) for s in smiles]
    elif isinstance(scores, list):
        score_list = [float(v) for v in scores]
    else:
        score_list = [0.0] * len(smiles)

    # Normalise CI: may be dict-of-lists {"lo": [...], "hi": [...]} or list-of-dicts
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
            "ci_lo":   ci_lo_list[i] if i < len(ci_lo_list) else 0.0,
            "ci_hi":   ci_hi_list[i] if i < len(ci_hi_list) else 1.0,
            "ad":      ad_list[i] if i < len(ad_list) else "in_domain",
        })

    return {
        "round":        proposal.round_number,
        "generated_at": proposal.created_at,
        "trigger":      proposal.triggered_by,
        "items":        items,
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
        svc._ensure_schema()
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
                (campaign_id, user_id, molecule_name, target, indication, sponsor, objective, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except Exception as exc:
        log.exception("eSig signing failed for campaign %s", campaign_id)
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "sig_id": sig.sig_id,
        "signed_at": sig.signed_at,
        "action": sig.action,
        "meaning": sig.meaning,
    }
