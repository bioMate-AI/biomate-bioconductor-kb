"""
Enhanced Database Query Module for Biomni

This module provides robust database querying with:
1. Local database/cache checking before API calls
2. Query validation against API schemas
3. Retry with LLM feedback on failures
4. Rate limiting with exponential backoff
5. Query caching for successful patterns
6. User interaction hooks for failed queries

Usage:
    from biomni.tool.database_enhanced import EnhancedQueryEngine

    engine = EnhancedQueryEngine()
    result = engine.query("uniprot", prompt="Find human insulin protein")
"""

import hashlib
import json
import os
import pickle
import re
import sqlite3
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Callable, Optional
from urllib.parse import urlparse, parse_qs

import requests
from langchain_core.messages import HumanMessage, SystemMessage

from biomni.llm import get_llm


@dataclass
class QueryResult:
    """Structured result from database query."""
    success: bool
    data: Optional[dict] = None
    error: Optional[str] = None
    source: str = "api"  # "local", "cache", or "api"
    query_info: Optional[dict] = None
    attempts: int = 1
    cached_at: Optional[datetime] = None


@dataclass
class RateLimitConfig:
    """Rate limiting configuration per database."""
    requests_per_minute: int = 30
    min_interval_seconds: float = 0.5
    max_retries: int = 3
    backoff_factor: float = 2.0


@dataclass
class DatabaseConfig:
    """Configuration for a specific database."""
    name: str
    base_url: str
    schema_file: str
    rate_limit: RateLimitConfig = field(default_factory=RateLimitConfig)
    local_data_path: Optional[str] = None
    cache_ttl_hours: int = 24


# Database configurations
DATABASE_CONFIGS = {
    "uniprot": DatabaseConfig(
        name="UniProt",
        base_url="https://rest.uniprot.org",
        schema_file="uniprot.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=100),
        cache_ttl_hours=168,  # 1 week - protein data is stable
    ),
    "kegg": DatabaseConfig(
        name="KEGG",
        base_url="https://rest.kegg.jp",
        schema_file="kegg.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=10),  # KEGG has strict limits
        cache_ttl_hours=168,
    ),
    "pdb": DatabaseConfig(
        name="PDB",
        base_url="https://data.rcsb.org",
        schema_file="pdb.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=50),
        cache_ttl_hours=720,  # 1 month - structure data is very stable
    ),
    "chembl": DatabaseConfig(
        name="ChEMBL",
        base_url="https://www.ebi.ac.uk/chembl/api/data",
        schema_file="chembl.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=30),
        cache_ttl_hours=168,
    ),
    "pubchem": DatabaseConfig(
        name="PubChem",
        base_url="https://pubchem.ncbi.nlm.nih.gov/rest/pug",
        schema_file="pubchem.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=5),  # Very strict limits
        cache_ttl_hours=168,
    ),
    "clinvar": DatabaseConfig(
        name="ClinVar",
        base_url="https://eutils.ncbi.nlm.nih.gov/entrez/eutils",
        schema_file="clinvar.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=3),  # NCBI E-utilities limit
        cache_ttl_hours=24,  # Clinical data updates more frequently
    ),
    "gnomad": DatabaseConfig(
        name="gnomAD",
        base_url="https://gnomad.broadinstitute.org/api",
        schema_file="gnomad.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=30),
        cache_ttl_hours=720,
    ),
    "ensembl": DatabaseConfig(
        name="Ensembl",
        base_url="https://rest.ensembl.org",
        schema_file="ensembl.pkl",
        rate_limit=RateLimitConfig(requests_per_minute=15),
        cache_ttl_hours=720,
    ),
}


class LocalDatabaseManager:
    """Manages local database lookups and caching."""

    def __init__(self, data_path: str = "./data"):
        self.data_path = Path(data_path)
        self.cache_dir = self.data_path / "query_cache"
        self.local_db_dir = self.data_path / "local_databases"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.local_db_dir.mkdir(parents=True, exist_ok=True)

        # Initialize SQLite cache database
        self.cache_db_path = self.cache_dir / "query_cache.db"
        self._init_cache_db()

        # Track known local data files
        self.local_data_files = self._scan_local_data()

    def _init_cache_db(self):
        """Initialize SQLite cache database."""
        conn = sqlite3.connect(str(self.cache_db_path))
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS query_cache (
                query_hash TEXT PRIMARY KEY,
                database_name TEXT,
                prompt TEXT,
                endpoint TEXT,
                response_json TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                accessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                access_count INTEGER DEFAULT 1
            )
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_database ON query_cache(database_name)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_created ON query_cache(created_at)
        """)
        conn.commit()
        conn.close()

    def _scan_local_data(self) -> dict:
        """Scan for available local database files."""
        local_files = {}

        # Common local data patterns
        patterns = {
            "uniprot": ["uniprot*.fasta", "uniprot*.tsv", "swissprot*.fasta"],
            "pdb": ["pdb*.ent", "*.pdb", "structures/*.cif"],
            "kegg": ["kegg_*.json", "pathway_*.xml"],
            "genome": ["*.fa", "*.fasta", "*.gtf", "*.gff"],
        }

        for db_name, file_patterns in patterns.items():
            local_files[db_name] = []
            for pattern in file_patterns:
                local_files[db_name].extend(self.local_db_dir.glob(pattern))
                local_files[db_name].extend(self.data_path.glob(pattern))

        return local_files

    def get_query_hash(self, database: str, prompt: str = None, endpoint: str = None) -> str:
        """Generate a unique hash for a query."""
        key = f"{database}:{prompt or ''}:{endpoint or ''}"
        return hashlib.sha256(key.encode()).hexdigest()[:16]

    def check_cache(self, database: str, prompt: str = None,
                    endpoint: str = None, ttl_hours: int = 24) -> Optional[dict]:
        """Check if query result exists in cache and is still valid."""
        query_hash = self.get_query_hash(database, prompt, endpoint)

        conn = sqlite3.connect(str(self.cache_db_path))
        cursor = conn.cursor()

        cursor.execute("""
            SELECT response_json, created_at, access_count FROM query_cache
            WHERE query_hash = ? AND database_name = ?
        """, (query_hash, database))

        row = cursor.fetchone()

        if row:
            response_json, created_at_str, access_count = row
            created_at = datetime.fromisoformat(created_at_str)

            # Check if cache is still valid
            if datetime.now() - created_at < timedelta(hours=ttl_hours):
                # Update access statistics
                cursor.execute("""
                    UPDATE query_cache
                    SET accessed_at = CURRENT_TIMESTAMP, access_count = access_count + 1
                    WHERE query_hash = ?
                """, (query_hash,))
                conn.commit()
                conn.close()

                return {
                    "data": json.loads(response_json),
                    "cached_at": created_at,
                    "access_count": access_count + 1
                }

        conn.close()
        return None

    def save_to_cache(self, database: str, prompt: str, endpoint: str, response: dict):
        """Save query result to cache."""
        query_hash = self.get_query_hash(database, prompt, endpoint)

        conn = sqlite3.connect(str(self.cache_db_path))
        cursor = conn.cursor()

        cursor.execute("""
            INSERT OR REPLACE INTO query_cache
            (query_hash, database_name, prompt, endpoint, response_json, created_at, accessed_at, access_count)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
        """, (query_hash, database, prompt or "", endpoint or "", json.dumps(response)))

        conn.commit()
        conn.close()

    def check_local_data(self, database: str, query_params: dict) -> Optional[dict]:
        """Check if data is available locally before making API call."""
        local_files = self.local_data_files.get(database, [])

        if not local_files:
            return None

        # Database-specific local lookup logic
        if database == "uniprot":
            return self._lookup_local_uniprot(query_params, local_files)
        elif database == "pdb":
            return self._lookup_local_pdb(query_params, local_files)

        return None

    def _lookup_local_uniprot(self, query_params: dict, files: list) -> Optional[dict]:
        """Look up UniProt data in local FASTA/TSV files."""
        accession = query_params.get("accession")
        gene = query_params.get("gene")

        if not accession and not gene:
            return None

        for fasta_file in files:
            if fasta_file.suffix in [".fasta", ".fa"]:
                try:
                    from Bio import SeqIO
                    for record in SeqIO.parse(str(fasta_file), "fasta"):
                        # Check if record matches query
                        if accession and accession in record.id:
                            return {
                                "source": "local",
                                "file": str(fasta_file),
                                "accession": record.id,
                                "sequence": str(record.seq),
                                "description": record.description
                            }
                        if gene and gene.lower() in record.description.lower():
                            return {
                                "source": "local",
                                "file": str(fasta_file),
                                "accession": record.id,
                                "sequence": str(record.seq),
                                "description": record.description
                            }
                except ImportError:
                    pass  # BioPython not available
                except Exception:
                    continue

        return None

    def _lookup_local_pdb(self, query_params: dict, files: list) -> Optional[dict]:
        """Look up PDB structure in local files."""
        pdb_id = query_params.get("pdb_id", "").lower()

        if not pdb_id:
            return None

        for pdb_file in files:
            if pdb_id in str(pdb_file).lower():
                return {
                    "source": "local",
                    "file": str(pdb_file),
                    "pdb_id": pdb_id,
                    "exists": True
                }

        return None

    def cleanup_expired_cache(self, max_age_days: int = 30):
        """Remove expired cache entries."""
        conn = sqlite3.connect(str(self.cache_db_path))
        cursor = conn.cursor()

        cutoff = datetime.now() - timedelta(days=max_age_days)
        cursor.execute("""
            DELETE FROM query_cache WHERE created_at < ?
        """, (cutoff.isoformat(),))

        deleted = cursor.rowcount
        conn.commit()
        conn.close()

        return deleted


class QueryValidator:
    """Validates LLM-generated queries against API schemas."""

    def __init__(self, schema_dir: str = None):
        if schema_dir is None:
            schema_dir = os.path.join(os.path.dirname(__file__), "schema_db")
        self.schema_dir = schema_dir
        self._schemas = {}

    def load_schema(self, database: str) -> Optional[dict]:
        """Load schema for a specific database."""
        if database in self._schemas:
            return self._schemas[database]

        config = DATABASE_CONFIGS.get(database)
        if not config:
            return None

        schema_path = os.path.join(self.schema_dir, config.schema_file)
        if os.path.exists(schema_path):
            with open(schema_path, "rb") as f:
                self._schemas[database] = pickle.load(f)
            return self._schemas[database]

        return None

    def validate_url(self, database: str, url: str) -> dict:
        """Validate a URL against the database schema."""
        schema = self.load_schema(database)
        config = DATABASE_CONFIGS.get(database)

        result = {
            "valid": True,
            "warnings": [],
            "errors": [],
            "suggestions": []
        }

        if not config:
            result["warnings"].append(f"Unknown database: {database}")
            return result

        # Check base URL
        if not url.startswith(config.base_url) and not url.startswith("http"):
            result["errors"].append(f"URL should start with {config.base_url}")
            result["valid"] = False

        # Parse URL
        try:
            parsed = urlparse(url)
            path = parsed.path
            query_params = parse_qs(parsed.query)
        except Exception as e:
            result["errors"].append(f"Invalid URL format: {str(e)}")
            result["valid"] = False
            return result

        # Schema-based validation
        if schema:
            result = self._validate_against_schema(url, path, query_params, schema, result)

        return result

    def _validate_against_schema(self, url: str, path: str, params: dict,
                                  schema: dict, result: dict) -> dict:
        """Validate URL components against API schema."""
        categories = schema.get("categories", {})

        # Check if path matches any known endpoint
        endpoint_found = False
        for category_name, category in categories.items():
            endpoints = category.get("endpoints", {})
            for endpoint_pattern, endpoint_info in endpoints.items():
                # Extract path pattern from endpoint
                method, pattern = endpoint_pattern.split(" ", 1)

                # Simple pattern matching (could be enhanced)
                pattern_regex = pattern.replace("{id}", r"[^/]+")
                pattern_regex = pattern_regex.replace("{", r"[^/]*").replace("}", r"[^/]*")

                if re.match(pattern_regex, path):
                    endpoint_found = True

                    # Check required parameters
                    required = endpoint_info.get("required_params", [])
                    for req_param in required:
                        if req_param not in params and "{" + req_param + "}" not in pattern:
                            result["errors"].append(f"Missing required parameter: {req_param}")
                            result["valid"] = False

                    break
            if endpoint_found:
                break

        if not endpoint_found:
            result["warnings"].append(f"Endpoint pattern not found in schema: {path}")

        return result


class RateLimiter:
    """Manages rate limiting with exponential backoff."""

    def __init__(self):
        self._last_request_time = {}
        self._request_counts = {}
        self._minute_start = {}

    def wait_if_needed(self, database: str):
        """Wait if rate limit would be exceeded."""
        config = DATABASE_CONFIGS.get(database)
        if not config:
            return

        rate_limit = config.rate_limit
        now = time.time()

        # Check minimum interval
        last_time = self._last_request_time.get(database, 0)
        time_since_last = now - last_time

        if time_since_last < rate_limit.min_interval_seconds:
            sleep_time = rate_limit.min_interval_seconds - time_since_last
            time.sleep(sleep_time)

        # Check requests per minute
        minute_start = self._minute_start.get(database, now)
        if now - minute_start >= 60:
            # Reset counter for new minute
            self._minute_start[database] = now
            self._request_counts[database] = 0

        count = self._request_counts.get(database, 0)
        if count >= rate_limit.requests_per_minute:
            # Wait until next minute
            sleep_time = 60 - (now - minute_start)
            if sleep_time > 0:
                time.sleep(sleep_time)
            self._minute_start[database] = time.time()
            self._request_counts[database] = 0

        # Update tracking
        self._last_request_time[database] = time.time()
        self._request_counts[database] = self._request_counts.get(database, 0) + 1

    def get_backoff_time(self, attempt: int, database: str) -> float:
        """Calculate exponential backoff time."""
        config = DATABASE_CONFIGS.get(database)
        if not config:
            return 2 ** attempt

        return config.rate_limit.min_interval_seconds * (config.rate_limit.backoff_factor ** attempt)


class EnhancedQueryEngine:
    """Main engine for enhanced database queries."""

    def __init__(self, data_path: str = "./data",
                 user_interaction_callback: Optional[Callable] = None):
        """Initialize the enhanced query engine.

        Args:
            data_path: Path to data directory for caching and local data
            user_interaction_callback: Optional callback for user interaction on failures
                Should accept (error_info: dict) and return Optional[str] with user input
        """
        self.local_db = LocalDatabaseManager(data_path)
        self.validator = QueryValidator()
        self.rate_limiter = RateLimiter()
        self.user_callback = user_interaction_callback

        # Load LLM configuration
        try:
            from biomni.config import default_config
            self.llm_model = default_config.llm
            self.api_key = default_config.api_key
        except ImportError:
            self.llm_model = "claude-3-5-haiku-20241022"
            self.api_key = None

    def query(self, database: str, prompt: str = None, endpoint: str = None,
              max_retries: int = 3, use_cache: bool = True,
              check_local: bool = True) -> QueryResult:
        """Execute a database query with all enhancements.

        Args:
            database: Database name (e.g., "uniprot", "pdb")
            prompt: Natural language query
            endpoint: Direct API endpoint (optional)
            max_retries: Maximum retry attempts with LLM feedback
            use_cache: Whether to check/use cache
            check_local: Whether to check local data first

        Returns:
            QueryResult with data, source, and metadata
        """
        config = DATABASE_CONFIGS.get(database)
        if not config:
            return QueryResult(
                success=False,
                error=f"Unknown database: {database}. Available: {list(DATABASE_CONFIGS.keys())}"
            )

        # Step 1: Check local data first
        if check_local and prompt:
            query_params = self._extract_query_params(prompt)
            local_result = self.local_db.check_local_data(database, query_params)
            if local_result:
                return QueryResult(
                    success=True,
                    data=local_result,
                    source="local",
                    query_info={"prompt": prompt, "method": "local_lookup"}
                )

        # Step 2: Check cache
        if use_cache:
            cached = self.local_db.check_cache(
                database, prompt, endpoint, config.cache_ttl_hours
            )
            if cached:
                return QueryResult(
                    success=True,
                    data=cached["data"],
                    source="cache",
                    cached_at=cached["cached_at"],
                    query_info={"prompt": prompt, "endpoint": endpoint}
                )

        # Step 3: Generate and validate query
        attempt = 0
        last_error = None
        generated_endpoint = endpoint

        while attempt < max_retries:
            attempt += 1

            # Generate endpoint from prompt if needed
            if prompt and not generated_endpoint:
                gen_result = self._generate_query(database, prompt, last_error)
                if not gen_result["success"]:
                    last_error = gen_result.get("error", "Failed to generate query")
                    continue
                generated_endpoint = gen_result["endpoint"]

            # Validate the endpoint
            validation = self.validator.validate_url(database, generated_endpoint)
            if not validation["valid"]:
                last_error = f"Validation failed: {'; '.join(validation['errors'])}"
                generated_endpoint = None  # Force regeneration
                continue

            # Apply rate limiting
            self.rate_limiter.wait_if_needed(database)

            # Execute the query
            try:
                result = self._execute_query(generated_endpoint)

                if result["success"]:
                    # Cache successful result
                    if use_cache:
                        self.local_db.save_to_cache(
                            database, prompt, generated_endpoint, result["data"]
                        )

                    return QueryResult(
                        success=True,
                        data=result["data"],
                        source="api",
                        query_info={
                            "prompt": prompt,
                            "endpoint": generated_endpoint,
                            "validation": validation
                        },
                        attempts=attempt
                    )
                else:
                    last_error = result.get("error", "API request failed")
                    # Include API error in feedback for next attempt
                    generated_endpoint = None

            except Exception as e:
                last_error = str(e)
                # Apply backoff before retry
                if attempt < max_retries:
                    backoff = self.rate_limiter.get_backoff_time(attempt, database)
                    time.sleep(backoff)

        # All retries failed - try user interaction
        if self.user_callback:
            user_input = self.user_callback({
                "database": database,
                "original_prompt": prompt,
                "last_error": last_error,
                "attempts": attempt,
                "suggestion": "Please provide a more specific query or direct endpoint"
            })

            if user_input:
                # Retry with user input
                return self.query(
                    database,
                    prompt=user_input if not user_input.startswith("http") else None,
                    endpoint=user_input if user_input.startswith("http") else None,
                    max_retries=1,
                    use_cache=use_cache,
                    check_local=check_local
                )

        return QueryResult(
            success=False,
            error=last_error,
            query_info={"prompt": prompt, "attempts": attempt}
        )

    def _extract_query_params(self, prompt: str) -> dict:
        """Extract query parameters from natural language prompt."""
        params = {}

        # Extract UniProt accession patterns
        accession_match = re.search(r'\b([OPQA-Z]\d{5}[A-Z0-9]{0,4})\b', prompt.upper())
        if accession_match:
            params["accession"] = accession_match.group(1)

        # Extract PDB IDs
        pdb_match = re.search(r'\b(\d[A-Z0-9]{3})\b', prompt.upper())
        if pdb_match:
            params["pdb_id"] = pdb_match.group(1)

        # Extract gene names (simple heuristic)
        gene_patterns = [
            r'gene[:\s]+([A-Z][A-Z0-9]+)',
            r'\b(BRCA[12]|TP53|EGFR|KRAS|MYC|INS|HBB|HBA[12])\b'
        ]
        for pattern in gene_patterns:
            match = re.search(pattern, prompt.upper())
            if match:
                params["gene"] = match.group(1)
                break

        # Extract organism
        organism_patterns = {
            "human": 9606,
            "mouse": 10090,
            "rat": 10116,
            "yeast": 559292,
            "e. coli": 562,
            "drosophila": 7227,
            "zebrafish": 7955,
        }
        prompt_lower = prompt.lower()
        for name, taxid in organism_patterns.items():
            if name in prompt_lower:
                params["organism_id"] = taxid
                params["organism"] = name
                break

        return params

    def _generate_query(self, database: str, prompt: str,
                        previous_error: str = None) -> dict:
        """Generate API query using LLM with optional error feedback."""
        config = DATABASE_CONFIGS.get(database)
        schema = self.validator.load_schema(database)

        if not schema:
            return {"success": False, "error": f"No schema available for {database}"}

        # Build system prompt with schema
        system_template = f"""You are a {config.name} API expert. Generate the correct REST API endpoint for the user's request.

{config.name} API SCHEMA:
{{schema}}

Base URL: {config.base_url}

Your response must be a JSON object with:
1. "full_url": Complete URL including base URL and parameters
2. "description": Brief description of what the query does
3. "confidence": Your confidence level (high/medium/low)

IMPORTANT RULES:
- Always use the correct base URL
- Include all required parameters
- Use proper URL encoding for special characters
- For searches, use the appropriate query syntax
"""

        # Add error feedback if retrying
        if previous_error:
            system_template += f"""

PREVIOUS ATTEMPT FAILED with error: {previous_error}
Please analyze the error and generate a corrected query.
Common issues:
- Incorrect endpoint path
- Missing required parameters
- Invalid parameter values
- Wrong query syntax
"""

        system_template += "\n\nReturn ONLY the JSON object, no additional text."

        try:
            schema_json = json.dumps(schema, indent=2)
            system_prompt = system_template.format(schema=schema_json)

            # Get LLM
            try:
                from biomni.config import default_config
                llm = get_llm(
                    model=self.llm_model,
                    temperature=0.0,
                    api_key=self.api_key,
                    config=default_config
                )
            except ImportError:
                llm = get_llm(
                    model=self.llm_model,
                    temperature=0.0,
                    api_key=self.api_key or "EMPTY"
                )

            messages = [
                SystemMessage(content=system_prompt),
                HumanMessage(content=prompt)
            ]

            response = llm.invoke(messages)
            llm_text = response.content.strip()

            # Parse JSON from response
            json_start = llm_text.find("{")
            json_end = llm_text.rfind("}") + 1

            if json_start >= 0 and json_end > json_start:
                result = json.loads(llm_text[json_start:json_end])
                endpoint = result.get("full_url", "")

                if endpoint:
                    return {
                        "success": True,
                        "endpoint": endpoint,
                        "description": result.get("description", ""),
                        "confidence": result.get("confidence", "medium")
                    }

            return {"success": False, "error": "Could not parse LLM response"}

        except Exception as e:
            return {"success": False, "error": f"LLM query failed: {str(e)}"}

    def _execute_query(self, endpoint: str) -> dict:
        """Execute the actual API request."""
        try:
            headers = {"Accept": "application/json"}
            response = requests.get(endpoint, headers=headers, timeout=30)
            response.raise_for_status()

            try:
                data = response.json()
            except ValueError:
                data = {"raw_text": response.text}

            return {"success": True, "data": data}

        except requests.exceptions.HTTPError as e:
            error_msg = str(e)
            try:
                error_json = e.response.json()
                if "message" in error_json:
                    error_msg = error_json["message"]
                elif "error" in error_json:
                    error_msg = error_json["error"]
            except Exception:
                pass

            return {
                "success": False,
                "error": f"HTTP {e.response.status_code}: {error_msg}",
                "status_code": e.response.status_code
            }

        except requests.exceptions.Timeout:
            return {"success": False, "error": "Request timed out"}

        except requests.exceptions.ConnectionError:
            return {"success": False, "error": "Connection failed"}

        except Exception as e:
            return {"success": False, "error": str(e)}

    def get_cache_stats(self) -> dict:
        """Get cache statistics."""
        conn = sqlite3.connect(str(self.local_db.cache_db_path))
        cursor = conn.cursor()

        cursor.execute("SELECT COUNT(*) FROM query_cache")
        total = cursor.fetchone()[0]

        cursor.execute("""
            SELECT database_name, COUNT(*), SUM(access_count)
            FROM query_cache GROUP BY database_name
        """)
        by_database = {row[0]: {"count": row[1], "accesses": row[2]} for row in cursor.fetchall()}

        conn.close()

        return {
            "total_cached_queries": total,
            "by_database": by_database,
            "cache_path": str(self.local_db.cache_db_path)
        }

    def clear_cache(self, database: str = None):
        """Clear cache entries."""
        conn = sqlite3.connect(str(self.local_db.cache_db_path))
        cursor = conn.cursor()

        if database:
            cursor.execute("DELETE FROM query_cache WHERE database_name = ?", (database,))
        else:
            cursor.execute("DELETE FROM query_cache")

        deleted = cursor.rowcount
        conn.commit()
        conn.close()

        return deleted


# Convenience function for quick queries
def enhanced_query(database: str, prompt: str = None, endpoint: str = None,
                   data_path: str = "./data", **kwargs) -> QueryResult:
    """Quick enhanced query without persistent engine instance."""
    engine = EnhancedQueryEngine(data_path=data_path)
    return engine.query(database, prompt=prompt, endpoint=endpoint, **kwargs)
