"""
Unified Instrument Service - Main Application

This service provides a single API for all instrument connections in bioMate.
It routes requests to the appropriate backend (SENAITE, OpenELIS, or direct parsers)
and integrates results with Galaxy workflows.
"""

import os
import logging
from typing import Dict, List, Optional
from datetime import datetime
from enum import Enum

from fastapi import FastAPI, UploadFile, File, HTTPException, Form, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
import boto3
from bioblend.galaxy import GalaxyInstance

# Configure logging
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

# Configuration
SENAITE_API_URL = os.getenv("SENAITE_API_URL", "http://senaite-api:8000")
OPENELIS_API_URL = os.getenv("OPENELIS_API_URL", "http://openelis-api:8000")
GALAXY_URL = os.getenv("GALAXY_URL", "http://galaxy:8080")
GALAXY_API_KEY = os.getenv("GALAXY_API_KEY")
S3_BUCKET = os.getenv("S3_BUCKET")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

app = FastAPI(
    title="bioMate Instrument Service",
    description="Unified API for clinical and research instrument connections",
    version="1.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# Data Models
# ============================================================================

class InstrumentBackend(str, Enum):
    """Available instrument backends"""
    SENAITE = "senaite"
    OPENELIS = "openelis"
    DIRECT = "direct"
    AUTO = "auto"


class InstrumentResult(BaseModel):
    """Normalized instrument result"""
    test_code: str
    test_name: str
    value: Optional[str]
    unit: Optional[str]
    reference_range: Optional[str]
    flags: Optional[str]
    timestamp: Optional[datetime]


class SampleResult(BaseModel):
    """Sample with results"""
    sample_id: str
    patient_id: Optional[str]
    instrument: str
    timestamp: datetime
    results: List[InstrumentResult]
    qc_status: Optional[str]
    raw_data: Optional[Dict]


class ImportResponse(BaseModel):
    """API response for import"""
    success: bool
    message: str
    samples: List[SampleResult]
    backend_used: str
    galaxy_dataset_id: Optional[str] = None
    s3_url: Optional[str] = None
    errors: List[str] = []


class InstrumentInfo(BaseModel):
    """Instrument information"""
    manufacturer: str
    model: str
    type: str
    protocol: str
    backend: str


# ============================================================================
# Backend Clients
# ============================================================================

class InstrumentOrchestrator:
    """Orchestrates requests across multiple instrument backends"""

    def __init__(self):
        self.http_client = httpx.AsyncClient(timeout=120.0)
        self.s3_client = boto3.client('s3', region_name=AWS_REGION) if S3_BUCKET else None
        self.galaxy = GalaxyInstance(GALAXY_URL, GALAXY_API_KEY) if GALAXY_API_KEY else None

        # Instrument routing map (instrument type -> preferred backend)
        self.routing_map = self._build_routing_map()

    def _build_routing_map(self) -> Dict[str, str]:
        """Build routing map based on instrument coverage"""
        return {
            # Clinical Chemistry (both support, prefer OpenELIS for core)
            "Cobas_C311": "openelis",
            "Cobas_Integra": "openelis",
            "Cobas_TaqMan": "openelis",

            # Hematology (both support, prefer SENAITE for XN features)
            "Sysmex_XN": "senaite",
            "Sysmex_XS": "senaite",
            "Sysmex_XT": "senaite",

            # Flow Cytometry (both support, prefer OpenELIS for FACS)
            "FACSCalibur": "openelis",
            "FACSCanto": "openelis",
            "Aquios_CL": "openelis",

            # Specialized (SENAITE-only)
            "Shimadzu_GCMS": "senaite",
            "Shimadzu_LCMS": "senaite",
            "Horiba_ICP": "senaite",
            "PerkinElmer_ICP": "senaite",

            # Sequencing (direct parsers - GPL-free)
            "Illumina": "direct",
            "Illumina_NovaSeq": "direct",
            "Illumina_NextSeq": "direct",
            "Illumina_MiSeq": "direct",
            "ONT": "direct",
            "ONT_MinION": "direct",
            "ONT_GridION": "direct",
            "ONT_PromethION": "direct",
            "PacBio": "direct",
            "PacBio_Sequel": "direct",
            "PacBio_Revio": "direct",
        }

    async def get_all_instruments(self) -> List[InstrumentInfo]:
        """Get combined list of all supported instruments"""
        instruments = []

        try:
            # Get from SENAITE
            senaite_response = await self.http_client.get(f"{SENAITE_API_URL}/instruments")
            if senaite_response.status_code == 200:
                senaite_instruments = senaite_response.json()
                for inst in senaite_instruments:
                    instruments.append(InstrumentInfo(**inst, backend="senaite"))

            # Get from OpenELIS
            openelis_response = await self.http_client.get(f"{OPENELIS_API_URL}/instruments")
            if openelis_response.status_code == 200:
                openelis_instruments = openelis_response.json()
                for inst in openelis_instruments:
                    instruments.append(InstrumentInfo(**inst, backend="openelis"))

        except Exception as e:
            logger.error(f"Error fetching instruments: {e}")

        return instruments

    async def import_file(
        self,
        file_content: bytes,
        filename: str,
        instrument: str,
        backend: InstrumentBackend = InstrumentBackend.AUTO,
        create_galaxy_dataset: bool = True
    ) -> ImportResponse:
        """
        Import instrument file using appropriate backend
        """
        # Determine backend
        if backend == InstrumentBackend.AUTO:
            backend_str = self.routing_map.get(instrument, "senaite")
        else:
            backend_str = backend.value

        logger.info(f"Importing {filename} via {backend_str} backend")

        try:
            # Route to appropriate backend
            if backend_str == "senaite":
                result = await self._import_via_senaite(file_content, filename, instrument)
            elif backend_str == "openelis":
                result = await self._import_via_openelis(file_content, filename, instrument)
            elif backend_str == "direct":
                result = await self._import_via_direct_parser(file_content, filename, instrument)
            else:
                raise HTTPException(400, f"Unknown backend: {backend_str}")

            # Store in S3
            s3_url = None
            if self.s3_client:
                s3_url = await self._store_in_s3(file_content, filename)

            # Create Galaxy dataset
            galaxy_dataset_id = None
            if create_galaxy_dataset and self.galaxy and result["samples"]:
                galaxy_dataset_id = await self._create_galaxy_dataset(result["samples"], filename)

            return ImportResponse(
                success=result["success"],
                message=result["message"],
                samples=result["samples"],
                backend_used=backend_str,
                galaxy_dataset_id=galaxy_dataset_id,
                s3_url=s3_url,
                errors=result.get("errors", [])
            )

        except Exception as e:
            logger.error(f"Import failed: {e}", exc_info=True)
            raise HTTPException(500, f"Import failed: {e}")

    async def _import_via_senaite(self, file_content: bytes, filename: str, instrument: str) -> Dict:
        """Import via SENAITE API"""
        files = {"file": (filename, file_content)}
        data = {"instrument": instrument}

        response = await self.http_client.post(
            f"{SENAITE_API_URL}/import",
            files=files,
            data=data
        )
        response.raise_for_status()
        return response.json()

    async def _import_via_openelis(self, file_content: bytes, filename: str, instrument: str) -> Dict:
        """Import via OpenELIS API"""
        files = {"file": (filename, file_content)}
        data = {"instrument": instrument}

        response = await self.http_client.post(
            f"{OPENELIS_API_URL}/import",
            files=files,
            data=data
        )
        response.raise_for_status()
        return response.json()

    async def _import_via_direct_parser(self, file_content: bytes, filename: str, instrument: str) -> Dict:
        """Import via direct parsers (Illumina, ONT, PacBio)"""
        import tempfile
        import os
        from ...parsers import IlluminaParser, ONTParser, PacBioParser

        # Write to temp file
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(filename)[1]) as tmp:
            tmp.write(file_content)
            tmp_path = tmp.name

        try:
            # Select parser based on instrument
            if "Illumina" in instrument:
                parser = IlluminaParser()
            elif "ONT" in instrument:
                parser = ONTParser()
            elif "PacBio" in instrument:
                parser = PacBioParser()
            else:
                raise ValueError(f"No direct parser for instrument: {instrument}")

            # Parse file
            result = parser.parse(tmp_path, max_reads=10000)  # Limit for demo

            if not result.success:
                raise Exception(f"Parser errors: {result.errors}")

            # Convert to API format
            return {
                "success": True,
                "message": f"Parsed {result.total_reads} reads",
                "samples": [
                    {
                        "sample_id": sample.sample_id,
                        "sample_name": sample.sample_name,
                        "read_count": sample.read_count,
                        "total_bases": sample.total_bases,
                        "mean_read_length": sample.mean_read_length,
                        "mean_quality": sample.mean_quality,
                        "results": [
                            {
                                "test_code": "READ_COUNT",
                                "test_name": "Total Reads",
                                "value": str(sample.read_count),
                                "unit": "reads"
                            },
                            {
                                "test_code": "TOTAL_BASES",
                                "test_name": "Total Bases",
                                "value": str(sample.total_bases),
                                "unit": "bp"
                            },
                            {
                                "test_code": "MEAN_LENGTH",
                                "test_name": "Mean Read Length",
                                "value": f"{sample.mean_read_length:.1f}",
                                "unit": "bp"
                            },
                            {
                                "test_code": "MEAN_QUALITY",
                                "test_name": "Mean Quality Score",
                                "value": f"{sample.mean_quality:.1f}",
                                "unit": "Q"
                            }
                        ]
                    }
                    for sample in result.samples
                ],
                "errors": result.errors
            }

        finally:
            # Clean up temp file
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    async def _store_in_s3(self, file_content: bytes, filename: str) -> str:
        """Store file in S3 for audit trail"""
        try:
            key = f"instruments/{datetime.now().strftime('%Y/%m/%d')}/{filename}"
            self.s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=key,
                Body=file_content,
                ServerSideEncryption='AES256'
            )
            return f"s3://{S3_BUCKET}/{key}"
        except Exception as e:
            logger.error(f"S3 storage failed: {e}")
            return None

    async def _create_galaxy_dataset(self, samples: List[SampleResult], filename: str) -> str:
        """Create Galaxy dataset from instrument results"""
        try:
            # Get or create history
            histories = self.galaxy.histories.get_histories()
            if not histories:
                history = self.galaxy.histories.create_history(name="Instrument Data")
            else:
                history = histories[0]

            # Convert samples to JSON
            import json
            data_json = json.dumps([s.dict() for s in samples], indent=2, default=str)

            # Upload to Galaxy
            dataset = self.galaxy.histories.upload_file(
                history['id'],
                data_json,
                file_name=f"{filename}_parsed.json",
                file_type="json"
            )

            logger.info(f"Created Galaxy dataset: {dataset['id']}")
            return dataset['id']

        except Exception as e:
            logger.error(f"Galaxy dataset creation failed: {e}")
            return None


# Global orchestrator
orchestrator = InstrumentOrchestrator()


# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    backends_status = {}

    # Check SENAITE
    try:
        response = await orchestrator.http_client.get(f"{SENAITE_API_URL}/health", timeout=5.0)
        backends_status["senaite"] = "healthy" if response.status_code == 200 else "unhealthy"
    except:
        backends_status["senaite"] = "unreachable"

    # Check OpenELIS
    try:
        response = await orchestrator.http_client.get(f"{OPENELIS_API_URL}/health", timeout=5.0)
        backends_status["openelis"] = "healthy" if response.status_code == 200 else "unhealthy"
    except:
        backends_status["openelis"] = "unreachable"

    # Check Galaxy
    backends_status["galaxy"] = "connected" if orchestrator.galaxy else "not_configured"

    # Check S3
    backends_status["s3"] = "configured" if orchestrator.s3_client else "not_configured"

    overall_status = "healthy" if any(s == "healthy" for s in backends_status.values()) else "degraded"

    return {
        "status": overall_status,
        "backends": backends_status,
        "service": "instrument-orchestrator",
        "version": "1.0.0"
    }


@app.get("/instruments", response_model=List[InstrumentInfo])
async def list_all_instruments():
    """
    List all supported instruments across all backends

    Returns combined list from SENAITE (60+) and OpenELIS (13+)
    """
    try:
        instruments = await orchestrator.get_all_instruments()
        logger.info(f"Found {len(instruments)} total instruments")
        return instruments
    except Exception as e:
        logger.error(f"Failed to list instruments: {e}")
        raise HTTPException(500, f"Failed to list instruments: {e}")


@app.post("/import", response_model=ImportResponse)
async def import_instrument_file(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    instrument: str = Form(...),
    backend: InstrumentBackend = Form(InstrumentBackend.AUTO),
    sample_id: Optional[str] = Form(None),
    create_galaxy_dataset: bool = Form(True)
):
    """
    Import instrument results file

    This is the main entry point for all instrument imports.
    Routes to appropriate backend automatically or by specification.

    Args:
        file: Instrument results file
        instrument: Instrument type (e.g., "Cobas_C311", "Sysmex_XN", "Illumina")
        backend: Backend to use (auto, senaite, openelis, direct)
        sample_id: Optional sample ID filter
        create_galaxy_dataset: Whether to create Galaxy dataset

    Returns:
        Parsed results, Galaxy dataset ID, and S3 URL
    """
    try:
        logger.info(f"Importing {file.filename}: instrument={instrument}, backend={backend}")

        # Read file
        content = await file.read()

        # Import via orchestrator
        result = await orchestrator.import_file(
            content,
            file.filename,
            instrument,
            backend,
            create_galaxy_dataset
        )

        logger.info(f"Import successful: {len(result.samples)} samples, backend={result.backend_used}")

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Import failed: {e}", exc_info=True)
        raise HTTPException(500, f"Import failed: {e}")


@app.get("/backends")
async def list_backends():
    """List available instrument backends and their status"""
    return {
        "senaite": {
            "name": "SENAITE",
            "instruments": "60+",
            "license": "GPL-2.0 (network-isolated)",
            "url": SENAITE_API_URL,
            "status": "available"
        },
        "openelis": {
            "name": "OpenELIS Global 2",
            "instruments": "13+",
            "license": "MPL-2.0 (commercial-friendly)",
            "url": OPENELIS_API_URL,
            "status": "available"
        },
        "direct": {
            "name": "Direct Parsers",
            "instruments": "3 (Illumina, Roche, Sysmex)",
            "license": "MIT (proprietary)",
            "status": "planned"
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
