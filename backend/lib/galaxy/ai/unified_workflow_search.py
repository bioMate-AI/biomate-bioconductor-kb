#!/usr/bin/env python3
"""
Unified Workflow Search

Consolidates all workflow search into a single API using the
unified workflow index in galaxy_ai_tools.db.

Replaces:
- WorkflowSearchRAG (3 hardcoded templates)
- RAGWorkflowRecommender (951 JSON files, in-memory)

Uses:
- SQLite FTS for full-text search
- Domain/source filtering
- Preference for nf-core over biomni where overlap exists

Author: BioMate Team
Date: 2024-12-31
"""

import json
import sqlite3
import logging
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
from difflib import SequenceMatcher, get_close_matches

# Optional embedding support — reuses the same all-MiniLM-L6-v2 model as VectorToolSearch.
# Gracefully degraded: if sentence-transformers is unavailable the chain search falls back
# to Jaccard scoring (existing behaviour).

# Model and threshold are module-level constants so callers and tests can inspect
# or override them without touching method bodies.  The model name matches
# VectorToolSearch.DEFAULT_MODEL so both sub-systems share the same weights file.
_CHAIN_EMBED_MODEL_NAME = "all-MiniLM-L6-v2"
# Minimum cosine similarity for a chain to be passed to LLM reranking.
# Intentionally higher than single-workflow search (chains are broad; weak overlap
# means the query is asking for a sub-step, not the full pipeline).
_CHAIN_EMBED_MIN_SIMILARITY = 0.42

# Score thresholds for _classify_match().
# Calibrated to the raw scoring sum produced by _score_workflow().
# High confidence requires meaningful keyword + category overlap; medium allows partial.
_MATCH_SCORE_HIGH = 12.0
_MATCH_SCORE_MED = 6.0

# Shared stopword set for tokenisation.  Used in both single-workflow Jaccard
# and chain Jaccard fallback — keep in one place so they stay in sync.
_SEARCH_STOPWORDS: frozenset = frozenset({
    "i", "want", "to", "the", "a", "an", "for", "with",
    "and", "or", "from", "in", "on", "my", "run", "perform",
    "execute", "do", "using", "via", "of", "at", "as", "by",
})

try:
    import numpy as _np
    from sentence_transformers import SentenceTransformer as _ST
    _CHAIN_EMBED_MODEL: Optional[Any] = None      # lazy singleton
    _CHAIN_EMBED_NAMES: List[str] = []            # chain names in index order
    _CHAIN_EMBED_MATRIX: Optional[Any] = None     # np.ndarray (n_chains × dim)
    _EMBEDDINGS_AVAILABLE = True
except ImportError:
    _np = None
    _ST = None
    _CHAIN_EMBED_MODEL = None
    _CHAIN_EMBED_NAMES = []
    _CHAIN_EMBED_MATRIX = None
    _EMBEDDINGS_AVAILABLE = False

log = logging.getLogger(__name__)

# Database path
DB_PATH = Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"

# Source priority for the workflows table (higher = preferred).
# Both the workflows table AND the tools table contain Bioconductor entries:
#   tools table      → package metadata, vignette steps, function lists (tool-level search)
#   workflows table  → the runnable .nf workflow files (workflow-level search, ~1818 entries)
SOURCE_PRIORITY = {
    "nfcore":           100,  # Full nf-core pipelines (rnaseq, sarek, chipseq, …)
    "nfcore_subwf":      95,  # nf-core composite subworkflows (multi-tool analysis steps)
    "biomni_nextflow":   85,  # BioMate domain analysis workflows (Python, Docker-native)
    "bioconductor":      75,  # Bioconductor R package Nextflow workflows (~1818 .nf files)
    "galaxy_biomni":     35,  # Unique BioMate Galaxy workflows pending NF conversion
    # legacy / compat
    "nfcore_converted":  88,
    "galaxy_local":      30,
    "unknown":           20,
    "nfcore_module":     10,  # Should be in tools table; low priority if found here
    "biomni":             5,  # Fully superseded legacy
}


@dataclass
class WorkflowMatch:
    """Represents a workflow search result."""
    id: int
    name: str
    description: str
    domain: str
    source: str
    format: str
    step_count: int
    tools: List[str]
    tags: List[str]
    score: float
    match_type: str  # high_confidence, medium_confidence, low_confidence
    filename: str
    workflow_json: Optional[str] = None


@dataclass
class WorkflowChain:
    """A named, ordered composition of workflows for a research project type.

    Chains are the unit of plan when a user submits a multi-step research
    query.  A matching chain bypasses per-query LLM assembly and provides
    a validated, curated execution plan with explicit data-flow connections.
    """
    id: int
    name: str
    display_name: str
    domain: str
    description: str
    steps: List[Dict[str, Any]]        # [{order, workflow_name, role, params_template}]
    connections: List[Dict[str, Any]]  # [{from_step, from_output, to_step, to_input}]
    required_inputs: List[Dict[str, Any]]
    expected_outputs: List[Dict[str, Any]]
    example_queries: List[str]
    tags: List[str]
    source: str                        # 'curated' | 'learned' | 'user_defined'
    usage_count: int
    success_rate: float
    # Set by _llm_select_chain when LLM is uncertain about scope — caller should
    # surface this question to the user rather than launching the chain directly.
    clarification_needed: bool = False
    clarification_question: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "display_name": self.display_name,
            "domain": self.domain,
            "description": self.description,
            "steps": self.steps,
            "connections": self.connections,
            "required_inputs": self.required_inputs,
            "expected_outputs": self.expected_outputs,
            "example_queries": self.example_queries,
            "tags": self.tags,
            "source": self.source,
            "usage_count": self.usage_count,
            "success_rate": self.success_rate,
        }


class UnifiedWorkflowSearch:
    """
    Unified search across all indexed workflows.

    Features:
    1. Full-text search using SQLite FTS
    2. Domain filtering
    3. Source preference (nf-core > biomni)
    4. Keyword boosting for bioinformatics terms
    """

    def __init__(self, db_path: Optional[Path] = None):
        """Initialize with database connection."""
        self.db_path = db_path or DB_PATH
        self._ensure_fts_index()

        # Optional fast-LLM client for Pass-0 catalog browse.
        # Set via set_llm_client() from AIAssistant after construction.
        self._llm_client: Optional[Any] = None

        # Keyword weights for scoring
        self.keyword_weights = {
            # RNA-seq & Differential Expression
            'rna-seq': 3.0, 'rnaseq': 3.0, 'rna': 2.0,
            'expression': 2.0, 'differential': 2.5, 'de': 2.0,
            'deseq2': 3.0, 'edger': 3.0, 'limma': 2.5,
            'salmon': 2.5, 'kallisto': 2.5, 'star': 2.0, 'hisat2': 2.0,
            'transcriptome': 2.0, 'transcriptomics': 2.5,

            # RNA Velocity (separate from DE)
            'velocity': 2.5, 'velocyto': 3.0, 'scvelo': 3.0,
            'trajectory': 2.0, 'pseudotime': 2.0,

            # Canonical pipeline name anchors — high weight so exact name matches win
            'sarek': 4.0, 'rnaseq': 3.0, 'chipseq': 4.0, 'atacseq': 4.0,
            'raredisease': 4.0, 'taxprofiler': 4.0, 'methylseq': 4.0,
            'scrnaseq': 4.0, 'differentialabundance': 4.0, 'oncoanalyser': 4.0,

            # Variant calling
            'variant': 3.0, 'snp': 2.5, 'indel': 2.0, 'mutation': 2.0,
            'gatk': 2.5, 'freebayes': 2.0, 'bcftools': 2.0,
            'vcf': 2.0, 'calling': 1.5,

            # ChIP-seq / ATAC-seq
            'chip-seq': 3.0, 'chipseq': 3.0, 'atac': 2.5, 'peak': 2.0,
            'macs2': 2.5, 'homer': 2.0,

            # Proteomics
            'proteomics': 3.0, 'dia': 2.5, 'dda': 2.5, 'mass-spec': 2.0,
            'dia-nn': 3.0, 'maxquant': 2.5,

            # Single-cell
            'single-cell': 3.0, 'scrna': 3.0, 'scrnaseq': 3.0,
            'scanpy': 2.5, 'seurat': 2.5, 'cellranger': 2.5,

            # Methylation
            'methylation': 3.0, 'bisulfite': 2.5, 'methylseq': 3.0,

            # Assembly
            'assembly': 3.0, 'genome': 2.0, 'contig': 2.0,
            'spades': 2.5, 'flye': 2.5,

            # Quality control
            'quality': 2.0, 'qc': 2.0, 'fastqc': 2.5, 'multiqc': 2.0,

            # File formats & conversion (CRITICAL - was missing!)
            'fasta': 2.5, 'fastq': 2.5, 'bam': 2.0, 'sam': 2.0,
            'bed': 2.0, 'gff': 2.0, 'gtf': 2.0, 'bigwig': 2.0,
            'convert': 2.5, 'conversion': 2.5, 'format': 1.5,
            'extract': 1.5, 'filter': 1.5, 'merge': 1.5,

            # Alignment
            'align': 2.0, 'alignment': 2.5, 'mapping': 2.0,
            'bwa': 2.5, 'bowtie': 2.5, 'bowtie2': 2.5, 'minimap2': 2.5,

            # General analysis terms
            'analysis': 1.0, 'pipeline': 1.5, 'workflow': 1.0,

            # Cryo-EM / Structural biology
            'cryo': 3.0, 'cryoem': 3.0, 'cryo-em': 3.0,
            'cryosparc': 3.0, 'relion': 3.0,
            'single': 1.5, 'particle': 2.5, 'spa': 2.5,
            'micrograph': 3.0, 'ctf': 2.5, 'motion': 2.0,
            'reconstruction': 2.5, 'refinement': 2.5,
            'tomography': 3.0, 'cryo-et': 3.0, 'tiltseries': 2.5,
            'subtomogram': 3.0, 'tomogram': 2.5, 'tilt': 2.0, 'lamella': 2.5,
            'electron': 2.0, 'microscopy': 2.0,
            'resolution': 2.0, 'map': 1.5, 'density': 1.5,
            'sharpening': 2.5, 'fsc': 2.5,
            # Nanodisc / membrane protein reconstitution
            'saposin': 4.0, 'nanodisc': 3.5, 'msp': 3.0, 'msp1d1': 3.5,
            'lipid': 2.0, 'reconstitution': 2.5, 'detergent': 2.0,
            'membrane': 2.0, 'transporter': 2.5,
            # GPCR / G protein complex
            'gpcr': 4.0, 'g-protein': 3.5, 'gprotein': 3.5, 'gi': 2.0, 'gs': 2.0,
            'scfv16': 4.0, 'apyrase': 3.5, 'opioid': 3.0, 'dopamine': 2.5,
            'receptor': 2.0, 'agonist': 2.5, 'biased': 2.5, 'arrestin': 2.5,
            'pam': 2.5, 'allosteric': 2.5,
            # Multi-drug / difference maps
            'difference': 3.0, 'atlas': 2.5, 'multi-drug': 3.5, 'multidrug': 3.5,
            'occupancy': 2.5, 'pharmacophore': 2.5, 'sigma': 2.0,
            'calcium': 2.0, 'cav1': 3.0, 'ion-channel': 3.5, 'ionchannel': 2.5,
            'apo': 2.0, 'drug-bound': 3.0,
            # Pore-forming proteins / liposome SPA
            'pore': 3.0, 'liposome': 3.5, 'bax': 3.5, 'cardiolipin': 3.0,
            'lysis': 2.5, 'ants': 2.5, 'dpx': 2.5, 'gasdermin': 3.0, 'perforin': 3.0,
            # RELION multi-body / flexible complexes
            'multibody': 4.0, 'multi-body': 4.0, 'flexible': 2.0, 'domain-motion': 3.0,
            'body-mask': 3.5, 'spliceosome': 3.5, 'ribosome': 2.5, 'relion': 3.0,

            # Drug discovery / Pharmacology / ADMET
            'admet': 3.0, 'herg': 3.0, 'dili': 3.0,
            'toxicity': 2.5, 'cardiotoxicity': 3.0, 'hepatotoxicity': 2.5,
            'ames': 2.5, 'mutagenicity': 2.5, 'clintox': 2.5,
            'drug': 2.0, 'compound': 2.0, 'molecule': 1.5,
            'smiles': 2.5, 'ligand': 2.5, 'scaffold': 2.5,
            'pharmacology': 3.0, 'pharmacokinetics': 3.0, 'pharmacokinetic': 3.0,
            'absorption': 2.0, 'distribution': 1.5, 'metabolism': 2.0, 'excretion': 2.0,
            'bioavailability': 2.5, 'permeability': 2.0, 'bbb': 2.5,
            'docking': 3.0, 'binding': 2.0, 'affinity': 2.0,
            'alphafold': 2.5, 'alphafold3': 3.0, 'diffdock': 3.0, 'autodock': 2.5, 'vina': 2.5,
            'nca': 3.0, 'pknca': 3.0, 'nlmixr2': 3.0,
            'auc': 2.5, 'cmax': 2.5, 'tmax': 2.0, 'half-life': 2.5,
            'qsar': 3.0, 'rdkit': 2.5, 'mordred': 2.5,
            'scaffold-hopping': 3.0, 'mmp': 2.5, 'recap': 2.5,
            'drug-like': 2.5, 'druglikeness': 2.5, 'lipinski': 2.0,
            'solubility': 2.0, 'logp': 2.0, 'psa': 2.0,

            # MD simulation (AMBER / GROMACS)
            'amber': 3.5, 'pmemd': 3.5, 'amber24': 3.5, 'ambertools': 3.0,
            'gromacs': 3.5, 'gmx': 3.0, 'gromos': 3.0, 'gromacs md': 3.5,
            'molecular dynamics': 3.5, 'md simulation': 3.5, 'explicit solvent md': 3.5,
            'nvt': 2.5, 'npt': 2.5, 'equilibration': 2.5, 'gaff2': 3.0, 'tleap': 3.0,
            'mm-gbsa': 3.5, 'mmgbsa': 3.5, 'mmpbsa': 3.5, 'binding free energy': 3.5,
            'cpptraj': 3.0, 'rmsd trajectory': 3.0, 'protein stability': 3.0,

            # Glide / Schrödinger
            'glide': 3.5, 'schrodinger': 3.5, 'schrödinger': 3.5,
            'glidescore': 3.5, 'htvs': 3.5, 'xp docking': 3.5, 'sp docking': 3.0,
            'extra precision docking': 3.5, 'prepwiz': 3.0, 'ligprep': 2.5,
            'virtual screening glide': 3.5, 'fep plus': 3.0, 'fep+': 3.0,

            # MOE covalent docking
            'moe': 3.5, 'moebatch': 3.5, 'covdock': 3.5, 'covalent docking': 3.5,
            'covalent inhibitor': 3.5, 'warhead': 3.5, 'acrylamide': 3.0,
            'chloroacetamide': 3.0, 'irreversible inhibitor': 3.5,
            'gbvi': 3.0, 'gbvi wsa': 3.5, 'targeted covalent': 3.5,
            'molecular operating environment': 3.5,

            # Generative design (REINVENT4)
            'reinvent': 3.5, 'reinvent4': 3.5, 'generative design': 3.5,
            'de novo design': 3.5, 'de novo': 3.0, 'scaffold hopping': 3.5,
            'lead generation': 3.0, 'lead optimization': 3.0,
            'molecule optimization': 3.0, 'fragment decoration': 3.0,

            # Assay ingestion & ranking
            'assay ingestion': 4.0, 'compound ranking': 3.5, 'safety potency ranking': 4.0,
            'composite ranking': 3.5, 'composite score': 3.5, 'bcr abl1': 3.5,
            'herg ranking': 3.5, 'potency safety': 3.5, 'multi assay': 3.0,
            'assay data': 3.0, 'ingest assay': 4.0, 'rank compounds': 3.5,

            # CRO submission export
            'cro submission': 4.0, 'wuxi apptec': 4.5, 'cro export': 4.0,
            'compound export': 3.5, 'cro outsourcing': 4.0, 'submission export': 3.5,
            'wuxiapptec': 4.5, 'contract research': 3.0,
        }

        log.info(f"UnifiedWorkflowSearch initialized with DB: {self.db_path}")

    def _get_connection(self) -> sqlite3.Connection:
        """Get database connection."""
        return sqlite3.connect(str(self.db_path))

    def _ensure_fts_index(self):
        """Ensure FTS index exists and is populated."""
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            # Check if FTS table exists
            cursor.execute("""
                SELECT name FROM sqlite_master
                WHERE type='table' AND name='workflows_fts'
            """)

            if not cursor.fetchone():
                log.warning("FTS index not found, creating...")
                self._create_fts_index(conn)

        finally:
            conn.close()

    def _create_fts_index(self, conn: sqlite3.Connection):
        """Create FTS index for workflows."""
        cursor = conn.cursor()

        # Create FTS table if not exists
        cursor.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS workflows_fts USING fts5(
                name, description, annotation, tags, domain, tools_used,
                content='workflows',
                content_rowid='id'
            )
        """)

        # Populate FTS index
        cursor.execute("""
            INSERT INTO workflows_fts(rowid, name, description, annotation, tags, domain, tools_used)
            SELECT id, name, description, annotation, tags, domain, tools_used FROM workflows
        """)

        conn.commit()
        log.info("FTS index created and populated")

    # ------------------------------------------------------------------
    # Pass-0: LLM-based catalog browse
    # ------------------------------------------------------------------

    def set_llm_client(self, client: Any) -> None:
        """Inject a fast-LLM client to enable Pass-0 catalog browse.

        The client must expose ``generate(prompt, max_tokens, temperature) -> str``.
        Call this from ``AIAssistant.__init__()`` after construction so that
        the singleton search instance gets LLM capability without requiring it
        at import time.
        """
        self._llm_client = client
        log.info("[UnifiedWorkflowSearch] LLM client set — Pass-0 browse enabled")

    def _browse_catalog_with_llm(
        self,
        query: str,
        broad_limit: int = 60,
        output_limit: int = 10,
    ) -> List[int]:
        """Pass-0: Ask the LLM to identify the most relevant workflow IDs.

        Algorithm
        ---------
        1. Fetch ``broad_limit`` workflows from the DB using a relaxed FTS
           query (many terms OR-joined).  These are the candidates the LLM
           will choose from.
        2. Format them as a compact numbered list: ``<id>. <name>: <description>``.
        3. Send to the fast LLM (Claude Haiku / GPT-3.5) with a structured
           prompt asking it to return a JSON list of the top ``output_limit``
           workflow IDs best matching the query.
        4. Parse the JSON; return a list of integer IDs.  Returns ``[]`` on
           any error so the caller can fall back to pure FTS.

        This is intentionally lightweight:
        - Uses the cheapest/fastest model.
        - Max 128 output tokens (a short JSON array).
        - Fails silently — never blocks the main search path.
        """
        if self._llm_client is None:
            return []

        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            fts_query = self._build_fts_query(query)
            cursor.execute(
                """
                SELECT w.id, w.name, COALESCE(w.description, '') as description
                FROM workflows w
                JOIN workflows_fts ON w.id = workflows_fts.rowid
                WHERE workflows_fts MATCH ?
                ORDER BY bm25(workflows_fts)
                LIMIT ?
                """,
                [fts_query, broad_limit],
            )
            rows = cursor.fetchall()
        except Exception as _exc:
            log.debug("[Pass-0] FTS broad fetch failed: %s", _exc)
            return []
        finally:
            conn.close()

        if not rows:
            return []

        # Format catalog for LLM
        catalog_lines = []
        for wf_id, name, desc in rows:
            short_desc = (desc or "")[:120].replace("\n", " ")
            catalog_lines.append(f"{wf_id}. {name}: {short_desc}")
        catalog_text = "\n".join(catalog_lines)

        prompt = (
            f"You are a bioinformatics workflow recommender.\n"
            f"User query: {query}\n\n"
            f"Candidate workflows (id. name: description):\n{catalog_text}\n\n"
            f"Return ONLY a JSON array of the {output_limit} workflow IDs (integers) "
            f"that best match the user query, ordered by relevance (best first). "
            f"Example: [42, 7, 15]. No explanation, just the JSON array."
        )

        try:
            raw = self._llm_client.generate(prompt, max_tokens=128, temperature=0.0)
            # Extract JSON array from the response (strip any surrounding text)
            import re as _re
            m = _re.search(r"\[[\d,\s]+\]", raw or "")
            if not m:
                log.debug("[Pass-0] LLM response has no JSON array: %r", raw)
                return []
            ids = [int(x) for x in m.group(0).strip("[]").split(",") if x.strip().isdigit()]
            log.info("[Pass-0] LLM selected %d workflow IDs for query %r", len(ids), query[:60])
            return ids[:output_limit]
        except Exception as _exc:
            log.debug("[Pass-0] LLM catalog browse failed: %s", _exc)
            return []

    def search(self,
               query: str,
               domain: Optional[str] = None,
               source: Optional[str] = None,
               format: Optional[str] = None,
               limit: int = 10,
               include_workflow_json: bool = False,
               user_profile: Optional[Dict[str, Any]] = None,
               preferred_domains: Optional[List[str]] = None,
               penalized_domains: Optional[List[str]] = None,
               key_terms: Optional[List[str]] = None) -> List[WorkflowMatch]:
        """
        Search for workflows matching the query.

        Args:
            query: Natural language search query
            domain: Filter by domain (genomics, proteomics, etc.)
            source: Filter by source (nfcore, biomni, etc.)
            format: Filter by format (galaxy_ga, nextflow)
            limit: Maximum results to return
            include_workflow_json: Include full workflow JSON in results
            user_profile: Optional user domain profile dict with keys
                ``domains`` (list[str]) and ``topics`` (list[str]).
                Used as a starting bias — profile domains are preferred
                unless the query context overrides them.

        Returns:
            List of WorkflowMatch objects sorted by relevance
        """
        # ── Pass 0: LLM catalog browse ─────────────────────────────────────────
        # Ask the fast LLM to pick the most semantically relevant workflow IDs
        # from a broad FTS candidate set.  Returns [] when LLM is unavailable
        # or any error occurs, so the rest of the search is unaffected.
        # Preserve ranked order for graded boosting (rank 0 gets +3.0, rank 9 gets +0.3).
        llm_ranked_ids: List[int] = self._browse_catalog_with_llm(query, broad_limit=60, output_limit=10)
        llm_rank_map: Dict[int, int] = {wf_id: rank for rank, wf_id in enumerate(llm_ranked_ids)}

        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            # Build FTS query — augment with LLM-extracted key_terms when provided
            effective_query = query
            if key_terms:
                extra = " ".join(t for t in key_terms if t and t.lower() not in query.lower())
                if extra:
                    effective_query = f"{query} {extra}"
            fts_query = self._build_fts_query(effective_query)

            # When preferred_domains is provided (LLM-derived), use penalized_domains too
            # if the caller passed them. When neither is provided, _calculate_score falls
            # back to rule-based _infer_domain_preferences().
            # (penalized_domains parameter already holds the caller's value, no reassignment needed)

            # Build SQL with filters
            sql = """
                SELECT w.id, w.name, w.description, w.domain, w.source, w.format,
                       w.step_count, w.tools_used, w.tags, w.filename, w.workflow_json,
                       bm25(workflows_fts) as fts_score
                FROM workflows w
                JOIN workflows_fts ON w.id = workflows_fts.rowid
                WHERE workflows_fts MATCH ?
            """
            params = [fts_query]

            if domain:
                sql += " AND w.domain = ?"
                params.append(domain)

            if source:
                sql += " AND w.source = ?"
                params.append(source)

            if format:
                sql += " AND w.format = ?"
                params.append(format)

            sql += " ORDER BY fts_score LIMIT ?"
            params.append(max(limit * 10, 50))  # Get many more for re-ranking (min 50)

            cursor.execute(sql, params)
            rows = cursor.fetchall()

            # Re-rank with custom scoring
            results = []
            for row in rows:
                match = self._create_match(row, query, include_workflow_json, user_profile=user_profile,
                                           preferred_domains=preferred_domains, penalized_domains=penalized_domains)
                # ── Pass-0 boost: workflows the LLM ranked get a graded bonus ──
                # rank 0 → +3.0, rank 1 → +2.7, ..., rank 9 → +0.3
                if llm_rank_map and row[0] in llm_rank_map:
                    rank = llm_rank_map[row[0]]
                    rank_bonus = max(0.0, 3.0 - 0.3 * rank)
                    match = WorkflowMatch(
                        id=match.id,
                        name=match.name,
                        description=match.description,
                        domain=match.domain,
                        source=match.source,
                        format=match.format,
                        step_count=match.step_count,
                        tools=match.tools,
                        tags=match.tags,
                        filename=match.filename,
                        workflow_json=match.workflow_json,
                        score=round(match.score + rank_bonus, 2),
                        match_type=match.match_type,
                    )
                results.append(match)

            # Sort by custom score (includes source priority + Pass-0 boost)
            results.sort(key=lambda x: x.score, reverse=True)

            # ── Pass-0 rescue: fetch LLM-ranked IDs that FTS missed ─────────
            # Some semantically relevant workflows may have low FTS scores and
            # fall outside the broad candidate set.  Fetch them directly and
            # insert them using their LLM rank to determine a synthetic score.
            if llm_ranked_ids:
                seen_ids = {m.id for m in results}
                missing_llm_ids = [wf_id for wf_id in llm_ranked_ids if wf_id not in seen_ids]
                if missing_llm_ids:
                    placeholders = ",".join("?" * len(missing_llm_ids))
                    rescue_sql = f"""
                        SELECT w.id, w.name, w.description, w.domain, w.source, w.format,
                               w.step_count, w.tools_used, w.tags, w.filename, w.workflow_json,
                               0.0 as fts_score
                        FROM workflows w
                        WHERE w.id IN ({placeholders})
                    """
                    try:
                        rescue_conn = self._get_connection()
                        rc = rescue_conn.cursor()
                        rc.execute(rescue_sql, missing_llm_ids)
                        rescued_rows = rc.fetchall()
                        rescue_conn.close()
                        for row in rescued_rows:
                            m = self._create_match(row, query, include_workflow_json, user_profile=user_profile,
                                                   preferred_domains=preferred_domains, penalized_domains=penalized_domains)
                            rank = llm_rank_map.get(row[0], len(llm_ranked_ids))
                            # Synthetic score: 2.8 − 0.3*rank (one notch below top FTS+LLM hits)
                            m = WorkflowMatch(
                                id=m.id, name=m.name, description=m.description,
                                domain=m.domain, source=m.source, format=m.format,
                                step_count=m.step_count, tools=m.tools, tags=m.tags,
                                filename=m.filename, workflow_json=m.workflow_json,
                                score=round(2.8 - 0.3 * rank, 2),
                                match_type="llm_rescued",
                            )
                            results.append(m)
                        if rescued_rows:
                            results.sort(key=lambda x: x.score, reverse=True)
                            log.debug("Pass-0 rescued %d LLM-selected workflows not in FTS", len(rescued_rows))
                    except Exception as exc:
                        log.debug("Pass-0 rescue fetch failed: %s", exc)

            return results[:limit]

        except sqlite3.OperationalError as e:
            log.warning(f"FTS search failed: {e}, falling back to LIKE search")
            return self._fallback_search(query, domain, source, format, limit, include_workflow_json, user_profile=user_profile)

        finally:
            conn.close()

    # Common bioinformatics abbreviation expansions
    ABBREVIATION_MAP = {
        'de': ['differential', 'expression'],  # DE = Differential Expression
        'deg': ['differential', 'expression', 'gene'],  # DEG
        'dea': ['differential', 'expression', 'analysis'],  # DEA
        'ngs': ['next', 'generation', 'sequencing'],
        'wgs': ['whole', 'genome', 'sequencing'],
        'wes': ['whole', 'exome', 'sequencing'],
        'rnaseq': ['rna', 'seq', 'transcriptome'],
        'chipseq': ['chip', 'seq', 'chromatin'],
        'atacseq': ['atac', 'seq', 'chromatin', 'accessibility'],
        'scrna': ['single', 'cell', 'rna'],
        'scrnaseq': ['single', 'cell', 'rna', 'seq'],
        'bwa': ['bwa', 'alignment', 'mapping'],
        'bowtie': ['bowtie', 'alignment', 'mapping'],
        'star': ['star', 'alignment', 'spliced'],
        'deseq': ['deseq2', 'differential', 'expression'],
        'deseq2': ['deseq2', 'differential', 'expression'],
        'edger': ['edger', 'differential', 'expression'],
        'gatk': ['gatk', 'variant', 'calling'],
        'vcf': ['vcf', 'variant'],
        'qc': ['quality', 'control'],
        'fastqc': ['fastqc', 'quality', 'control'],
    }

    def _infer_domain_preferences(self, query: str) -> Tuple[set, set]:
        """
        Infer domain preferences from user query for ranking bias.

        Returns:
            (preferred_domains, penalized_domains)
        """
        q = query.lower()
        preferred = set()
        penalized = set()

        # WES / somatic variant workflows should not rank microbiome workflows highly.
        if any(token in q for token in [
            'wes', 'whole exome', 'exome', 'tumor normal', 'tumor-normal', 'somatic'
        ]):
            preferred.update({'genomics', 'variant_calling', 'cancer_biology'})
            penalized.update({'microbiology', 'metagenomics'})

        # Microbiome / metagenomics intent
        if any(token in q for token in ['microbiome', 'metagenomics', '16s', 'metagenome']):
            preferred.update({'microbiology', 'metagenomics'})
            penalized.update({'variant_calling'})

        # Transcriptomics intent
        if any(token in q for token in ['rna-seq', 'rnaseq', 'deseq2', 'differential expression', 'transcriptome']):
            preferred.update({'transcriptomics'})

        # Drug discovery / pharmacology / structural biology
        drug_tokens = ['docking', 'autodock', 'vina', 'diffdock', 'alphafold', 'structure prediction',
                       'binding affinity', 'admet', 'herg', 'dili', 'pharmacokinetic', 'nca', 'pknca',
                       'drug', 'ligand', 'scaffold', 'smiles', 'molecular docking']
        if any(tok in q for tok in drug_tokens):
            preferred.update({'drug_discovery', 'biochemistry', 'structural_biology'})
            penalized.update({'microbiology', 'metagenomics', 'transcriptomics'})

        return preferred, penalized

    # Tokens that signal "I have raw data to process" or "I want to run a pipeline"
    # → prefer full pipeline sources (nfcore, biomni_nextflow) over R package libraries
    _PIPELINE_INTENT_SIGNALS = [
        # "I have data" pattern
        'i have', 'my data', 'my samples', 'i want to process', 'i want to run',
        'process my', 'analyze my', 'analyse my', 'run analysis', 'run a pipeline',
        'fastq', 'bam file', 'vcf file', 'raw reads', 'raw data', 'sequencing data',
        'from samples', 'from patients', 'from cells', 'i need to process',
        'we have', 'our data', 'our samples', 'we sequenced',
        # "run [workflow_type]" pattern — clearly want to execute a pipeline
        'run rna', 'run chip', 'run atac', 'run variant', 'run qc', 'run wgs',
        'run methylseq', 'run sarek', 'run rnaseq', 'run genome',
        'perform rna', 'perform chip', 'perform variant', 'perform whole genome',
        'execute rna', 'execute variant', 'execute pipeline',
        'do rna-seq', 'do rna seq', 'do chip-seq', 'do atac-seq',
        'nf-core run', 'nextflow run',
    ]

    def _detect_pipeline_intent(self, query: str) -> bool:
        """Return True when the user's query indicates they have raw data to process.

        Such queries should prefer full pipeline sources (nfcore, biomni_nextflow)
        over package-level tools (bioconductor) that operate on already-processed data.
        """
        q = query.lower()
        return any(signal in q for signal in self._PIPELINE_INTENT_SIGNALS)

    def _build_fts_query(self, query: str) -> str:
        """Build FTS5 query from natural language with safe tokenization and abbreviation expansion."""
        # Robust tokenization: strip punctuation that can break FTS syntax.
        words = re.findall(r"[a-z0-9]+", query.lower())

        # Remove common words
        words = [w for w in words if w not in _SEARCH_STOPWORDS and len(w) > 1]

        # Expand abbreviations — keep the original token AND add expansions
        # so "rnaseq" matches both the exact "rnaseq" token in FTS and
        # workflows that use the expanded form "rna seq transcriptome".
        expanded_words = []
        for word in words:
            if word in self.ABBREVIATION_MAP:
                expanded_words.append(word)            # original first (exact match gets higher BM25)
                expanded_words.extend(self.ABBREVIATION_MAP[word])
            else:
                expanded_words.append(word)

        # Remove duplicates while preserving order
        seen = set()
        unique_words = []
        for w in expanded_words:
            if w not in seen:
                seen.add(w)
                unique_words.append(w)

        # Build OR query for flexibility
        if unique_words:
            return " OR ".join(unique_words)
        return query

    def _create_match(self, row: tuple, query: str, include_json: bool,
                      user_profile: Optional[Dict[str, Any]] = None,
                      preferred_domains: Optional[List[str]] = None,
                      penalized_domains: Optional[List[str]] = None) -> WorkflowMatch:
        """Create WorkflowMatch from database row."""
        id_, name, description, domain, source, format_, step_count, tools_json, tags_json, filename, workflow_json, fts_score = row

        # Parse JSON fields
        try:
            tools = json.loads(tools_json) if tools_json else []
        except:
            tools = []

        try:
            tags = json.loads(tags_json) if tags_json else []
        except:
            tags = []

        # Calculate custom score — use LLM-derived domain lists when provided
        score = self._calculate_score(query, name, description or "", tools, tags, source, domain or "general", fts_score,
                                      user_profile=user_profile,
                                      preferred_domains=preferred_domains,
                                      penalized_domains=penalized_domains)
        match_type = self._classify_match(score)

        return WorkflowMatch(
            id=id_,
            name=name,
            description=description or "",
            domain=domain or "general",
            source=source or "unknown",
            format=format_ or "galaxy_ga",
            step_count=step_count or 0,
            tools=tools,
            tags=tags,
            score=score,
            match_type=match_type,
            filename=filename,
            workflow_json=workflow_json if include_json else None
        )

    def _expand_query(self, query: str) -> str:
        """Expand abbreviations in query for better matching."""
        words = query.lower().replace("-", " ").split()
        expanded = []
        for word in words:
            if word in self.ABBREVIATION_MAP:
                expanded.extend(self.ABBREVIATION_MAP[word])
            else:
                expanded.append(word)
        return " ".join(expanded)

    # Key phrases to boost when found in workflow names
    KEY_PHRASES = [
        'differential expression', 'variant calling', 'peak calling', 'quality control',
        'rna-seq', 'rnaseq', 'rna seq', 'chip-seq', 'chipseq', 'atac-seq', 'atacseq',
        'single cell', 'single-cell', 'methylation', 'assembly', 'alignment',
        'fastq', 'fasta', 'bam', 'vcf', 'proteomics', 'metabolomics',
        # Drug discovery / pharmacology
        'admet', 'admet pred', 'predict admet', 'toxicity screening',
        'herg', 'dili', 'drug safety', 'drug combination',
        'structure prediction', 'docking', 'binding affinity',
        'pharmacokinetic', 'nca', 'pknca', 'nlmixr',
        'scaffold hopping', 'qsar', 'drug like',
        'molecular docking', 'alphafold', 'diffdock', 'autodock',
    ]

    def _calculate_score(self,
                         query: str,
                         name: str,
                         description: str,
                         tools: List[str],
                         tags: List[str],
                         source: str,
                         workflow_domain: str,
                         fts_score: float,
                         user_profile: Optional[Dict[str, Any]] = None,
                         preferred_domains: Optional[List[str]] = None,
                         penalized_domains: Optional[List[str]] = None) -> float:
        """Calculate relevance score with source priority and phrase matching."""
        score = 0.0
        # Expand abbreviations in query for keyword matching
        query_expanded = self._expand_query(query)
        query_lower = query.lower()
        name_lower = name.lower().replace("-", " ").replace("_", " ")
        text = f"{name_lower} {description or ''} {' '.join(tools)} {' '.join(tags)}".lower()

        # 1. FTS score (normalized, ~30% weight)
        score += abs(fts_score) * 1.5

        # 2. Keyword matching (~25% weight) - use expanded query
        for keyword, weight in self.keyword_weights.items():
            if keyword in query_expanded and keyword in text:
                score += weight

        # 3. Phrase match bonus (~25% weight) - boost for key phrases in both query and name
        phrase_matches = 0
        for phrase in self.KEY_PHRASES:
            if phrase in query_expanded and phrase in name_lower:
                phrase_matches += 1
        if phrase_matches > 0:
            score += 5.0 + (phrase_matches * 3.0)  # Base 5 + 3 per phrase match

        # 4. Name word overlap (~15% weight) - also expand for name matching
        query_words = set(query_expanded.split())
        name_words = set(name_lower.split())
        overlap = len(query_words.intersection(name_words))
        score += overlap * 1.5

        # 4b. Exact / near-exact name match bonus — critical for "run nf-core/rnaseq" queries
        # Strip prefix like "nf-core/" so "rnaseq" matches "nf-core/rnaseq"
        bare_name = name_lower.split("/")[-1].replace("-", " ").replace("_", " ").strip()
        q_bare = query_lower.replace("nf-core/", "").replace("nf-core ", "").replace("-", " ").replace("_", " ").strip()
        if bare_name and q_bare:
            if bare_name == q_bare:
                score += 15.0  # Exact name match (e.g., query="rnaseq", name="nf-core/rnaseq")
            elif bare_name.startswith(q_bare) or q_bare.startswith(bare_name):
                score += 8.0   # Prefix match

        # 5. Source priority — boosted to make nfcore clearly win over bioconductor
        source_bonus = SOURCE_PRIORITY.get(source, 0) / 15.0  # ~6.7 max (nfcore=6.67, bioconductor=5.0)
        score += source_bonus

        # 5b. Pipeline intent boost: when user says "I have data to process",
        # full pipeline sources get a large bonus over package-level Bioconductor tools
        if self._detect_pipeline_intent(query):
            if source in ("nfcore", "nfcore_subwf", "biomni_nextflow"):
                score += 8.0
            elif source == "bioconductor":
                score -= 5.0  # Bioconductor R packages are unlikely to be what they need

        # 6. Domain preference bias (critical for avoiding cross-domain QC mismatches)
        # Use LLM-derived domain lists when provided (UQU output); fall back to rule-based inference.
        if preferred_domains is None and penalized_domains is None:
            inferred_pref, inferred_pen = self._infer_domain_preferences(query)
        else:
            inferred_pref = set(preferred_domains or [])
            inferred_pen = set(penalized_domains or [])
        domain_value = (workflow_domain or "general").lower()
        if domain_value in inferred_pref:
            score += 4.0
        if domain_value in inferred_pen:
            score -= 4.0

        # 7. User profile bias (starting bias; query context from step 6 takes precedence)
        # Only applied when query doesn't already express a strong domain preference.
        if user_profile:
            profile_domains = [d.lower() for d in (user_profile.get("domains") or [])]
            if profile_domains and not inferred_pref:
                # Normalise domain key: "single_cell" → matches workflow_domain "single_cell" etc.
                if domain_value in profile_domains:
                    score += 2.0

        return round(score, 2)

    def _classify_match(self, score: float) -> str:
        """Classify match confidence.

        Thresholds are module constants _MATCH_SCORE_HIGH / _MATCH_SCORE_MED.
        Calibrated to require meaningful keyword overlap:
        - high_confidence: Strong keyword matches + name overlap (score >= 12)
        - medium_confidence: Some keyword matches (score >= 6)
        - low_confidence: Weak matches that need adaptation
        """
        if score >= _MATCH_SCORE_HIGH:
            return "high_confidence"
        elif score >= _MATCH_SCORE_MED:
            return "medium_confidence"
        else:
            return "low_confidence"

    def _fallback_search(self,
                         query: str,
                         domain: Optional[str],
                         source: Optional[str],
                         format: Optional[str],
                         limit: int,
                         include_json: bool,
                         user_profile: Optional[Dict[str, Any]] = None) -> List[WorkflowMatch]:
        """Fallback to LIKE search if FTS fails."""
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            sql = """
                SELECT id, name, description, domain, source, format,
                       step_count, tools_used, tags, filename, workflow_json, 0.0 as fts_score
                FROM workflows
                WHERE name LIKE ? OR description LIKE ? OR tools_used LIKE ?
            """
            like_pattern = f"%{query}%"
            params = [like_pattern, like_pattern, like_pattern]

            if domain:
                sql += " AND domain = ?"
                params.append(domain)

            if source:
                sql += " AND source = ?"
                params.append(source)

            if format:
                sql += " AND format = ?"
                params.append(format)

            sql += " LIMIT ?"
            params.append(limit)

            cursor.execute(sql, params)
            rows = cursor.fetchall()

            results = []
            for row in rows:
                match = self._create_match(row, query, include_json, user_profile=user_profile)
                results.append(match)

            results.sort(key=lambda x: x.score, reverse=True)
            return results

        finally:
            conn.close()

    def get_workflow(self, workflow_id: int) -> Optional[WorkflowMatch]:
        """Get a specific workflow by ID."""
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute("""
                SELECT id, name, description, domain, source, format,
                       step_count, tools_used, tags, filename, workflow_json
                FROM workflows
                WHERE id = ?
            """, (workflow_id,))

            row = cursor.fetchone()
            if not row:
                return None

            # Add dummy fts_score
            row = row + (0.0,)
            return self._create_match(row, "", True)

        finally:
            conn.close()

    # ── Workflow chain API ────────────────────────────────────────────────────

    def _row_to_chain(self, row) -> "WorkflowChain":
        """Convert a DB row to a WorkflowChain dataclass."""
        return WorkflowChain(
            id              = row[0],
            name            = row[1],
            display_name    = row[2],
            domain          = row[3],
            description     = row[4] or "",
            steps           = json.loads(row[5] or "[]"),
            connections     = json.loads(row[6] or "[]"),
            required_inputs = json.loads(row[7] or "[]"),
            expected_outputs= json.loads(row[8] or "[]"),
            example_queries = json.loads(row[9] or "[]"),
            tags            = json.loads(row[10] or "[]"),
            source          = row[11] or "curated",
            usage_count     = row[12] or 0,
            success_rate    = row[13] or 0.0,
        )

    def _chain_select_cols(self) -> str:
        return (
            "id, name, display_name, domain, description, "
            "steps, connections, required_inputs, expected_outputs, "
            "example_queries, tags, source, usage_count, success_rate"
        )

    # ------------------------------------------------------------------
    # Chain embedding index helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _chain_embed_text(chain: "WorkflowChain") -> str:
        """Rich text for embedding: name + display_name + description + examples + tags.

        Including name and display_name ensures exact-name matches score very
        high even when description/examples are sparse.
        """
        parts = [
            chain.name.replace("_", " "),   # e.g. "bulk rnaseq de analysis"
            chain.display_name,              # e.g. "Bulk RNA-seq Differential Expression Analysis"
            chain.description or "",
        ]
        parts.extend(chain.example_queries)
        parts.extend(chain.tags)
        return ". ".join(p.strip() for p in parts if p.strip())

    def _rebuild_chain_embedding_index(self, chains: List["WorkflowChain"]) -> None:
        """Recompute the in-memory embedding index for all chains."""
        global _CHAIN_EMBED_MODEL, _CHAIN_EMBED_NAMES, _CHAIN_EMBED_MATRIX
        if not _EMBEDDINGS_AVAILABLE:
            return
        try:
            if _CHAIN_EMBED_MODEL is None:
                log.info("[ChainIndex] Loading %s for chain embedding search", _CHAIN_EMBED_MODEL_NAME)
                # Reuse VectorToolSearch's GPU-safe device detection when available;
                # fall back to cpu so we never block startup on a broken CUDA driver.
                try:
                    from .vector_search import _detect_device_safe
                    device = _detect_device_safe(timeout_seconds=5.0)
                except Exception:
                    device = "cpu"
                _CHAIN_EMBED_MODEL = _ST(_CHAIN_EMBED_MODEL_NAME, device=device)
            texts = [self._chain_embed_text(c) for c in chains]
            _CHAIN_EMBED_NAMES = [c.name for c in chains]
            _CHAIN_EMBED_MATRIX = _CHAIN_EMBED_MODEL.encode(
                texts, convert_to_numpy=True, show_progress_bar=False
            )
            log.info("[ChainIndex] Indexed %d chains", len(chains))
        except Exception as exc:
            log.warning("[ChainIndex] Failed to build embedding index: %s", exc)
            _CHAIN_EMBED_NAMES = []
            _CHAIN_EMBED_MATRIX = None

    def _cosine_search_chains(
        self,
        query: str,
        all_chains: List["WorkflowChain"],
        limit: int,
        min_similarity: float,
    ) -> List[Tuple[float, "WorkflowChain"]]:
        """Return (cosine_score, chain) pairs for chains above min_similarity."""
        global _CHAIN_EMBED_MODEL, _CHAIN_EMBED_NAMES, _CHAIN_EMBED_MATRIX
        if not _EMBEDDINGS_AVAILABLE or _CHAIN_EMBED_MODEL is None:
            return []

        # Rebuild index if chain set changed
        current_names = [c.name for c in all_chains]
        if current_names != _CHAIN_EMBED_NAMES:
            self._rebuild_chain_embedding_index(all_chains)

        if _CHAIN_EMBED_MATRIX is None or len(_CHAIN_EMBED_NAMES) == 0:
            return []

        try:
            q_emb = _CHAIN_EMBED_MODEL.encode([query], convert_to_numpy=True)[0]
            q_norm = q_emb / (_np.linalg.norm(q_emb) + 1e-9)
            mat_norm = _CHAIN_EMBED_MATRIX / (
                _np.linalg.norm(_CHAIN_EMBED_MATRIX, axis=1, keepdims=True) + 1e-9
            )
            sims = _np.dot(mat_norm, q_norm)
            top_idx = _np.argsort(sims)[::-1][:limit]
            name_to_chain = {c.name: c for c in all_chains}
            return [
                (float(sims[i]), name_to_chain[_CHAIN_EMBED_NAMES[i]])
                for i in top_idx
                if float(sims[i]) >= min_similarity and _CHAIN_EMBED_NAMES[i] in name_to_chain
            ]
        except Exception as exc:
            log.warning("[ChainIndex] Cosine search failed: %s", exc)
            return []

    def _llm_select_chain(
        self,
        query: str,
        candidates: List["WorkflowChain"],
    ) -> Optional[List["WorkflowChain"]]:
        """Ask the LLM to match the query against candidate chains with scope checking.

        Chains are multi-step clinical pipelines with broad scope.  The LLM must
        verify that the user's request clearly covers the FULL scope of the chain —
        not just one component.  If it is uncertain, it should ask for clarification
        rather than guessing.

        Returns:
          [chain]           — LLM confirmed a specific chain with high confidence
          [chain(clarify)]  — LLM wants to clarify before committing; chain has
                               clarification_needed=True and clarification_question set
          []                — LLM explicitly says no chain matches
          None              — LLM unavailable; caller falls back to embedding ranking

        Response format (LLM):
          "chain:<name>"          → confident match
          "clarify:<name>|<q>"   → match but needs one clarifying question first
          "none"                  → no match
        """
        if self._llm_client is None or not candidates:
            return None

        options = "\n".join(
            f"- {c.name}: {c.display_name}\n"
            f"  Scope: {(c.description or '')[:200]}\n"
            f"  Steps: {', '.join(s.get('workflow_name', '') or s.get('name', '') for s in c.steps[:5])}"
            for c in candidates
        )
        prompt = (
            f"You are a bioinformatics workflow router.\n"
            f"User request: \"{query}\"\n\n"
            f"Candidate multi-step chains:\n{options}\n\n"
            f"RULES:\n"
            f"1. A chain matches ONLY if the user's request clearly covers the chain's FULL scope (all major steps).\n"
            f"2. If a chain is a subset match (user asked for one component of a larger chain), do NOT select it — return 'none'.\n"
            f"3. If a chain likely matches but the query lacks key context (e.g. sample type, disease, data modality), "
            f"ask ONE short clarifying question.\n"
            f"4. Return EXACTLY one of:\n"
            f"   chain:<name>          (confident full-scope match)\n"
            f"   clarify:<name>|<question>   (probable match, need one detail)\n"
            f"   none                  (no chain fits or query is too narrow)\n"
            f"No other text."
        )
        try:
            raw = (self._llm_client.generate(prompt, max_tokens=60, temperature=0.0) or "").strip()
            log.info("[ChainIndex] LLM raw response: %r", raw)

            if raw.lower().startswith("chain:"):
                name = raw[6:].strip()
                for c in candidates:
                    if c.name == name or c.name in name:
                        log.info("[ChainIndex] LLM confident match: %s", c.name)
                        return [c]

            if raw.lower().startswith("clarify:"):
                body = raw[8:].strip()
                parts = body.split("|", 1)
                chain_name = parts[0].strip()
                question = parts[1].strip() if len(parts) > 1 else (
                    f"Could you confirm the full scope? This pipeline covers: "
                    f"{candidates[0].description[:120]}"
                )
                for c in candidates:
                    if c.name == chain_name or c.name in chain_name:
                        import copy
                        c_copy = copy.copy(c)
                        c_copy.clarification_needed = True
                        c_copy.clarification_question = question
                        log.info("[ChainIndex] LLM wants clarification for %s: %s", c.name, question)
                        return [c_copy]

            if "none" in raw.lower():
                log.info("[ChainIndex] LLM: no chain matches")
                return []

            log.warning("[ChainIndex] LLM response unrecognized: %r", raw)
            return None  # fall back to embedding ranking
        except Exception as exc:
            log.warning("[ChainIndex] LLM chain selection failed: %s", exc)
            return None

    # ------------------------------------------------------------------
    # Chain search — embedding similarity + LLM reranking
    # ------------------------------------------------------------------

    def search_chains(self, query: str, domain: Optional[str] = None,
                      limit: int = 3, min_score: float = 0.15) -> List["WorkflowChain"]:
        """Return workflow chains matching the query.

        Search pipeline (three tiers, each falling back to the next):

          Tier 1 — Embedding similarity (all-MiniLM-L6-v2 cosine, threshold 0.42):
            - Text per chain: name + display_name + description + example_queries + tags
            - Threshold is intentionally high: chains are broad pipelines and should only
              be considered when the query is semantically close to the whole chain scope
            - Yields a ranked shortlist (up to 3 candidates) passed to LLM
            - LLM checks full-scope match; may request clarification instead of guessing

          Tier 2 — Jaccard token overlap (fallback when embeddings unavailable):
            - Includes name + display_name tokens in addition to description/examples/tags
            - min_score threshold applied

        The chain name and display_name are always included in matching text so that
        exact or near-exact name references in the user query score very high.
        """
        all_chains = self.list_chains(domain=domain)
        if not all_chains:
            return []

        # ── Tier 1: embedding similarity ──────────────────────────────────────
        if _EMBEDDINGS_AVAILABLE:
            # Lazily build index on first call
            if not _CHAIN_EMBED_NAMES:
                self._rebuild_chain_embedding_index(all_chains)

            embed_results = self._cosine_search_chains(
                query, all_chains, limit=min(3, len(all_chains)),
                min_similarity=_CHAIN_EMBED_MIN_SIMILARITY,
            )
            if embed_results:
                top_candidates = [c for _, c in embed_results]
                log.info(
                    "[ChainIndex] Embedding top-%d for %r: %s",
                    len(top_candidates), query[:60],
                    [c.name for c in top_candidates],
                )
                # LLM reranking from short candidate list
                # Returns [chain] (match), [] (explicit no-match), or None (unavailable)
                llm_result = self._llm_select_chain(query, top_candidates)
                if llm_result is not None:
                    return llm_result  # trust LLM decision (including explicit [])
                # LLM unavailable — trust embedding ranking
                return top_candidates[:limit]

        # ── Tier 2: Jaccard fallback ───────────────────────────────────────────
        def _expand_tokens(text: str) -> set:
            raw = re.findall(r"[a-z0-9]+", text.lower())
            expanded: set = set()
            for w in raw:
                if w in _SEARCH_STOPWORDS or len(w) <= 1:
                    continue
                expanded.add(w)
                if w in self.ABBREVIATION_MAP:
                    expanded.update(self.ABBREVIATION_MAP[w])
            return expanded

        query_tokens = _expand_tokens(query)
        scored: List[Tuple[float, "WorkflowChain"]] = []
        for chain in all_chains:
            chain_tokens: set = set()
            # Include name + display_name (the fix: these were not used before)
            chain_tokens.update(_expand_tokens(chain.name))
            chain_tokens.update(_expand_tokens(chain.display_name))
            for eq in chain.example_queries:
                chain_tokens.update(_expand_tokens(eq))
            chain_tokens.update(_expand_tokens(chain.description or ""))
            chain_tokens.update(_expand_tokens(" ".join(chain.tags)))

            overlap = len(query_tokens & chain_tokens)
            union   = len(query_tokens | chain_tokens) or 1
            jaccard = overlap / union
            precision = overlap / len(query_tokens) if query_tokens else 0.0
            score = max(jaccard, precision * 0.7) if len(query_tokens) >= 8 else jaccard
            domain_bonus = 0.05 if (chain.domain and chain.domain == domain) else 0.0
            scored.append((min(score + domain_bonus, 1.0), chain))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [c for s, c in scored[:limit] if s >= min_score]

    def get_chain(self, name: str) -> Optional["WorkflowChain"]:
        """Fetch a chain by its unique name."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                f"SELECT {self._chain_select_cols()} FROM workflow_chains WHERE name=?",
                (name,),
            )
            row = cursor.fetchone()
            return self._row_to_chain(row) if row else None
        finally:
            conn.close()

    def record_chain_run(self, chain_name: str, success: bool) -> None:
        """Update usage_count and rolling success_rate for a chain after execution."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "SELECT usage_count, success_rate FROM workflow_chains WHERE name=?",
                (chain_name,),
            )
            row = cursor.fetchone()
            if not row:
                return
            old_count, old_rate = row
            new_count = old_count + 1
            # Exponential moving average with α=0.1 for stability
            new_rate = old_rate * 0.9 + (1.0 if success else 0.0) * 0.1
            cursor.execute(
                "UPDATE workflow_chains SET usage_count=?, success_rate=?, updated_at=? WHERE name=?",
                (new_count, new_rate, datetime.utcnow().isoformat(), chain_name),
            )
            conn.commit()
        finally:
            conn.close()

    def list_chains(self, domain: Optional[str] = None) -> List["WorkflowChain"]:
        """List all curated chains, optionally filtered by domain."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            sql = f"SELECT {self._chain_select_cols()} FROM workflow_chains"
            params: list = []
            if domain:
                sql += " WHERE domain=?"
                params.append(domain)
            sql += " ORDER BY usage_count DESC, name"
            cursor.execute(sql, params)
            return [self._row_to_chain(r) for r in cursor.fetchall()]
        finally:
            conn.close()

    def get_stats(self) -> Dict[str, Any]:
        """Get workflow index statistics."""
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute("SELECT COUNT(*) FROM workflows")
            total = cursor.fetchone()[0]

            cursor.execute("SELECT source, COUNT(*) FROM workflows GROUP BY source")
            by_source = dict(cursor.fetchall())

            cursor.execute("SELECT domain, COUNT(*) FROM workflows GROUP BY domain ORDER BY COUNT(*) DESC LIMIT 10")
            by_domain = dict(cursor.fetchall())

            cursor.execute("SELECT format, COUNT(*) FROM workflows GROUP BY format")
            by_format = dict(cursor.fetchall())

            # Chain stats
            try:
                cursor.execute("SELECT COUNT(*) FROM workflow_chains")
                chain_total = cursor.fetchone()[0]
                cursor.execute("SELECT domain, COUNT(*) FROM workflow_chains GROUP BY domain")
                chains_by_domain = dict(cursor.fetchall())
            except sqlite3.OperationalError:
                chain_total = 0
                chains_by_domain = {}

            return {
                "total": total,
                "by_source": by_source,
                "by_domain": by_domain,
                "by_format": by_format,
                "chains": {"total": chain_total, "by_domain": chains_by_domain},
            }

        finally:
            conn.close()

    def list_domains(self) -> List[str]:
        """List all available domains."""
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute("SELECT DISTINCT domain FROM workflows WHERE domain IS NOT NULL ORDER BY domain")
            return [row[0] for row in cursor.fetchall()]
        finally:
            conn.close()


# Singleton instance
_search_instance: Optional[UnifiedWorkflowSearch] = None


def get_workflow_search() -> UnifiedWorkflowSearch:
    """Get the unified workflow search instance."""
    global _search_instance
    if _search_instance is None:
        _search_instance = UnifiedWorkflowSearch()
    return _search_instance


# CLI for testing
if __name__ == "__main__":
    import sys

    search = UnifiedWorkflowSearch()

    print("=" * 60)
    print("Unified Workflow Search - Test")
    print("=" * 60)
    print()

    # Show stats
    stats = search.get_stats()
    print(f"Total workflows: {stats['total']}")
    print(f"By source: {stats['by_source']}")
    print()

    # Test searches
    test_queries = [
        "RNA-seq differential expression",
        "variant calling SNP",
        "single-cell RNA",
        "proteomics DIA",
        "ChIP-seq peak calling",
    ]

    for query in test_queries:
        print(f"Query: '{query}'")
        print("-" * 40)
        results = search.search(query, limit=5)

        for i, match in enumerate(results, 1):
            print(f"  {i}. [{match.source}] {match.name}")
            print(f"     Domain: {match.domain}, Score: {match.score}, Type: {match.match_type}")
        print()
