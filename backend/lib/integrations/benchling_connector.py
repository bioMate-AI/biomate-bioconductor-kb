"""
Benchling Connector
===================
The single BioMate client for Benchling's REST API v2 (ELN entries, samples,
assay results, molecules, custom entities).

  PULL:  notebook entries, sample inventory, assay results, registered molecules
  PUSH:  BioMate workflow outputs → Benchling result entries

Authentication (https://docs.benchling.com/docs/authentication):
  - Benchling App, OAuth 2.0 client credentials (recommended): POST
    https://{tenant}.benchling.com/oauth/token with grant_type=client_credentials;
    tokens last 15 minutes and come without a refresh token, so a new token is
    requested shortly before expiry or after a 401.
  - Personal API key (trials only): HTTP Basic, key as username, empty password.
  A raw API key is never sent as a Bearer token.

The tenant URL is required (https://{tenant}.benchling.com); there is no
shared default host. Requests retry with exponential backoff on HTTP 429 and
5xx, honouring Retry-After. List calls follow ``nextToken`` with pageSize <= 100.

Environment variables (BenchlingConnector.from_env):
    BENCHLING_TENANT_URL     https://<tenant>.benchling.com (BENCHLING_API_URL also read)
    BENCHLING_CLIENT_ID      OAuth2 client ID      } preferred
    BENCHLING_CLIENT_SECRET  OAuth2 client secret  }
    BENCHLING_API_KEY        personal API key (used only without client credentials)

API reference: https://docs.benchling.com/docs/api/v2
"""

import base64
import logging
import os
import random
import threading
import time
from typing import Any, Callable, Dict, Iterable, List, Optional
from urllib.parse import urlparse

import requests

log = logging.getLogger(__name__)

MAX_PAGE_SIZE = 100
_RETRY_STATUS = {429, 500, 502, 503, 504}
_TOKEN_RENEW_MARGIN_S = 60
_NON_TENANT_HOSTS = {"benchling.com", "www.benchling.com", "api.benchling.com", "docs.benchling.com",
                     "help.benchling.com"}


class BenchlingConfigError(ValueError):
    """Missing or invalid Benchling configuration (tenant, credentials, schema)."""


class BenchlingAPIError(RuntimeError):
    """Benchling returned an error after retries."""

    def __init__(self, message: str, status: Optional[int] = None):
        super().__init__(message)
        self.status = status


def normalize_tenant_url(tenant: str) -> str:
    """Return https://{tenant}.benchling.com for a tenant name or URL.

    Accepts "myorg", "myorg.benchling.com" or "https://myorg.benchling.com[/api/v2]".
    Rejects non-HTTPS URLs, non-Benchling hosts and Benchling hosts that are
    not a tenant (benchling.com, api.benchling.com, ...).
    """
    tenant = (tenant or "").strip()
    if not tenant:
        raise BenchlingConfigError(
            "Benchling tenant URL is required (https://<tenant>.benchling.com); there is no shared host")
    if "://" not in tenant:
        tenant = "https://" + (tenant if "." in tenant else f"{tenant}.benchling.com")
    parsed = urlparse(tenant)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https":
        raise BenchlingConfigError(f"Benchling tenant URL must use https, got '{parsed.scheme}'")
    if not host.endswith(".benchling.com") or host in _NON_TENANT_HOSTS:
        raise BenchlingConfigError(
            f"'{host}' is not a Benchling tenant host; expected https://<tenant>.benchling.com")
    if parsed.username or parsed.password:
        raise BenchlingConfigError("credentials must not be embedded in the tenant URL")
    return f"https://{host}" + (f":{parsed.port}" if parsed.port else "")


class _ApiKeyAuth:
    kind = "api_key"

    def __init__(self, api_key: str):
        self._header = "Basic " + base64.b64encode(f"{api_key}:".encode()).decode()

    def header(self, connector: "BenchlingConnector", force_new: bool = False) -> str:
        return self._header


class _ClientCredentialsAuth:
    kind = "oauth_client_credentials"

    def __init__(self, client_id: str, client_secret: str):
        self.client_id = client_id
        self.client_secret = client_secret
        self._token: Optional[str] = None
        self._expires_at = 0.0
        self._lock = threading.Lock()

    def header(self, connector: "BenchlingConnector", force_new: bool = False) -> str:
        with self._lock:
            if force_new or self._token is None or connector._clock() >= self._expires_at:
                self._token, lifetime = connector._fetch_token(self.client_id, self.client_secret)
                self._expires_at = connector._clock() + max(0, lifetime - _TOKEN_RENEW_MARGIN_S)
            return f"Bearer {self._token}"


class BenchlingConnector:
    """
    Client for the Benchling REST API v2.

    Typical flow:
        1. Pull a notebook entry (experiment context)
        2. Extract sample references + assay results
        3. Map to BioMate workflow inputs
        4. Run workflow via BioMate API
        5. Push workflow outputs back as Benchling assay results

    Assay results for BioMate campaigns are mapped and ingested by
    galaxy.ai.drug_discovery.benchling_connector (explicit per-schema mapping).
    """

    def __init__(
        self,
        tenant_url: Optional[str] = None,
        api_key: Optional[str] = None,
        client_id: Optional[str] = None,
        client_secret: Optional[str] = None,
        *,
        api_url: Optional[str] = None,
        session: Optional[Any] = None,
        max_retries: int = 5,
        backoff_base_s: float = 1.0,
        backoff_max_s: float = 32.0,
        timeout_s: float = 30.0,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ):
        """Explicit arguments only; use from_env() to read the environment.

        ``api_url`` is the former name of ``tenant_url``.
        """
        self.api_url = normalize_tenant_url(tenant_url or api_url or "")
        if client_id or client_secret:
            if not (client_id and client_secret):
                raise BenchlingConfigError("OAuth app auth needs both client_id and client_secret")
            self._auth: Any = _ClientCredentialsAuth(client_id, client_secret)
        elif api_key:
            self._auth = _ApiKeyAuth(api_key)
        else:
            raise BenchlingConfigError(
                "Benchling credentials required: an app client_id/client_secret (recommended) "
                "or a personal API key")
        self.session = session or requests.Session()
        self.max_retries = max_retries
        self.backoff_base_s = backoff_base_s
        self.backoff_max_s = backoff_max_s
        self.timeout_s = timeout_s
        self._sleep = sleep
        self._clock = clock

    @classmethod
    def from_env(cls, environ: Optional[Dict[str, str]] = None, **kwargs: Any) -> "BenchlingConnector":
        env = os.environ if environ is None else environ
        client_id = env.get("BENCHLING_CLIENT_ID", "")
        client_secret = env.get("BENCHLING_CLIENT_SECRET", "")
        return cls(
            tenant_url=env.get("BENCHLING_TENANT_URL") or env.get("BENCHLING_API_URL", ""),
            client_id=client_id or None,
            client_secret=client_secret or None,
            api_key=None if (client_id or client_secret) else (env.get("BENCHLING_API_KEY") or None),
            **kwargs,
        )

    @property
    def auth_kind(self) -> str:
        return self._auth.kind

    @property
    def tenant_host(self) -> str:
        return urlparse(self.api_url).hostname or ""

    # ──────────────────────────────────────────────────────────────────────────
    # HTTP
    # ──────────────────────────────────────────────────────────────────────────

    def _backoff(self, attempt: int, retry_after: Optional[str]) -> float:
        if retry_after:
            try:
                return min(self.backoff_max_s, max(0.0, float(retry_after)))
            except ValueError:
                pass
        delay = min(self.backoff_max_s, self.backoff_base_s * (2 ** attempt))
        return delay + random.uniform(0, self.backoff_base_s)

    def _send(self, method: str, url: str, **kwargs: Any) -> Any:
        """Send with retry on 429/5xx and connection errors; returns the response."""
        attempt = 0
        while True:
            try:
                resp = self.session.request(method, url, timeout=self.timeout_s, **kwargs)
            except (requests.ConnectionError, requests.Timeout) as exc:
                if attempt >= self.max_retries:
                    raise BenchlingAPIError(f"{method} {url} failed after {attempt + 1} attempts: {exc}")
                self._sleep(self._backoff(attempt, None))
                attempt += 1
                continue
            if resp.status_code in _RETRY_STATUS and attempt < self.max_retries:
                self._sleep(self._backoff(attempt, resp.headers.get("Retry-After")))
                attempt += 1
                continue
            return resp

    @staticmethod
    def _error(resp: Any, what: str) -> BenchlingAPIError:
        try:
            body = resp.json()
            detail = (body.get("error") or {}).get("message") or str(body)[:300]
        except Exception:
            detail = (getattr(resp, "text", "") or "")[:300]
        return BenchlingAPIError(f"{what}: HTTP {resp.status_code}: {detail}", status=resp.status_code)

    def _fetch_token(self, client_id: str, client_secret: str):
        url = f"{self.api_url}/oauth/token"
        resp = self._send("POST", url, data={"grant_type": "client_credentials",
                                             "client_id": client_id, "client_secret": client_secret},
                          headers={"Accept": "application/json",
                                   "Content-Type": "application/x-www-form-urlencoded"})
        if resp.status_code != 200:
            raise self._error(resp, "Benchling OAuth token request failed")
        body = resp.json()
        token = body.get("access_token")
        if not token:
            raise BenchlingAPIError("Benchling OAuth token response has no access_token")
        return token, int(body.get("expires_in") or 900)

    def _request(self, method: str, path: str, params: Optional[Dict] = None,
                 body: Optional[Dict] = None) -> Any:
        url = f"{self.api_url}/api/v2{path}"
        headers = {"Accept": "application/json", "User-Agent": "BioMate-Connector/2.0"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        for renew in (False, True):
            headers["Authorization"] = self._auth.header(self, force_new=renew)
            resp = self._send(method, url, params=params, json=body, headers=headers)
            if resp.status_code == 401 and self._auth.kind == "oauth_client_credentials" and not renew:
                continue        # token revoked or expired early: request a new one once
            break
        if resp.status_code >= 400:
            raise self._error(resp, f"Benchling {method} {path}")
        return resp.json() if resp.content else {}

    def _get(self, path: str, params: Optional[Dict] = None) -> Any:
        return self._request("GET", path, params=params)

    def _post(self, path: str, body: Dict) -> Any:
        return self._request("POST", path, body=body)

    def _patch(self, path: str, body: Dict) -> Any:
        return self._request("PATCH", path, body=body)

    def list_all(self, path: str, key: str, params: Optional[Dict] = None,
                 page_size: int = MAX_PAGE_SIZE, max_records: Optional[int] = None) -> List[Dict[str, Any]]:
        """Follow ``nextToken`` through every page of a list endpoint."""
        query = dict(params or {})
        query["pageSize"] = max(1, min(int(page_size), MAX_PAGE_SIZE))
        items: List[Dict[str, Any]] = []
        while True:
            data = self._get(path, params=dict(query))
            items.extend(data.get(key, []) or [])
            if max_records is not None and len(items) >= max_records:
                return items[:max_records]
            token = data.get("nextToken")
            if not token:
                return items
            query["nextToken"] = token

    # ──────────────────────────────────────────────────────────────────────────
    # Registered compounds
    # ──────────────────────────────────────────────────────────────────────────

    def get_molecules(self, molecule_ids: Iterable[str]) -> Dict[str, Dict[str, Any]]:
        """Fetch molecules by ID (GET /molecules?ids=..., 100 per call) → {id: molecule}.

        Each molecule carries canonicalizedSmiles, originalSmiles and
        entityRegistryId. Unknown IDs make Benchling return 400 (raised).
        """
        ids = sorted({i for i in molecule_ids if i})
        found: Dict[str, Dict[str, Any]] = {}
        for chunk_start in range(0, len(ids), MAX_PAGE_SIZE):
            chunk = ids[chunk_start:chunk_start + MAX_PAGE_SIZE]
            for mol in self.list_all("/molecules", "molecules",
                                     {"ids": ",".join(chunk),
                                      "archiveReason": "ANY_ARCHIVED_OR_NOT_ARCHIVED"}):
                found[mol["id"]] = mol
        return found

    def get_custom_entities(self, entity_ids: Iterable[str]) -> Dict[str, Dict[str, Any]]:
        """Fetch custom entities by ID (GET /custom-entities:bulk-get) → {id: entity}."""
        ids = sorted({i for i in entity_ids if i})
        found: Dict[str, Dict[str, Any]] = {}
        for chunk_start in range(0, len(ids), MAX_PAGE_SIZE):
            chunk = ids[chunk_start:chunk_start + MAX_PAGE_SIZE]
            data = self._get("/custom-entities:bulk-get", params={"customEntityIds": ",".join(chunk)})
            for ent in data.get("customEntities", []) or []:
                found[ent["id"]] = ent
        return found

    def list_assay_result_schemas(self) -> List[Dict[str, Any]]:
        return self.list_all("/assay-result-schemas", "assayResultSchemas")

    # ──────────────────────────────────────────────────────────────────────────
    # Notebook Entries (ELN)
    # ──────────────────────────────────────────────────────────────────────────

    def list_entries(
        self,
        project_id: Optional[str] = None,
        schema_id: Optional[str] = None,
        page_size: int = 50,
    ) -> List[Dict[str, Any]]:
        """List notebook entries, optionally filtered by project or schema."""
        params: Dict[str, Any] = {"pageSize": page_size}
        if project_id:
            params["projectId"] = project_id
        if schema_id:
            params["schemaId"] = schema_id
        return self._get("/entries", params=params).get("entries", [])

    def get_entry(self, entry_id: str) -> Dict[str, Any]:
        """Get a single notebook entry with full content."""
        return self._get(f"/entries/{entry_id}")

    def search_entries(self, query: str, page_size: int = 20) -> List[Dict[str, Any]]:
        """Full-text search across notebook entries."""
        params = {"q": query, "pageSize": page_size}
        return self._get("/entries", params=params).get("entries", [])

    def extract_entry_text(self, entry: Dict[str, Any]) -> str:
        """
        Extract plain text from a Benchling notebook entry's day notes.
        Handles both legacy text blocks and modern structured notes.
        """
        texts: List[str] = []
        days = entry.get("days", [])
        for day in days:
            for note in day.get("notes", []):
                # Text block
                if note.get("type") == "text" and note.get("text"):
                    texts.append(note["text"])
                # Table block — join cell values
                elif note.get("type") == "table":
                    for row in note.get("rows", []):
                        for cell in row:
                            if cell.get("text"):
                                texts.append(cell["text"])
        return "\n".join(texts)

    # ──────────────────────────────────────────────────────────────────────────
    # Samples / Inventory
    # ──────────────────────────────────────────────────────────────────────────

    def list_samples(
        self,
        schema_id: Optional[str] = None,
        page_size: int = 50,
    ) -> List[Dict[str, Any]]:
        """List sample/entity inventory. schema_id filters by sample type."""
        params: Dict[str, Any] = {"pageSize": page_size}
        if schema_id:
            params["schemaId"] = schema_id
        return self._get("/samples", params=params).get("samples", [])

    def get_sample(self, sample_id: str) -> Dict[str, Any]:
        """Get a single sample with all fields."""
        return self._get(f"/samples/{sample_id}")

    def search_samples(self, query: str, schema_id: Optional[str] = None) -> List[Dict[str, Any]]:
        """Search samples by name or barcode."""
        params: Dict[str, Any] = {"q": query}
        if schema_id:
            params["schemaId"] = schema_id
        return self._get("/samples", params=params).get("samples", [])

    def samples_to_workflow_inputs(self, samples: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Convert a list of Benchling samples to BioMate workflow input format.
        Extracts common fields: compound ID, SMILES, batch number, concentration.
        """
        compounds = []
        for s in samples:
            fields = s.get("fields", {})
            compound = {
                "benchling_id": s.get("id"),
                "name": s.get("name"),
                "smiles": fields.get("smiles", {}).get("value"),
                "batch": fields.get("batch_number", {}).get("value"),
                "concentration_mM": fields.get("concentration_mM", {}).get("value"),
                "plate_barcode": fields.get("plate_barcode", {}).get("value"),
                "well": fields.get("well_position", {}).get("value"),
            }
            compounds.append({k: v for k, v in compound.items() if v is not None})
        return {"compounds": compounds, "count": len(compounds)}

    # ──────────────────────────────────────────────────────────────────────────
    # Assay Results
    # ──────────────────────────────────────────────────────────────────────────

    def list_assay_results(
        self,
        schema_id: str,
        entry_id: Optional[str] = None,
        page_size: int = MAX_PAGE_SIZE,
        modified_after: Optional[str] = None,
        archive_reason: str = "NOT_ARCHIVED",
        sort: str = "modifiedAt:asc",
        max_records: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """List assay results of one schema, following every page.

        schema_id is required by the API (there is no all-schemas listing).
        modified_after: RFC 3339 watermark, sent as ``modifiedAt.gte`` (callers
        upsert by result ID, so re-reading the boundary record is harmless).
        archive_reason: NOT_ARCHIVED (default), ANY_ARCHIVED or
        ANY_ARCHIVED_OR_NOT_ARCHIVED.
        entry_id: keep only results attached to this notebook entry.
        """
        if not schema_id:
            raise BenchlingConfigError("schema_id is required to list Benchling assay results")
        params: Dict[str, Any] = {"schemaId": schema_id, "sort": sort, "archiveReason": archive_reason}
        if modified_after:
            params["modifiedAt.gte"] = modified_after
        results = self.list_all("/assay-results", "assayResults", params,
                                page_size=page_size, max_records=None if entry_id else max_records)
        if entry_id:
            # The list endpoint has no entry filter; filter on the returned entryId.
            results = [r for r in results if r.get("entryId") == entry_id]
            if max_records is not None:
                results = results[:max_records]
        return results

    def create_assay_result(
        self,
        schema_id: str,
        fields: Dict[str, Any],
        entry_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Create a new assay result row in Benchling.

        schema_id: the Benchling assay result schema ID
        fields:    dict of {field_name: value} — must match schema
        entry_id:  optionally link to a notebook entry
        """
        body: Dict[str, Any] = {
            "assayResults": [
                {
                    "schemaId": schema_id,
                    "fields": {k: {"value": v} for k, v in fields.items()},
                }
            ]
        }
        if entry_id:
            body["assayResults"][0]["entryId"] = entry_id
        return self._post("/assay-results:bulk-create", body)

    def bulk_create_assay_results(
        self,
        schema_id: str,
        rows: List[Dict[str, Any]],
        entry_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Bulk-create assay result rows from a list of field dicts.
        Efficiently uploads BioMate workflow outputs (e.g. 100 ADMET results) in one call.
        """
        results_payload = []
        for row in rows:
            payload: Dict[str, Any] = {
                "schemaId": schema_id,
                "fields": {k: {"value": v} for k, v in row.items()},
            }
            if entry_id:
                payload["entryId"] = entry_id
            results_payload.append(payload)
        body = {"assayResults": results_payload}
        response = self._post("/assay-results:bulk-create", body)
        log.info(f"Bulk-created {len(rows)} assay results in schema {schema_id}")
        return response

    # ──────────────────────────────────────────────────────────────────────────
    # Projects / folders
    # ──────────────────────────────────────────────────────────────────────────

    def list_projects(self) -> List[Dict[str, Any]]:
        """List all accessible Benchling projects."""
        return self._get("/projects").get("projects", [])

    def get_project(self, project_id: str) -> Dict[str, Any]:
        """Get project metadata."""
        return self._get(f"/projects/{project_id}")

    # ──────────────────────────────────────────────────────────────────────────
    # BioMate integration helpers
    # ──────────────────────────────────────────────────────────────────────────

    def pull_workflow_inputs(
        self,
        project_id: Optional[str] = None,
        entry_id: Optional[str] = None,
        sample_schema_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        High-level pull: gather notebook context + sample inventory from Benchling
        and return a dict ready for BioMate workflow parameter injection.
        """
        result: Dict[str, Any] = {}

        # Notebook context
        if entry_id:
            entry = self.get_entry(entry_id)
            result["notebook_text"] = self.extract_entry_text(entry)
            result["entry_name"] = entry.get("name")
            result["entry_id"] = entry_id

        # Sample inventory
        if sample_schema_id:
            samples = self.list_samples(schema_id=sample_schema_id)
            result["compounds"] = self.samples_to_workflow_inputs(samples)

        return result

    def push_workflow_outputs(
        self,
        assay_schema_id: str,
        result_rows: List[Dict[str, Any]],
        entry_id: Optional[str] = None,
        field_mapping: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        """
        High-level push: upload BioMate workflow outputs to Benchling as assay results.

        result_rows:   list of dicts from BioMate output CSV (e.g. ranked_compounds.csv)
        field_mapping: rename BioMate fields to Benchling schema fields
                       e.g. {"composite_score": "BioMate_Score", "herg_ic50_um": "hERG_IC50"}
        """
        if field_mapping:
            result_rows = [
                {field_mapping.get(k, k): v for k, v in row.items()}
                for row in result_rows
            ]
        return self.bulk_create_assay_results(
            schema_id=assay_schema_id,
            rows=result_rows,
            entry_id=entry_id,
        )
