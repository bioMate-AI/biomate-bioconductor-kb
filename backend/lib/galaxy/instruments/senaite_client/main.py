"""
SENAITE API Wrapper - Main Application

This FastAPI application wraps SENAITE's instrument parsing capabilities
with a clean REST API. GPL-2.0 isolation is maintained through network boundaries.

NO SENAITE CODE IS IMPORTED OR LINKED.
"""

import os
import logging
from typing import Dict, List, Optional
from datetime import datetime

from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx

# Configure logging
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

# SENAITE connection (via HTTP only)
SENAITE_URL = os.getenv("SENAITE_URL", "http://senaite:8080")
SENAITE_USERNAME = os.getenv("SENAITE_USERNAME", "admin")
SENAITE_PASSWORD = os.getenv("SENAITE_PASSWORD", "admin")

app = FastAPI(
    title="SENAITE API Wrapper",
    description="GPL-isolated REST API for SENAITE instrument parsing",
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
    errors: List[str] = []


class SupportedInstrument(BaseModel):
    """Supported instrument info"""
    manufacturer: str
    model: str
    type: str
    protocol: str


# ============================================================================
# SENAITE HTTP Client
# ============================================================================

class SENAITEClient:
    """HTTP client for SENAITE (no code imports, GPL-safe)"""

    def __init__(self):
        self.base_url = SENAITE_URL
        self.username = SENAITE_USERNAME
        self.password = SENAITE_PASSWORD
        self.client = httpx.AsyncClient(timeout=60.0)

    async def authenticate(self) -> str:
        """Get authentication token from SENAITE"""
        try:
            response = await self.client.post(
                f"{self.base_url}/@@API/senaite/v1/login",
                json={
                    "username": self.username,
                    "password": self.password
                }
            )
            response.raise_for_status()
            data = response.json()
            return data.get("token", "")
        except Exception as e:
            logger.error(f"SENAITE authentication failed: {e}")
            raise HTTPException(500, f"SENAITE authentication failed: {e}")

    async def import_results(self, file_content: bytes, filename: str, instrument_type: str) -> Dict:
        """
        Import instrument results via SENAITE API

        This is a NETWORK API CALL - no GPL code linking
        """
        try:
            # Get auth token
            token = await self.authenticate()

            # Upload file to SENAITE
            files = {
                "file": (filename, file_content, "application/octet-stream")
            }
            data = {
                "instrument": instrument_type,
                "format": "auto"  # Auto-detect format
            }
            headers = {
                "Authorization": f"Bearer {token}"
            }

            response = await self.client.post(
                f"{self.base_url}/@@API/senaite/v1/import_results",
                files=files,
                data=data,
                headers=headers
            )
            response.raise_for_status()
            return response.json()

        except httpx.HTTPStatusError as e:
            logger.error(f"SENAITE API error: {e.response.status_code} - {e.response.text}")
            raise HTTPException(e.response.status_code, f"SENAITE error: {e.response.text}")
        except Exception as e:
            logger.error(f"SENAITE import failed: {e}")
            raise HTTPException(500, f"Import failed: {e}")

    async def get_supported_instruments(self) -> List[Dict]:
        """Get list of supported instruments from SENAITE"""
        try:
            token = await self.authenticate()
            headers = {"Authorization": f"Bearer {token}"}

            response = await self.client.get(
                f"{self.base_url}/@@API/senaite/v1/instruments",
                headers=headers
            )
            response.raise_for_status()
            return response.json().get("instruments", [])

        except Exception as e:
            logger.error(f"Failed to get instruments: {e}")
            return []


# Global client instance
senaite_client = SENAITEClient()


# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Verify SENAITE is accessible
        response = await senaite_client.client.get(f"{SENAITE_URL}/senaite")
        return {
            "status": "healthy",
            "senaite_status": "connected" if response.status_code == 200 else "unreachable",
            "service": "senaite-api-wrapper",
            "version": "1.0.0"
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "service": "senaite-api-wrapper"
        }


@app.get("/instruments", response_model=List[SupportedInstrument])
async def list_supported_instruments():
    """
    List all instruments supported by SENAITE (60+ instruments)

    This queries SENAITE via REST API (GPL-safe)
    """
    try:
        instruments = await senaite_client.get_supported_instruments()

        # If SENAITE doesn't provide API, return known list
        if not instruments:
            instruments = KNOWN_SENAITE_INSTRUMENTS

        return instruments
    except Exception as e:
        logger.error(f"Failed to list instruments: {e}")
        raise HTTPException(500, f"Failed to list instruments: {e}")


@app.post("/import", response_model=ImportResponse)
async def import_instrument_file(
    file: UploadFile = File(...),
    instrument: str = Form(...),
    sample_id: Optional[str] = Form(None)
):
    """
    Import instrument results file via SENAITE

    This is the main endpoint for importing instrument data.
    GPL ISOLATION: File is sent to SENAITE via HTTP POST (network boundary)

    Args:
        file: Instrument results file
        instrument: Instrument type (e.g., "Cobas_C311", "Sysmex_XN")
        sample_id: Optional sample ID filter

    Returns:
        Parsed and normalized results
    """
    try:
        logger.info(f"Importing file: {file.filename}, instrument: {instrument}")

        # Read file content
        content = await file.read()

        # Send to SENAITE via HTTP (GPL-safe)
        raw_results = await senaite_client.import_results(content, file.filename, instrument)

        # Normalize results to bioMate format
        normalized = normalize_senaite_results(raw_results, instrument)

        # Filter by sample_id if provided
        if sample_id:
            normalized["samples"] = [
                s for s in normalized["samples"]
                if s["sample_id"] == sample_id
            ]

        logger.info(f"Successfully imported {len(normalized['samples'])} samples")

        return ImportResponse(
            success=True,
            message=f"Imported {len(normalized['samples'])} samples",
            samples=normalized["samples"],
            errors=normalized.get("errors", [])
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Import failed: {e}", exc_info=True)
        raise HTTPException(500, f"Import failed: {e}")


# ============================================================================
# Helper Functions
# ============================================================================

def normalize_senaite_results(raw_data: Dict, instrument: str) -> Dict:
    """
    Normalize SENAITE response to bioMate format

    This function only processes JSON data - no GPL code involved
    """
    samples = []
    errors = []

    try:
        # SENAITE returns data in various formats depending on instrument
        # Parse the response and normalize

        if "samples" in raw_data:
            for sample_data in raw_data["samples"]:
                results = []

                for result_data in sample_data.get("results", []):
                    results.append(InstrumentResult(
                        test_code=result_data.get("keyword", ""),
                        test_name=result_data.get("title", ""),
                        value=result_data.get("result"),
                        unit=result_data.get("unit"),
                        reference_range=result_data.get("specification"),
                        flags=result_data.get("result_flag"),
                        timestamp=result_data.get("result_date")
                    ))

                samples.append(SampleResult(
                    sample_id=sample_data.get("id", ""),
                    patient_id=sample_data.get("client_sample_id"),
                    instrument=instrument,
                    timestamp=datetime.now(),
                    results=results,
                    qc_status=sample_data.get("review_state"),
                    raw_data=sample_data
                ))

        # Handle errors
        if "errors" in raw_data:
            errors = raw_data["errors"]

    except Exception as e:
        logger.error(f"Normalization error: {e}")
        errors.append(f"Normalization error: {e}")

    return {
        "samples": samples,
        "errors": errors
    }


# Known SENAITE instruments (fallback if API doesn't provide)
KNOWN_SENAITE_INSTRUMENTS = [
    # Chemistry
    {"manufacturer": "Roche", "model": "Cobas Integra 400 Plus", "type": "Chemistry", "protocol": "File"},
    {"manufacturer": "Roche", "model": "Cobas C311", "type": "Chemistry", "protocol": "File"},
    {"manufacturer": "Beckman Coulter", "model": "Access 2", "type": "Immunoassay", "protocol": "File"},
    {"manufacturer": "ThermoScientific", "model": "Gallery Ts9861x", "type": "Chemistry", "protocol": "File"},
    {"manufacturer": "ThermoScientific", "model": "Arena XT20", "type": "Chemistry", "protocol": "File"},
    {"manufacturer": "ThermoScientific", "model": "Multiskan GO", "type": "Microplate", "protocol": "File"},

    # Hematology
    {"manufacturer": "Sysmex", "model": "XN Series", "type": "Hematology", "protocol": "File/ASTM"},
    {"manufacturer": "Sysmex", "model": "XS Series", "type": "Hematology", "protocol": "File"},
    {"manufacturer": "Sysmex", "model": "XT Series", "type": "Hematology", "protocol": "File"},
    {"manufacturer": "Scil", "model": "ABC Plus", "type": "Hematology", "protocol": "File"},

    # Molecular
    {"manufacturer": "Roche", "model": "Cobas TaqMan", "type": "PCR", "protocol": "File"},
    {"manufacturer": "Cepheid", "model": "GeneXpert", "type": "PCR", "protocol": "File"},

    # Flow Cytometry
    {"manufacturer": "BD", "model": "FACSCalibur", "type": "Flow Cytometry", "protocol": "File"},
    {"manufacturer": "BD", "model": "FACSCanto", "type": "Flow Cytometry", "protocol": "File"},
    {"manufacturer": "Beckman Coulter", "model": "Aquios CL", "type": "Flow Cytometry", "protocol": "ASTM"},

    # ICP/Spectrometry
    {"manufacturer": "Horiba", "model": "Jobin Yvon ICP", "type": "ICP-MS", "protocol": "File"},
    {"manufacturer": "Varian", "model": "Vista Pro ICP", "type": "ICP-OES", "protocol": "File"},
    {"manufacturer": "PerkinElmer", "model": "Nexion 350X", "type": "ICP-MS", "protocol": "File"},

    # Chromatography
    {"manufacturer": "Shimadzu", "model": "GCMS-QP2010 SE", "type": "GC-MS", "protocol": "File"},
    {"manufacturer": "Shimadzu", "model": "GCMS-TQ8030", "type": "GC-MS/MS", "protocol": "File"},
    {"manufacturer": "Shimadzu", "model": "LCMS-8050", "type": "LC-MS/MS", "protocol": "File"},
    {"manufacturer": "Shimadzu", "model": "Nexera LC-2040C", "type": "HPLC", "protocol": "File"},

    # And 40+ more...
]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
