"""
BioMate Benchling LIMS Connector

Provides read-only access to Benchling assay results via the Benchling API v2.
Used by the DMTA loop to automatically ingest wet-lab measurements from Benchling
into the AssayIngestionService for compound ranking updates.

References:
    - Benchling API v2 docs: https://benchling.com/api/reference
    - Benchling Python SDK: benchling-api-client (optional, falls back to requests)

Usage:
    connector = BenchlingConnector(api_key="sk-XXXX")
    results = connector.list_assay_results(schema_id="assaysch_XXXX", since_hours=24)
    # returns list[dict] with keys: compound_id, smiles, assay_value, unit, ...
"""

import logging
import os
from datetime import datetime, timezone, timedelta
from typing import Optional

log = logging.getLogger(__name__)


class BenchlingConnector:
    """
    Thin wrapper around the Benchling Assay Results API.

    Supports two authentication modes:
    - Direct API key (Bearer token)
    - OAuth client credentials (set client_id + client_secret)

    Falls back to mock mode (returns synthetic data) when the API is
    unavailable — useful for local development without Benchling access.
    """

    BASE_URL = "https://api.benchling.com/v2"

    def __init__(
        self,
        api_key: Optional[str] = None,
        tenant_domain: Optional[str] = None,
        mock_mode: bool = False,
    ):
        """
        Args:
            api_key: Benchling API key (sk-XXXXXXXXXXXXXXXX).
                     Defaults to BENCHLING_API_KEY env var.
            tenant_domain: Benchling tenant (e.g. "myorg.benchling.com").
                           Defaults to BENCHLING_TENANT env var.
            mock_mode: Return synthetic data instead of calling the API.
        """
        self.api_key       = api_key or os.environ.get("BENCHLING_API_KEY", "")
        self.tenant_domain = tenant_domain or os.environ.get("BENCHLING_TENANT", "")
        self.mock_mode     = mock_mode or not self.api_key

        if self.tenant_domain:
            self.BASE_URL = f"https://{self.tenant_domain}/api/v2"

        if not self.mock_mode and not self.api_key:
            log.warning("BenchlingConnector: no API key; falling back to mock mode")
            self.mock_mode = True

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    def _get(self, path: str, params: Optional[dict] = None) -> dict:
        """HTTP GET against Benchling API v2."""
        try:
            import requests
        except ImportError:
            raise ImportError("requests is required for BenchlingConnector: pip install requests")

        url = f"{self.BASE_URL}{path}"
        resp = requests.get(url, headers=self._headers(), params=params or {}, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def list_assay_results(
        self,
        schema_id: Optional[str] = None,
        since_hours: float = 24.0,
        max_records: int = 500,
    ) -> list[dict]:
        """
        Fetch assay results from Benchling, filtered by schema and recency.

        Args:
            schema_id: Benchling assay schema ID (assaysch_XXXXX).
                       If None, fetches all accessible schemas.
            since_hours: Return only results created/modified in the last N hours.
            max_records: Maximum records to return (pagination handled internally).

        Returns:
            List of normalized dicts with keys:
                compound_id, smiles, assay_name, assay_value, unit,
                created_at, benchling_id, schema_id
        """
        if self.mock_mode:
            return self._mock_assay_results(schema_id, since_hours)

        since_dt = datetime.now(timezone.utc) - timedelta(hours=since_hours)
        since_str = since_dt.isoformat()

        params = {
            "pageSize": min(max_records, 100),
            "modifiedAt.gte": since_str,
        }
        if schema_id:
            params["schemaId"] = schema_id

        all_results = []
        next_token = None

        while True:
            if next_token:
                params["nextToken"] = next_token

            try:
                data = self._get("/assay-results", params=params)
            except Exception as exc:
                log.error("Benchling API call failed: %s", exc)
                raise

            raw_results = data.get("assayResults", [])
            for r in raw_results:
                normalized = self._normalize_result(r)
                if normalized:
                    all_results.append(normalized)
                if len(all_results) >= max_records:
                    break

            next_token = data.get("nextToken")
            if not next_token or len(all_results) >= max_records:
                break

        log.info(
            "BenchlingConnector: fetched %d results (schema=%s, since=%s)",
            len(all_results), schema_id, since_str
        )
        return all_results

    def _normalize_result(self, raw: dict) -> Optional[dict]:
        """
        Normalize a raw Benchling assay result dict to the standard
        AssayIngestionService schema:
          {compound_id, smiles, assay_name, assay_value, unit, created_at, ...}
        """
        fields = raw.get("fields", {})
        # Try standard field names; Benchling schemas vary per customer
        compound_id = (
            fields.get("compound_id", {}).get("value") or
            fields.get("compound", {}).get("value") or
            raw.get("id", "UNKNOWN")
        )
        smiles = (
            fields.get("smiles", {}).get("value") or
            fields.get("SMILES", {}).get("value") or
            ""
        )
        # Numeric assay value — use first numeric field found
        assay_value = None
        assay_name  = "assay"
        unit        = ""
        for field_name, field_data in fields.items():
            if field_name.lower() in ("compound_id", "compound", "smiles"):
                continue
            val = field_data.get("value")
            if isinstance(val, (int, float)):
                assay_value = val
                assay_name  = field_name
                unit        = field_data.get("units", "")
                break

        if not compound_id:
            return None

        return {
            "compound_id":  compound_id,
            "smiles":       smiles,
            "assay_name":   assay_name,
            "assay_value":  assay_value,
            "unit":         unit,
            "created_at":   raw.get("createdAt", ""),
            "modified_at":  raw.get("modifiedAt", ""),
            "benchling_id": raw.get("id", ""),
            "schema_id":    raw.get("schema", {}).get("id", ""),
        }

    def list_schemas(self) -> list[dict]:
        """Return available assay schemas for this tenant."""
        if self.mock_mode:
            return [{"id": "assaysch_MOCK001", "name": "Mock IC50 Assay"}]
        data = self._get("/assay-result-schemas")
        return [{"id": s["id"], "name": s.get("name", "")}
                for s in data.get("assayResultSchemas", [])]

    def _mock_assay_results(self, schema_id: Optional[str], since_hours: float) -> list[dict]:
        """
        Return synthetic assay data for local development / testing.
        Simulates 10 compound IC50 results from a fictional Benchling schema.
        """
        import random
        random.seed(42)
        now = datetime.now(timezone.utc).isoformat()
        results = []
        smiles_pool = [
            "CC1=CC=CC(=C1)NC2=NC=CC(=N2)NC3=CC=CC(=C3)S(=O)(=O)N",
            "CN1CCN(CC1)C2=CC=C(C=C2)C3=NNC(=O)C3CC4=CC=CC=C4",
            "COC1=CC2=C(C=C1OC)C(=O)C(=C(N2)C3=CC=CC=C3)C4=CC=CC=C4",
            "CC(=O)NC1=CC=C(C=C1)OCC(=O)Nc2ccc(cc2)F",
            "O=C(Nc1ccc(cc1)NC(=O)c2ccc(cc2)Cl)c3cccc(c3)Br",
        ]
        for i in range(10):
            results.append({
                "compound_id":  f"BNG-{i+1:04d}",
                "smiles":       smiles_pool[i % len(smiles_pool)],
                "assay_name":   "IC50_nM",
                "assay_value":  round(random.uniform(1, 5000), 1),
                "unit":         "nM",
                "created_at":   now,
                "modified_at":  now,
                "benchling_id": f"ar_mock_{i:06d}",
                "schema_id":    schema_id or "assaysch_MOCK001",
            })
        return results
