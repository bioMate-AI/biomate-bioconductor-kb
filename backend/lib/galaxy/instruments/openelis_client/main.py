"""
OpenELIS API Wrapper - Main Application

This FastAPI application wraps OpenELIS's instrument parsing capabilities
with a clean REST API. MPL-2.0 licensed (commercial-friendly).
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

# OpenELIS connection
OPENELIS_URL = os.getenv("OPENELIS_URL", "http://openelis:8080")
OPENELIS_USERNAME = os.getenv("OPENELIS_USERNAME", "admin")
OPENELIS_PASSWORD = os.getenv("OPENELIS_PASSWORD", "adminADMIN!")

app = FastAPI(
    title="OpenELIS API Wrapper",
    description="REST API for OpenELIS instrument parsing (MPL-2.0)",
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
# Data Models (Same as SENAITE for consistency)
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
# OpenELIS HTTP Client
# ============================================================================

class OpenELISClient:
    """HTTP client for OpenELIS"""

    def __init__(self):
        self.base_url = OPENELIS_URL
        self.username = OPENELIS_USERNAME
        self.password = OPENELIS_PASSWORD
        self.client = httpx.AsyncClient(timeout=60.0)
        self.session_id = None

    async def authenticate(self) -> str:
        """Authenticate with OpenELIS and get session"""
        try:
            response = await self.client.post(
                f"{self.base_url}/OpenELIS-Global/LoginServlet",
                data={
                    "loginName": self.username,
                    "password": self.password
                },
                follow_redirects=True
            )
            response.raise_for_status()

            # Extract session cookie
            cookies = response.cookies
            self.session_id = cookies.get("JSESSIONID", "")
            return self.session_id

        except Exception as e:
            logger.error(f"OpenELIS authentication failed: {e}")
            raise HTTPException(500, f"OpenELIS authentication failed: {e}")

    async def import_results(self, file_content: bytes, filename: str, instrument_type: str) -> Dict:
        """
        Import instrument results via OpenELIS API
        """
        try:
            # Authenticate if needed
            if not self.session_id:
                await self.authenticate()

            # Prepare file upload
            files = {
                "file": (filename, file_content, "application/octet-stream")
            }
            data = {
                "analyzerType": instrument_type
            }
            cookies = {"JSESSIONID": self.session_id}

            # Upload to OpenELIS analyzer import endpoint
            response = await self.client.post(
                f"{self.base_url}/OpenELIS-Global/api/importAnalyzer",
                files=files,
                data=data,
                cookies=cookies
            )
            response.raise_for_status()

            return response.json()

        except httpx.HTTPStatusError as e:
            logger.error(f"OpenELIS API error: {e.response.status_code} - {e.response.text}")
            raise HTTPException(e.response.status_code, f"OpenELIS error: {e.response.text}")
        except Exception as e:
            logger.error(f"OpenELIS import failed: {e}")
            raise HTTPException(500, f"Import failed: {e}")

    async def get_supported_instruments(self) -> List[Dict]:
        """Get list of supported instruments from OpenELIS"""
        # OpenELIS has a fixed set of core analyzers
        return OPENELIS_CORE_INSTRUMENTS


# Global client instance
openelis_client = OpenELISClient()


# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Verify OpenELIS is accessible
        response = await openelis_client.client.get(f"{OPENELIS_URL}/OpenELIS-Global")
        return {
            "status": "healthy",
            "openelis_status": "connected" if response.status_code == 200 else "unreachable",
            "service": "openelis-api-wrapper",
            "version": "1.0.0"
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "service": "openelis-api-wrapper"
        }


@app.get("/instruments", response_model=List[SupportedInstrument])
async def list_supported_instruments():
    """
    List all instruments supported by OpenELIS (13+ core instruments)
    """
    try:
        instruments = await openelis_client.get_supported_instruments()
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
    Import instrument results file via OpenELIS

    Args:
        file: Instrument results file
        instrument: Instrument type (e.g., "CobasC311", "SysmexXN")
        sample_id: Optional sample ID filter

    Returns:
        Parsed and normalized results
    """
    try:
        logger.info(f"Importing file: {file.filename}, instrument: {instrument}")

        # Read file content
        content = await file.read()

        # Send to OpenELIS
        raw_results = await openelis_client.import_results(content, file.filename, instrument)

        # Normalize results to bioMate format
        normalized = normalize_openelis_results(raw_results, instrument)

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

def normalize_openelis_results(raw_data: Dict, instrument: str) -> Dict:
    """
    Normalize OpenELIS response to bioMate format
    """
    samples = []
    errors = []

    try:
        # OpenELIS returns imported results
        if "tests" in raw_data:
            # Group by sample
            samples_dict = {}

            for test_data in raw_data["tests"]:
                sample_id = test_data.get("accessionNumber", "")

                if sample_id not in samples_dict:
                    samples_dict[sample_id] = {
                        "sample_id": sample_id,
                        "patient_id": test_data.get("patientId"),
                        "results": []
                    }

                # Add result
                samples_dict[sample_id]["results"].append(InstrumentResult(
                    test_code=test_data.get("testCode", ""),
                    test_name=test_data.get("testName", ""),
                    value=test_data.get("result"),
                    unit=test_data.get("units"),
                    reference_range=test_data.get("referenceRange"),
                    flags=test_data.get("abnormalFlag"),
                    timestamp=test_data.get("completedDate")
                ))

            # Convert to list
            for sample_id, sample_data in samples_dict.items():
                samples.append(SampleResult(
                    sample_id=sample_id,
                    patient_id=sample_data["patient_id"],
                    instrument=instrument,
                    timestamp=datetime.now(),
                    results=sample_data["results"],
                    qc_status="imported",
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


# OpenELIS Core Instruments
OPENELIS_CORE_INSTRUMENTS = [
    {"manufacturer": "Roche", "model": "Cobas C311", "type": "Chemistry", "protocol": "File"},
    {"manufacturer": "Roche", "model": "Cobas Integra", "type": "Chemistry", "protocol": "File"},
    {"manufacturer": "Roche", "model": "Cobas TaqMan", "type": "Molecular (PCR)", "protocol": "File"},
    {"manufacturer": "Roche", "model": "Cobas TaqMan DBS", "type": "Molecular (DBS)", "protocol": "File"},
    {"manufacturer": "Bio-Rad", "model": "Evolis", "type": "Immunology", "protocol": "File"},
    {"manufacturer": "BD Biosciences", "model": "FACSCalibur", "type": "Flow Cytometry", "protocol": "File"},
    {"manufacturer": "BD Biosciences", "model": "FACSCanto", "type": "Flow Cytometry", "protocol": "File"},
    {"manufacturer": "Sysmex", "model": "XN Series", "type": "Hematology", "protocol": "File"},
    {"manufacturer": "Beckman Coulter", "model": "Aquios CL", "type": "Flow Cytometry", "protocol": "ASTM"},
    {"manufacturer": "Cepheid", "model": "GeneXpert", "type": "Molecular", "protocol": "File"},
    {"manufacturer": "Sysmex", "model": "PocH-100i", "type": "Hematology", "protocol": "File"},
    # Plugin-based: unlimited additional instruments via ASTM bridge
    {"manufacturer": "Generic", "model": "ASTM-compatible", "type": "Any", "protocol": "ASTM"},
]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
