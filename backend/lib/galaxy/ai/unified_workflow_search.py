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
_CHAIN_EMBED_MIN_SIMILARITY = 0.60  # raised from 0.50 — prevents tumor_reactive_t_cell_chain from capturing neoantigen prediction queries

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
    _CHAIN_EMBED_DESC_HASH: str = ""              # hash of chain descriptions for cache invalidation
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

# ------------------------------------------------------------------
# Workflow-level dense retrieval (BGE embeddings)
# Mirrors the VectorToolSearch (vector_search.py) pattern but covers
# the 2449-workflow index instead of the tools table.
# ------------------------------------------------------------------
# Embedding model — same as VectorToolSearch.DEFAULT_MODEL so both
# sub-systems share the weights file.
_WORKFLOW_EMBED_MODEL_NAME = "BAAI/bge-small-en-v1.5"
# .npz path — stored next to galaxy_ai_tools.db
_WORKFLOW_EMBED_NPZ: Optional[Path] = None  # set once DB_PATH is known

# Module-level singletons — shared across all UnifiedWorkflowSearch instances
# so embeddings are only loaded once per process.
# Serializes the one-time embedding-model loads so a startup warmup thread and a
# racing first request can't both pay the ~8-10s SentenceTransformer load (each
# would clobber the global). The warm path early-returns BEFORE taking the lock,
# so steady-state searches are never serialized on it.
import threading as _threading
_EMBED_INIT_LOCK = _threading.Lock()
_WF_EMBED_MODEL: Optional[Any] = None       # SentenceTransformer instance
_WF_EMBED_IDS: List[int] = []              # workflow DB ids in index order
_WF_EMBED_MATRIX: Optional[Any] = None     # np.ndarray (n_workflows × dim)
_WF_EMBED_READY: bool = False              # True once load/build succeeds
_WF_EMBED_FAILED: bool = False             # True after a permanent init failure; prevents retry

# Minimum cosine similarity for dense-retrieval candidates.
# Only workflows with cosine ≥ 0.55 receive any bonus — high-confidence semantic matches only.
_WF_DENSE_MIN_SIM: float = 0.55
# How many dense candidates to retrieve per query (pre-filter).
_WF_DENSE_TOP_N: int = 40
# Score bonus weight for dense similarity (sim * _WF_DENSE_BONUS_WEIGHT).
# Calibrated at 0.5 so max bonus = 0.5 (negligible vs FTS scores of 40+).
# This acts purely as a tiebreaker between FTS-tied workflows — verified
# to produce identical rankings to weight=0.0 on a 12-query representative sample.
# Dense rescue is disabled (if False) until FTS description quality is improved
# for domains where rescue causes wrong-workflow inflation (RNA-seq, scRNA-seq).
_WF_DENSE_BONUS_WEIGHT: float = 0.5

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


# ------------------------------------------------------------------
# Execution-quality bonus (B-4: "Routing prefers runnable")
# ------------------------------------------------------------------
# The workflows table carries per-workflow execution-status columns produced
# by the Bioconductor exec-verification harness. Ranking historically ignored
# them, so a workflow that *fails to execute* could outrank an equally-relevant
# one that runs cleanly. This helper turns those columns into a SMALL additive
# bonus that is folded into _calculate_score.
#
# DESIGN INVARIANTS (why this is safe):
#   * The bonus is capped at ±2.0. The semantic signals dominate by 1-2 orders
#     of magnitude (FTS×1.5 ≈ 30-60, exact-name +15, prefix-name +8, phrase
#     +5..+8, domain ±4). A runnable-but-IRRELEVANT workflow can therefore never
#     out-rank a relevant one — the bonus only re-orders near-ties.
#   * Null / unknown status AND null verdict → 0.0 (neutral, NEVER a penalty).
#     The DB has ~1671 workflows with NULL real_exec_status; they must not be
#     pushed below scored-bad ones for lack of data.
#   * `real_exec_provisional == 1` (~860 rows) means the status was assumed, not
#     observed. POSITIVE bonuses are halved in that case; PENALTIES stay full
#     (a provisional failure is still evidence of breakage).
#   * Status is authoritative; the correctness verdict is only consulted as a
#     fallback when status is absent.
_EXEC_BONUS_CAP = 2.0

# Observed-execution status → bonus (positive = runs cleanly, negative = breaks).
_EXEC_STATUS_BONUS = {
    "ok":               2.0,   # executed cleanly
    "ok_warnings":      1.5,   # executed with non-fatal warnings
    "ran_empty_output": 0.5,   # ran but produced no output — weakly positive
    "runnable_assumed": 0.5,   # static analysis says runnable, not yet executed
    "exec_error":      -2.0,   # crashed at runtime
    "timeout":         -1.5,   # exceeded wall-clock limit
    "fixture_failed":  -1.5,   # test fixture / inputs could not be staged
    # "skip_input_type" / None → 0.0 (no execution signal, neutral)
}

# Correctness verdict → bonus. Only used as a FALLBACK when status is absent.
_EXEC_VERDICT_BONUS = {
    "executable":    1.0,
    "correct":       1.0,
    "pass":          0.5,
    "minor_issues":  0.0,
    "major_issues": -1.0,
    "parse_error":  -1.5,
}


def _exec_quality_bonus(status: Optional[str],
                        verdict: Optional[str],
                        provisional: Optional[Any]) -> float:
    """Map per-workflow execution-status columns to a small additive bonus.

    Args:
        status:      ``real_exec_status`` (e.g. 'ok', 'exec_error', None).
        verdict:     ``workflow_correctness_verdict`` (e.g. 'executable', None).
                     Consulted ONLY when ``status`` yields no signal.
        provisional: ``real_exec_provisional`` (0/1/None). When truthy, positive
                     bonuses are halved; penalties are unaffected.

    Returns:
        A float in [-_EXEC_BONUS_CAP, +_EXEC_BONUS_CAP]. Returns 0.0 for any
        null/unknown combination — never a penalty for missing data.

    Null-safe: any unexpected type is coerced or ignored without raising.
    """
    bonus = 0.0

    status_key = (status or "").strip().lower() if isinstance(status, str) else ""
    if status_key in _EXEC_STATUS_BONUS:
        bonus = _EXEC_STATUS_BONUS[status_key]
    else:
        # No usable status → fall back to the correctness verdict.
        verdict_key = (verdict or "").strip().lower() if isinstance(verdict, str) else ""
        bonus = _EXEC_VERDICT_BONUS.get(verdict_key, 0.0)

    # Provisional status is weaker evidence: halve POSITIVE bonuses only.
    try:
        is_provisional = bool(int(provisional)) if provisional is not None else False
    except (TypeError, ValueError):
        is_provisional = bool(provisional)
    if is_provisional and bonus > 0.0:
        bonus *= 0.5

    # Clamp to the cap so this signal can never dominate semantic relevance.
    if bonus > _EXEC_BONUS_CAP:
        bonus = _EXEC_BONUS_CAP
    elif bonus < -_EXEC_BONUS_CAP:
        bonus = -_EXEC_BONUS_CAP
    return round(bonus, 2)


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

            # Single-cell — core
            'single-cell': 3.0, 'scrna': 3.0, 'scrnaseq': 3.0,
            'scanpy': 2.5, 'seurat': 2.5, 'cellranger': 2.5,
            # Single-cell — multimodal instruments
            'cite-seq': 4.0, 'citeseq': 4.0, 'adt': 3.5, 'totalseq': 4.0,
            'antibody-derived': 3.5, 'dsb normalization': 4.0, 'dsb normaliz': 3.5,
            'wnn': 3.0, 'weighted nearest neighbour': 3.5, 'weighted nearest neighbor': 3.5,
            'multiome': 4.0, 'cell ranger arc': 4.0, 'chromvar': 3.5,
            'peak-to-gene': 3.5, 'peak to gene': 3.5, 'tf motif': 3.5,
            'rhapsody': 4.0, 'bd rhapsody': 4.5, 'abseq': 4.0, 'microwell': 3.5,
            'parse biosciences': 4.5, 'evercode': 4.5, 'split-pool': 4.0,
            'splitseq': 4.0, 'split seq': 4.0, 'combinatorial barcoding': 4.0,
            'merfish': 5.0, 'seqfish': 4.5, 'merscope': 5.0, 'vizgen': 5.0,
            'subcellular': 4.0, 'subcellular resolution': 4.5, 'subcellular rna': 5.0,
            'molecule detection': 4.0, 'rna molecule': 4.0, 'transcript detection': 3.5,
            'imaging-based spatial': 4.5, 'image-based spatial': 4.5,
            'not spot': 4.0, 'not spot-based': 4.5,
            'cellpose': 3.5, 'baysor': 3.5, 'spatially variable': 3.5,
            # Doublet detection
            'doubletfinder': 4.5, 'doublet finder': 4.5, 'scrublet': 4.5,
            'doublet detection': 4.0, 'doublet removal': 4.0, 'doublets': 3.5,
            'multiplet': 3.5, 'cell multiplet': 4.0, 'pann score': 4.0,
            # Licensed tool wrappers — high priority when user names the tool
            # Boost is intentionally high (25+) so the named-tool workflow beats the
            # BioMate-native implementation even when the native one has a higher FTS
            # base score (e.g. pk_sim_pbpk vs pbpk_simulation: ~22 pt FTS gap).
            'simcyp': 25.0, 'pk-sim': 25.0, 'pksim': 25.0, 'open systems pharmacology': 20.0,
            'osp suite': 20.0, 'certara pbpk': 25.0,
            'nonmem': 25.0, 'nmfe75': 25.0, 'population pk nonmem': 25.0,
            'gastroplus': 5.0, 'gastro plus': 5.0, 'simulations plus pbpk': 4.5,
            'fep+': 5.0, 'fep plus': 5.0, 'schrodinger fep': 5.0, 'free energy perturbation': 4.5,
            'stardrop': 5.0, 'optibrium': 4.5, 'nova generative': 4.5,
            'monolix': 5.0, 'lixoft': 4.5, 'saem estimation': 4.0,
            # Bispecific antibody
            'bispecific': 5.0, 'bsab': 5.0, 'bite': 4.5, 'bispecific t-cell engager': 5.0,
            'crossmab': 5.0, 'dart bispecific': 5.0, 'dvd-ig': 4.5, 'dvd ig': 4.5,
            'knob-into-hole': 4.5, 'knob into hole': 4.5, 'knob hole': 4.5,
            'nanobody fusion': 4.5, 'vhh fusion': 4.5, 'dual antigen': 4.0,
            'two targets': 3.5, 'dual blockade': 4.0, 'cd3 arm': 4.5,
            'blinatumomab': 4.5, 'faricimab': 4.5, 'amivantamab': 4.5,
            # siRNA off-target
            'sirna': 5.0, 'si rna': 5.0, 'sirna off-target': 5.0, 'off-target silencing': 5.0,
            'seed region': 4.5, 'risc': 4.0, 'rnai off-target': 5.0, 'passenger strand': 4.5,
            "2'-ome": 4.0, "2'-o-methyl": 4.0, '2ome modification': 4.5,
            'esc chemistry': 4.5, 'inclisiran': 4.5, 'givosiran': 4.5,
            'tlr7 tlr8': 4.5, 'tlr immune stimulation': 4.5, 'sirna immunogenicity': 4.5,

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

            # Drug MoA RNA-seq
            'drug moa': 4.5, 'moa rnaseq': 4.5, 'drug moa rnaseq': 5.0,
            'mechanism of action rnaseq': 4.5, 'mechanism action rna': 4.0,
            'drug mechanism rnaseq': 4.5, 'drug effect rna': 3.5,

            # Pharmacovigilance / FAERS signal detection
            'faers': 4.0, 'pharmacovigilance': 4.0, 'disproportionality': 4.0,
            'ror': 3.5, 'prr': 3.5, 'reporting odds ratio': 4.0,
            'proportional reporting ratio': 4.0, 'adverse drug reaction': 3.5,
            'signal detection': 3.5, 'spontaneous reporting': 3.5,
            'drug safety surveillance': 3.5, 'post-marketing surveillance': 3.5,

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

    def _ensure_workflows_table(self):
        """Create the workflows table if it doesn't exist (prevents crash on fresh/empty DB)."""
        conn = self._get_connection()
        try:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS workflows (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    filename TEXT UNIQUE NOT NULL,
                    description TEXT, annotation TEXT, tags TEXT,
                    domain TEXT, workflow_json TEXT NOT NULL DEFAULT '{}',
                    step_count INTEGER, tools_used TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    source TEXT DEFAULT 'unknown', format TEXT DEFAULT 'galaxy_ga',
                    executable INTEGER DEFAULT 1, docker_image TEXT, category TEXT,
                    workflow_hash TEXT, indexed_at TEXT,
                    input_types TEXT DEFAULT '[]', output_types TEXT DEFAULT '[]',
                    annotation_v2 TEXT, step_metadata TEXT, params_schema TEXT
                )
            """)
            conn.commit()
            self._migrate_schema(conn)
            count = conn.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
            if count == 0:
                log.warning("[WorkflowSearch] workflows table is EMPTY — workflow suggestions unavailable until the DB is synced")
            else:
                log.info("[WorkflowSearch] workflows table OK: %d entries", count)
        finally:
            conn.close()

    def _migrate_schema(self, conn: sqlite3.Connection):
        """Add missing columns and tables to an existing database without re-indexing."""
        cursor = conn.cursor()

        # Add missing columns to workflows table (ALTER TABLE ignores existing columns via try/except)
        existing_cols = {row[1] for row in cursor.execute("PRAGMA table_info(workflows)")}
        for col, definition in [
            ("input_types",                 "TEXT DEFAULT '[]'"),
            ("output_types",                "TEXT DEFAULT '[]'"),
            ("annotation_v2",               "TEXT"),
            ("step_metadata",               "TEXT"),
            ("params_schema",               "TEXT"),
            ("real_exec_status",            "TEXT"),
            ("real_exec_at",                "TEXT"),
            ("real_exec_produced",          "INTEGER"),
            ("real_exec_err",               "TEXT"),
            ("real_exec_provisional",       "INTEGER DEFAULT 0"),
            ("workflow_correctness_score",  "REAL"),
            ("workflow_correctness_verdict","TEXT"),
        ]:
            if col not in existing_cols:
                cursor.execute(f"ALTER TABLE workflows ADD COLUMN {col} {definition}")
                log.info("[WorkflowSearch] migrated: added column workflows.%s", col)

        # Create workflow_chains table if absent — normally created by index_all_workflows.py
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS workflow_chains (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL,
                display_name TEXT,
                description TEXT,
                domain TEXT,
                steps TEXT NOT NULL DEFAULT '[]',
                tags TEXT DEFAULT '[]',
                input_schema TEXT DEFAULT '{}',
                output_schema TEXT DEFAULT '{}',
                usage_count INTEGER DEFAULT 0,
                success_rate REAL DEFAULT 0.0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.commit()
        log.info("[WorkflowSearch] schema migration complete")

    def _ensure_fts_index(self):
        """Ensure FTS index exists and is populated."""
        self._ensure_workflows_table()
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
                SELECT w.id, w.name, COALESCE(w.description, '') as description,
                       w.source, w.filename
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

        # Format catalog for LLM — include source and whether it is a complete
        # pipeline vs a helper subworkflow, so the model can reason about scope.
        # A "subworkflow" handles one step; a "pipeline" is end-to-end.
        SOURCE_LABELS = {
            "nfcore":          "nf-core pipeline",
            "nfcore_subwf":    "nf-core subworkflow",
            "biomni_nextflow": "BioMate pipeline",
            "bioconductor":    "Bioconductor R package",
            "biomate":         "BioMate pipeline",
        }
        catalog_lines = []
        for wf_id, name, desc, source, filename in rows:
            short_desc = (desc or "")[:120].replace("\n", " ")
            base_label = SOURCE_LABELS.get(source or "", "pipeline")
            # Detect subworkflows from filename path — they are helper steps, not
            # standalone tools the user would invoke directly.
            is_subwf = "/subworkflows/" in (filename or "")
            kind = "subworkflow (pipeline component)" if is_subwf else base_label
            catalog_lines.append(f"{wf_id}. [{kind}] {name}: {short_desc}")
        catalog_text = "\n".join(catalog_lines)

        prompt = (
            f"You are a bioinformatics workflow recommender.\n"
            f"User query: {query}\n\n"
            f"Candidate workflows (id. [type] name: description):\n{catalog_text}\n\n"
            f"Ranking guidance:\n"
            f"- Users want complete, end-to-end pipelines that run their analysis from start to finish.\n"
            f"- Prefer [nf-core pipeline] entries — these are community-standard, peer-reviewed pipelines.\n"
            f"- Never rank a [subworkflow (pipeline component)] above a complete pipeline that covers "
            f"the same analysis. Subworkflows are implementation details inside larger pipelines; they "
            f"are not standalone tools a user would run directly.\n"
            f"- If an nf-core pipeline and a subworkflow both match the query, always prefer the pipeline.\n"
            f"- EXPLICIT TOOL REQUEST: If the query says 'using <Tool>', 'run <Tool>', or 'with <Tool>' "
            f"as the primary method, rank that tool's workflow #1. "
            f"  POSITIVE: 'run DiffDock on my protein' → DiffDock workflow should be #1. "
            f"  POSITIVE: 'using HADDOCK for docking' → HADDOCK workflow should be #1. "
            f"  NEGATIVE: 'benchmark DiffDock or HADDOCK' → the user is comparing tools, "
            f"not requesting DiffDock specifically; pick the workflow that best fits the overall goal.\n"
            f"  NEGATIVE: 'like DiffDock but for cyclic peptides' → the user is describing style, "
            f"not requesting DiffDock; pick the cyclic peptide workflow.\n\n"
            f"Return ONLY a JSON array of the {output_limit} workflow IDs (integers) "
            f"that best match the user query, ordered by relevance (best first). "
            f"Example: [42, 7, 15]. No explanation, just the JSON array."
        )

        try:
            # Use the fast model (fallbacks[0] from config) for Pass-0: cheap
            # ranking call that doesn't need thinking-model quality. Falls back
            # to the primary automatically if the fast model fails.
            raw = self._llm_client.generate(prompt, max_tokens=512, temperature=0.0,
                                            use_fast_model=True)
            # Extract JSON array from the response (strip any surrounding text)
            import re as _re
            m = _re.search(r"\[[\d,\s]+\]", raw or "")
            if not m:
                # Fallback: handle truncated responses like '[149' (missing closing bracket)
                bare_ids = [int(x) for x in _re.findall(r'\d+', raw or '') if x.strip()]
                if bare_ids:
                    log.debug("[Pass-0] Extracted %d IDs from partial LLM response: %r", len(bare_ids), raw)
                    ids = bare_ids
                else:
                    log.debug("[Pass-0] LLM response has no JSON array: %r", raw)
                    return []
            else:
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

        # ── Dense pre-filter: BGE cosine retrieval ─────────────────────────
        # Runs independently of FTS. Returns {id: cosine_sim} for the top
        # _WF_DENSE_TOP_N workflows above _WF_DENSE_MIN_SIM.  Empty dict when
        # the embedding index is unavailable — all downstream logic degrades
        # gracefully to FTS-only.
        dense_sim_map: Dict[int, float] = self._dense_workflow_prefilter(query)

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
                       bm25(workflows_fts) as fts_score,
                       w.input_types, w.output_types,
                       w.real_exec_status, w.workflow_correctness_verdict, w.real_exec_provisional
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
                bonus = 0.0
                # ── Pass-0 boost: workflows the LLM ranked get a graded bonus ──
                # rank 0 → +3.0, rank 1 → +2.7, ..., rank 9 → +0.3
                if llm_rank_map and row[0] in llm_rank_map:
                    rank = llm_rank_map[row[0]]
                    bonus += max(0.0, 3.0 - 0.3 * rank)
                # ── Dense cosine bonus: BGE similarity scales up the score ──
                # Additive — neither replaces FTS nor overrides named-anchor.
                # sim=0.3 → +1.5, sim=0.5 → +2.5, sim=0.7 → +3.5, sim=0.8 → +4.0
                if dense_sim_map and row[0] in dense_sim_map:
                    bonus += dense_sim_map[row[0]] * _WF_DENSE_BONUS_WEIGHT
                if bonus > 0.0:
                    new_score = round(match.score + bonus, 2)
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
                        score=new_score,
                        # Re-classify after bonus so match_type reflects actual final score.
                        # Without this, a workflow scoring 10.0+4.0=14.0 would still be
                        # labeled medium_confidence and incorrectly trigger the disambiguation gate.
                        match_type=self._classify_match(new_score),
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
                               0.0 as fts_score,
                               w.input_types, w.output_types,
                               w.real_exec_status, w.workflow_correctness_verdict, w.real_exec_provisional
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

            # ── Dense rescue: DISABLED ──────────────────────────────────────
            # Dense rescue was adding semantically similar but wrong workflows
            # (e.g. bulk_rnaseq_de_analysis above nf-core/rnaseq) causing P@1
            # regression from 0.742 → 0.417.  Dense bonus on FTS-found hits is
            # kept (above); rescue block disabled until tuning is complete.
            if False and dense_sim_map:
                seen_ids = {m.id for m in results}
                dense_only_ids = [wf_id for wf_id in dense_sim_map if wf_id not in seen_ids]
                if dense_only_ids:
                    placeholders = ",".join("?" * len(dense_only_ids))
                    dense_rescue_sql = f"""
                        SELECT w.id, w.name, w.description, w.domain, w.source, w.format,
                               w.step_count, w.tools_used, w.tags, w.filename, w.workflow_json,
                               0.0 as fts_score,
                               w.input_types, w.output_types,
                               w.real_exec_status, w.workflow_correctness_verdict, w.real_exec_provisional
                        FROM workflows w
                        WHERE w.id IN ({placeholders})
                    """
                    try:
                        dr_conn = self._get_connection()
                        dr = dr_conn.cursor()
                        dr.execute(dense_rescue_sql, dense_only_ids)
                        dr_rows = dr.fetchall()
                        dr_conn.close()
                        for row in dr_rows:
                            m = self._create_match(row, query, include_workflow_json,
                                                   user_profile=user_profile,
                                                   preferred_domains=preferred_domains,
                                                   penalized_domains=penalized_domains)
                            sim = dense_sim_map.get(row[0], _WF_DENSE_MIN_SIM)
                            # Synthetic score: source_priority base + cosine bonus
                            # (no FTS contribution since these were not in FTS results)
                            m = WorkflowMatch(
                                id=m.id, name=m.name, description=m.description,
                                domain=m.domain, source=m.source, format=m.format,
                                step_count=m.step_count, tools=m.tools, tags=m.tags,
                                filename=m.filename, workflow_json=m.workflow_json,
                                score=round(sim * _WF_DENSE_BONUS_WEIGHT, 2),
                                match_type="dense_rescued",
                            )
                            results.append(m)
                        if dr_rows:
                            results.sort(key=lambda x: x.score, reverse=True)
                            log.debug(
                                "[WorkflowEmbed] Dense rescue added %d workflows not in FTS",
                                len(dr_rows),
                            )
                    except Exception as exc:
                        log.debug("[WorkflowEmbed] Dense rescue fetch failed: %s", exc)

            # Remove workflows the user explicitly negated (e.g. "NOT mhcquant").
            negated_slugs = self._extract_negated_pipeline_slugs(query)
            if negated_slugs:
                filtered = [
                    m
                    for m in results
                    if self._normalise_pipeline_slug(m.name.split("/")[-1]) not in negated_slugs
                ]
                if filtered:
                    results = filtered

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
        'cite': ['cite', 'seq', 'antibody', 'adt'],  # CITE-seq
        'adt': ['antibody', 'derived', 'tag', 'cite', 'seq'],
        'wnn': ['weighted', 'nearest', 'neighbour', 'multimodal'],
        'dsb': ['dsb', 'normalization', 'adt', 'background'],
        'merfish': ['merfish', 'spatial', 'transcriptomics', 'imaging'],
        'codex': ['codex', 'spatial', 'protein', 'imaging'],
        'tbi': ['total', 'based', 'imaging'],  # image-based spatial
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

        # Proteomics (mass spectrometry) — must come before drug_discovery check
        # DIA-NN, Spectronaut, OpenSWATH = DIA proteomics; MaxQuant, Fragpipe = DDA proteomics
        # "data-independent acquisition" and "data-dependent acquisition" are MS terms, NOT sequencing.
        proteomics_tokens = [
            'dia-nn', 'spectronaut', 'openswath', 'maxquant', 'fragpipe', 'msfragger',
            'proteomics', 'proteomic', 'mass spectrometry', 'mass spec', 'mzml', 'mzxml',
            'data-independent acquisition', 'data-dependent acquisition',
            'dia proteomics', 'dda proteomics', 'label-free quantification', 'lfq proteomics',
            'tmt proteomics', 'itraq', 'phosphoproteomics', 'phosphoproteomic',
            'raw thermo', 'thermo raw', '.raw files', 'orbitrap',
        ]
        if any(tok in q for tok in proteomics_tokens):
            preferred.update({'proteomics', 'biochemistry'})
            # Critical: penalize transcriptomics (RNA-seq) for proteomics queries to prevent
            # "data-independent acquisition" → RNA-seq misrouting
            penalized.update({'transcriptomics', 'metagenomics'})

        # Drug discovery / pharmacology / structural biology
        drug_tokens = ['docking', 'autodock', 'vina', 'diffdock', 'alphafold', 'structure prediction',
                       'binding affinity', 'admet', 'herg', 'dili', 'pharmacokinetic', 'nca', 'pknca',
                       'drug', 'ligand', 'scaffold', 'smiles', 'molecular docking']
        if any(tok in q for tok in drug_tokens):
            preferred.update({'drug_discovery', 'biochemistry', 'structural_biology'})
            penalized.update({'microbiology', 'metagenomics', 'transcriptomics'})

        return preferred, penalized

    # Tokens that signal "I have raw data to process" or "I want to run a pipeline"
    # Signals that the user has RAW sequencing data (FASTQ/BAM) needing alignment/preprocessing.
    # Only these justify penalizing Bioconductor packages, which operate on processed data.
    # NOTE: Generic phrases like "analyze my", "I have" are NOT here — many Bioconductor tools
    # ARE the correct primary analysis tool for count matrices, microbiome data, single-cell
    # downstream analysis, etc. The penalty must only fire for raw-data-format evidence.
    _RAW_DATA_INTENT_SIGNALS = [
        # Explicit raw format mentions
        '.fastq', 'fastq', 'fastq.gz', 'fast5', 'pod5',  # sequencing reads
        'raw reads', 'raw sequencing', 'raw data from sequencer',
        'bam file', '.bam ', 'cram file', '.cram ',       # aligned reads (still upstream of R)
        'from sequencing', 'off the sequencer', 'we sequenced',
        # Sequencing protocol names — these imply raw FASTQ data
        # (users with these protocols need a full alignment pipeline, not R packages)
        'rrbs', 'wgbs', 'em-seq', 'emseq', 'rrbs-seq',   # bisulfite sequencing methods
        'bisulfite seq', 'bisulfite-seq',
        'cut&run', 'cutandrun', 'cut&tag', 'cutandtag',   # antibody-tethered nuclease methods
        'chip-seq reads', 'chip seq reads', 'atac-seq reads',
        'drop-seq', 'dropseq', 'smart-seq', 'smartseq', 'indrop',  # scRNA-seq protocols
        '10x chromium', 'seq-well', 'dip-c',
        # CRISPR screens require NGS of sgRNA libraries — raw sequencing intent
        'crispr screen', 'crispr knockout screen', 'knockout screen', 'crispr pooled',
        # Explicitly wants full pipeline from raw
        'run a pipeline', 'run the full pipeline', 'run nf-core', 'nextflow run',
        'run sarek', 'run rnaseq', 'run methylseq', 'run chipseq', 'run atacseq',
        'do rna-seq', 'do rna seq', 'do chip-seq', 'do atac-seq', 'do wgs', 'do wes',
        'perform whole genome', 'perform chip-seq', 'perform atac-seq',
        'execute pipeline', 'execute variant calling', 'execute rna-seq',
    ]

    def _detect_pipeline_intent(self, query: str) -> bool:
        """Return True when the user has raw sequencing data (FASTQ/BAM) needing a full pipeline.

        Only raw-data-format signals trigger Bioconductor penalty. Generic phrases like
        "analyze my data" or "I have count data" do NOT trigger this — Bioconductor packages
        (ALDEx2, ANCOMBC, miloR, etc.) are the correct primary tools for downstream analysis
        and have no nfcore equivalents for those tasks.
        """
        q = query.lower()
        return any(signal in q for signal in self._RAW_DATA_INTENT_SIGNALS)

    @staticmethod
    def _normalise_pipeline_slug(raw: str) -> str:
        return re.sub(r"[^a-z0-9]", "", (raw or "").lower())

    def _extract_negated_pipeline_slugs(self, query: str) -> set:
        """Slugs the user explicitly excluded (e.g. 'NOT mhcquant', 'not epitope prediction')."""
        negated: set = set()
        q = query.lower()
        for m in re.finditer(
            r"\b(?:not|avoid|never|don'?t\s+use|instead\s+of)\s+"
            r"(?:nf[\s\-]?core[/\s]+)?([a-z][a-z0-9_\s-]+?)"
            r"(?:\s+or|\s+and|,|\.|$|\)|—)",
            q,
        ):
            phrase = m.group(1).strip()
            phrase_compact = self._normalise_pipeline_slug(phrase)
            if phrase_compact:
                negated.add(phrase_compact)
            first_token = phrase.split()[0] if phrase else ""
            first_compact = self._normalise_pipeline_slug(first_token)
            if first_compact:
                negated.add(first_compact)
        return negated

    def _extract_explicit_pipeline_slug(self, query: str) -> Optional[str]:
        """Return an nf-core pipeline slug when the user explicitly types 'nf-core/X' or 'nfcore X'.

        Only matches the nf-core path format to avoid false positives from loose word-scanning.
        Negated slugs (e.g. 'NOT rnaseq') are excluded from the result.
        """
        negated = self._extract_negated_pipeline_slugs(query)
        q = query.lower()
        found: List[str] = []
        for m in re.finditer(r"nf[\s\-]?core[/\s]+([a-z][a-z0-9_-]+)", q):
            slug = self._normalise_pipeline_slug(m.group(1))
            if slug and slug not in negated:
                found.append(slug)
        if not found:
            return None
        seen: set = set()
        unique = [s for s in found if not (s in seen or seen.add(s))]  # type: ignore[func-returns-value]
        return unique[0] if unique else None

    # ------------------------------------------------------------------
    # Dense retrieval — BGE workflow embeddings
    # ------------------------------------------------------------------

    def _ensure_workflow_embeddings(self) -> bool:
        """Load (or build) the BGE workflow embedding index.

        Returns True when the index is ready, False on any failure.
        Uses module-level singletons so the index is built at most once per
        process regardless of how many UnifiedWorkflowSearch instances exist.

        Staleness contract (added 2026-06-13 — see
        docs/20260613_DENSE_EMBEDDINGS_PATHS.md §6):

          - On load, we re-derive a content signature from the live DB
            and compare it against the signature stamped into the .npz
            at build time. Mismatch → rebuild.
          - The signature is a SHA-256 over the same (id, name,
            description, annotation) tuples the build uses to encode
            text, so it catches BOTH row-count drift AND in-place
            edits.
          - Computing the signature is a single SQL SELECT + a hash
            pass over ~4k strings (~5-10 ms). Cheap relative to the
            ~67 s rebuild it prevents.
          - When the .npz pre-dates this contract (no signature
            metadata), we trust the existing file and just check
            row-count parity as the minimum bar — first opportunity
            to upgrade lands the signature in the saved .npz so the
            next process gets the full check for free.
        """
        global _WF_EMBED_MODEL, _WF_EMBED_IDS, _WF_EMBED_MATRIX, _WF_EMBED_READY, _WF_EMBED_FAILED, _WORKFLOW_EMBED_NPZ

        if _WF_EMBED_READY:
            return True
        if _WF_EMBED_FAILED or not _EMBEDDINGS_AVAILABLE:
            return False

        # Serialize the cold init (model load + index build) so the warmup thread
        # and a first request don't double-load. Re-check readiness after taking
        # the lock — the thread that lost the race returns immediately.
        # Use a 5 s timeout: when a rebuild is running in another thread (67 s+),
        # concurrent requests fall back to FTS-only rather than blocking the SSE
        # stream for the entire rebuild duration.
        acquired = _EMBED_INIT_LOCK.acquire(timeout=5)
        if not acquired:
            log.debug("[WorkflowEmbed] Init lock busy — FTS-only fallback for this request")
            return _WF_EMBED_READY
        try:
            if _WF_EMBED_READY:
                return True
            if _WF_EMBED_FAILED:
                return False
            return self._ensure_workflow_embeddings_locked()
        finally:
            _EMBED_INIT_LOCK.release()

    def _ensure_workflow_embeddings_locked(self) -> bool:
        global _WF_EMBED_MODEL, _WF_EMBED_IDS, _WF_EMBED_MATRIX, _WF_EMBED_READY, _WF_EMBED_FAILED, _WORKFLOW_EMBED_NPZ
        try:
            # Resolve .npz path next to the DB
            if _WORKFLOW_EMBED_NPZ is None:
                _WORKFLOW_EMBED_NPZ = self.db_path.parent / "galaxy_ai_workflow_embeddings.npz"

            # Load model only when the shared embed server is unavailable.
            # When the server is running (gunicorn on_starting hook), workers
            # delegate encode() calls to it and skip loading ~300 MB of weights.
            if _WF_EMBED_MODEL is None:
                try:
                    from galaxy.ai.embed_client import get_client as _get_embed_client
                    if _get_embed_client().available():
                        log.info("[WorkflowEmbed] Embed server available — skipping in-process model load")
                    else:
                        raise RuntimeError("embed server unavailable")
                except Exception:
                    log.info("[WorkflowEmbed] Loading model %s …", _WORKFLOW_EMBED_MODEL_NAME)
                    _WF_EMBED_MODEL = _ST(_WORKFLOW_EMBED_MODEL_NAME, device="cpu",
                                          local_files_only=True)

            if _WORKFLOW_EMBED_NPZ.exists():
                self._load_workflow_embeddings()
                # Staleness check: did the DB drift since the .npz was built?
                # At runtime we never rebuild — that is a deploy-time operation
                # handled by sync_to_dev.sh after galaxy_ai_tools.db is updated.
                # A stale NPZ means the deploy step was skipped; fall back to
                # FTS-only for this request rather than blocking for 60-120 s.
                if self._workflow_embeddings_stale():
                    log.warning(
                        "[WorkflowEmbed] NPZ is stale vs DB — run sync_to_dev.sh "
                        "to rebuild. Using FTS-only search until next deploy."
                    )
                    return False
            else:
                log.warning(
                    "[WorkflowEmbed] NPZ not found at %s — run sync_to_dev.sh "
                    "to build it. Using FTS-only search.", _WORKFLOW_EMBED_NPZ
                )
                return False

            _WF_EMBED_READY = (
                _WF_EMBED_MATRIX is not None
                and len(_WF_EMBED_IDS) > 0
            )
            if _WF_EMBED_READY:
                log.info(
                    "[WorkflowEmbed] Ready: %d workflows, dim=%d",
                    len(_WF_EMBED_IDS),
                    _WF_EMBED_MATRIX.shape[1],
                )
            return _WF_EMBED_READY
        except Exception as exc:
            _WF_EMBED_FAILED = True  # don't retry on every search call
            log.warning("[WorkflowEmbed] Init failed (dense retrieval disabled): %s", exc)
            return False

    # ------------------------------------------------------------------
    # Staleness detection
    # ------------------------------------------------------------------

    def _compute_workflow_db_signature(self) -> tuple:
        """Compute (row_count, sha256_hex) over the DB's workflow rows.

        Hashes the same (id, name, description, annotation) tuples
        _build_workflow_embeddings reads, so any change that would
        affect the encoded text shows up as a different signature.
        """
        import hashlib as _hashlib
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id, COALESCE(name,''), COALESCE(description,''), "
            "COALESCE(domain,''), COALESCE(tags,''), COALESCE(annotation,'') "
            "FROM workflows ORDER BY id"
        )
        rows = cursor.fetchall()
        conn.close()
        h = _hashlib.sha256()
        for r in rows:
            # Use a delimiter that can't appear in normal text fields
            h.update("\x1e".join(str(x) for x in r).encode("utf-8", errors="replace"))
            h.update(b"\x1f")
        return len(rows), h.hexdigest()

    def _workflow_embeddings_stale(self) -> bool:
        """True iff the loaded .npz no longer matches the live DB.

        Compares:
          1) row count — fast, catches new/removed workflows
          2) signature — catches in-place edits to name/description/etc.
             when present in the .npz metadata (built post-2026-06-13).

        Conservative on missing metadata: pre-signature .npz files pass
        the check on row-count alone; the next rebuild lands the
        signature so subsequent loads get the full check.
        """
        try:
            db_count, db_sig = self._compute_workflow_db_signature()
        except Exception as exc:
            log.warning("[WorkflowEmbed] DB signature failed (treating as fresh): %s", exc)
            return False

        if db_count != len(_WF_EMBED_IDS):
            log.info(
                "[WorkflowEmbed] Row-count drift: DB=%d .npz=%d",
                db_count, len(_WF_EMBED_IDS),
            )
            return True

        # Optional signature check — only present on .npz files built
        # post-2026-06-13. Absence is NOT stale (back-compat).
        try:
            data = _np.load(str(_WORKFLOW_EMBED_NPZ), allow_pickle=True)
            stored = data.get("workflow_signature")
            if stored is not None:
                stored_sig = stored.item() if hasattr(stored, "item") else str(stored)
                if stored_sig != db_sig:
                    log.info(
                        "[WorkflowEmbed] Content signature mismatch (stored=%s.. live=%s..)",
                        str(stored_sig)[:12], db_sig[:12],
                    )
                    return True
        except Exception as exc:
            log.warning("[WorkflowEmbed] Signature read failed: %s", exc)

        return False

    def _load_workflow_embeddings(self) -> None:
        global _WF_EMBED_IDS, _WF_EMBED_MATRIX
        log.info("[WorkflowEmbed] Loading from %s", _WORKFLOW_EMBED_NPZ)
        data = _np.load(str(_WORKFLOW_EMBED_NPZ), allow_pickle=True)
        _WF_EMBED_IDS = [int(x) for x in data["workflow_ids"]]
        _WF_EMBED_MATRIX = data["embeddings"]
        log.info("[WorkflowEmbed] Loaded %d workflow embeddings", len(_WF_EMBED_IDS))

    def _build_workflow_embeddings(self) -> None:
        """Encode all workflows and persist to disk as .npz.

        Stamps a content signature into the .npz so subsequent loads
        can detect staleness without re-encoding (see §6 of
        docs/20260613_DENSE_EMBEDDINGS_PATHS.md).
        """
        global _WF_EMBED_IDS, _WF_EMBED_MATRIX

        log.info("[WorkflowEmbed] Building embedding index for all workflows …")
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id, name, COALESCE(description,''), COALESCE(domain,''), "
            "COALESCE(tags,''), COALESCE(annotation,'') FROM workflows"
        )
        rows = cursor.fetchall()
        conn.close()

        if not rows:
            log.warning("[WorkflowEmbed] No workflows found — skipping")
            return

        ids, texts = [], []
        for wf_id, name, desc, domain, tags, annotation in rows:
            ids.append(int(wf_id))
            # Build rich text: combine all textual fields (same strategy as VectorToolSearch)
            parts = []
            if name:
                parts.append(name)
            if desc:
                parts.append(desc[:600])
            if domain:
                parts.append(f"Domain: {domain}")
            if tags:
                parts.append(f"Tags: {tags}")
            if annotation and annotation != desc:
                parts.append(annotation[:300])
            texts.append(". ".join(parts))

        log.info("[WorkflowEmbed] Encoding %d workflows with %s …", len(texts), _WORKFLOW_EMBED_MODEL_NAME)
        matrix = _WF_EMBED_MODEL.encode(
            texts,
            batch_size=64,
            show_progress_bar=False,
            convert_to_numpy=True,
        )

        _WF_EMBED_IDS = ids
        _WF_EMBED_MATRIX = matrix

        # Compute the same signature _workflow_embeddings_stale will
        # check against on load. Stored as a 0-dim object array so np
        # round-trips it cleanly.
        try:
            _, sig = self._compute_workflow_db_signature()
        except Exception as exc:
            log.warning("[WorkflowEmbed] Signature compute on save failed: %s", exc)
            sig = ""

        # Persist
        _np.savez_compressed(
            str(_WORKFLOW_EMBED_NPZ),
            workflow_ids=_np.array(ids, dtype=_np.int64),
            embeddings=matrix,
            workflow_signature=_np.array(sig, dtype=object),
        )
        log.info(
            "[WorkflowEmbed] Saved %d embeddings to %s (sig=%s..)",
            len(ids), _WORKFLOW_EMBED_NPZ, sig[:12] if sig else "none",
        )

    def _dense_workflow_prefilter(
        self,
        query: str,
        top_n: int = _WF_DENSE_TOP_N,
        min_sim: float = _WF_DENSE_MIN_SIM,
    ) -> Dict[int, float]:
        """Return {workflow_id: cosine_similarity} for the top-N BGE hits.

        Returns an empty dict when the embedding index is unavailable so the
        caller falls back to pure FTS without raising.
        """
        if not self._ensure_workflow_embeddings():
            return {}
        try:
            # Prefer the shared embed server; fall back to in-process model.
            q_vec = None
            try:
                from galaxy.ai.embed_client import get_client as _get_embed_client
                q_vec = _get_embed_client().encode_wf(query)
            except Exception:
                pass
            if q_vec is None:
                if _WF_EMBED_MODEL is None:
                    return {}
                q_vec = _WF_EMBED_MODEL.encode([query], convert_to_numpy=True)[0]
            q_norm = q_vec / (_np.linalg.norm(q_vec) + 1e-9)
            mat_norms = _np.linalg.norm(_WF_EMBED_MATRIX, axis=1, keepdims=True) + 1e-9
            mat_norm = _WF_EMBED_MATRIX / mat_norms
            sims = mat_norm.dot(q_norm)           # shape: (n_workflows,)
            # Top-N above threshold
            valid = _np.where(sims >= min_sim)[0]
            if len(valid) == 0:
                return {}
            top_idx = valid[_np.argsort(sims[valid])[::-1][:top_n]]
            return {_WF_EMBED_IDS[i]: float(sims[i]) for i in top_idx}
        except Exception as exc:
            log.debug("[WorkflowEmbed] Dense prefilter error: %s", exc)
            return {}

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
        # Unpack length-tolerantly: the first 14 fields are always present; the
        # trailing execution-quality columns (real_exec_status,
        # workflow_correctness_verdict, real_exec_provisional) are appended by
        # the candidate SELECTs but may be absent for callers using an older
        # SELECT shape. Missing → None → neutral 0.0 exec bonus.
        (id_, name, description, domain, source, format_, step_count,
         tools_json, tags_json, filename, workflow_json, fts_score,
         input_types_json, output_types_json) = row[:14]
        real_exec_status = row[14] if len(row) > 14 else None
        workflow_correctness_verdict = row[15] if len(row) > 15 else None
        real_exec_provisional = row[16] if len(row) > 16 else None

        # Parse JSON fields
        try:
            tools = json.loads(tools_json) if tools_json else []
        except:
            tools = []

        try:
            tags = json.loads(tags_json) if tags_json else []
        except:
            tags = []

        try:
            input_types = json.loads(input_types_json) if input_types_json else []
        except:
            input_types = []

        # Subworkflow detection: these are pipeline components, not standalone tools.
        # Using filename path as the structural signal — no keyword matching.
        is_subworkflow = (
            source == "nfcore_subwf"
            or "/subworkflows/" in (filename or "")
        )

        # Calculate custom score — use LLM-derived domain lists when provided
        score = self._calculate_score(query, name, description or "", tools, tags, source, domain or "general", fts_score,
                                      user_profile=user_profile,
                                      preferred_domains=preferred_domains,
                                      penalized_domains=penalized_domains,
                                      input_types=input_types,
                                      is_subworkflow=is_subworkflow,
                                      real_exec_status=real_exec_status,
                                      workflow_correctness_verdict=workflow_correctness_verdict,
                                      real_exec_provisional=real_exec_provisional)
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
        'epitope prediction', 'epitopeprediction', 'mhc binding', 'immunoinformatics',
        'neoepitope', 'mhcnuggets',
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
                         penalized_domains: Optional[List[str]] = None,
                         input_types: Optional[List[str]] = None,
                         is_subworkflow: bool = False,
                         real_exec_status: Optional[str] = None,
                         workflow_correctness_verdict: Optional[str] = None,
                         real_exec_provisional: Optional[Any] = None) -> float:
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

        # 3. Phrase match bonus (~25% weight) - boost for key phrases in both query and name/desc
        # Normalize description too (remove hyphens so "rna-seq" matches query "rna seq").
        # Use word-boundary check (' phrase ') to avoid false substring matches
        # (e.g. 'rna seq' inside 'scrna seq').
        desc_norm = (description or '').lower().replace('-', ' ')
        phrase_haystack = ' ' + name_lower + ' ' + desc_norm + ' '
        padded_query = ' ' + query_expanded + ' '
        phrase_matches = 0
        for phrase in self.KEY_PHRASES:
            padded = ' ' + phrase + ' '
            if padded in padded_query and padded in phrase_haystack:
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
            elif len(bare_name) >= 6 and bare_name in q_bare:
                score += 12.0  # Name appears as substring in query (e.g., "Generate the drug_moa_rnaseq workflow")

        # 4c. Explicit negation — user said "not X" or "avoid X"
        negated_slugs = self._extract_negated_pipeline_slugs(query_lower)
        if self._normalise_pipeline_slug(name_lower.split("/")[-1]) in negated_slugs:
            score -= 35.0

        # 5. Source priority — boosted to make nfcore clearly win over bioconductor
        source_bonus = SOURCE_PRIORITY.get(source, 0) / 15.0  # ~6.7 max (nfcore=6.67, bioconductor=5.0)
        score += source_bonus

        # 5b. Pipeline intent boost: when user says "I have data to process",
        # full pipeline sources get a large bonus over package-level Bioconductor tools.
        # Subworkflows (helper steps inside a larger pipeline) get NO boost — users
        # want complete pipelines, not individual processing components.
        # Subworkflow detection: filename path contains '/subworkflows/' (structural signal).
        if self._detect_pipeline_intent(query):
            if is_subworkflow:
                score -= 4.0  # Subworkflows compete unfairly with full pipelines; penalise
            elif source in ("nfcore", "biomni_nextflow"):
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

        # 8. Input-type compatibility scoring (soft boost/penalty using DB input_types field).
        # Only applied when the workflow has clean, non-channel input_types (skip "ch_*" names).
        if input_types:
            # Normalise: lowercase, strip whitespace; skip Nextflow channel names (ch_*)
            wf_types = frozenset(
                t.lower().strip() for t in input_types
                if t and not t.lower().strip().startswith("ch_")
            )
            if wf_types:
                user_types = self._detect_query_data_types(query)
                if user_types:
                    overlap = user_types & wf_types
                    if overlap:
                        score += 3.0  # user has exactly the right input type
                    elif (user_types & self._RAW_TYPES) and (wf_types & self._PROCESSED_TYPES):
                        score -= 4.0  # user has raw data but workflow needs processed input
                    elif (user_types & self._PROCESSED_TYPES) and not (user_types & self._RAW_TYPES) and (wf_types & self._RAW_TYPES):
                        score -= 4.0  # user has processed data only but workflow needs raw input

        # 9. Preferred/legacy tag scoring — steer generic queries toward the AI-backed version
        tags_lower = [t.lower() for t in (tags or [])]
        if "preferred" in tags_lower:
            score += 4.0  # AI/ML version always ranked above legacy equivalents
        if "legacy" in tags_lower:
            # Only penalise if the user isn't explicitly asking for the old version by name
            if "legacy" not in query_lower and "admet_pred" not in query_lower.replace(" ", "_"):
                score -= 6.0

        # 10. Execution-quality bonus (B-4: "Routing prefers runnable").
        # Small additive signal (capped at ±2.0) from per-workflow exec-status
        # columns: prefer workflows that actually run, gently down-weight ones
        # that crash/timeout. Null/unknown → 0.0 (neutral). This is well below
        # the semantic signals above, so it only re-orders near-ties and can
        # never let a runnable-but-irrelevant workflow outrank a relevant one.
        score += _exec_quality_bonus(
            real_exec_status, workflow_correctness_verdict, real_exec_provisional
        )

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
                       step_count, tools_used, tags, filename, workflow_json, 0.0 as fts_score,
                       input_types, output_types,
                       real_exec_status, workflow_correctness_verdict, real_exec_provisional
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
                       step_count, tools_used, tags, filename, workflow_json,
                       0.0 as fts_score, input_types, output_types,
                       real_exec_status, workflow_correctness_verdict, real_exec_provisional
                FROM workflows
                WHERE id = ?
            """, (workflow_id,))

            row = cursor.fetchone()
            if not row:
                return None

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
        """Rich text for embedding: name + display_name + description + examples + tags
        + required_inputs summary.

        Including name and display_name ensures exact-name matches score very
        high even when description/examples are sparse.
        Including required_inputs type names lets the embedding distinguish
        chains that need raw FASTQ from those that need processed outputs.
        """
        parts = [
            chain.name.replace("_", " "),   # e.g. "bulk rnaseq de analysis"
            chain.display_name,              # e.g. "Bulk RNA-seq Differential Expression Analysis"
            chain.description or "",
        ]
        # Include required input type names (e.g. "cellranger_output h5ad directory")
        # so queries mentioning raw data types (fastq, bam) score lower for chains
        # that require processed inputs.
        if chain.required_inputs:
            # Legacy rows (bioc_*_v2 chains) store required_inputs as plain strings
            # like "count_matrix"; canonical form is a list of dicts with name/type/
            # description. Handle both so a single malformed row doesn't take down
            # the whole chain embedding index.
            def _inp_tokens(inp):
                if isinstance(inp, str):
                    return inp
                if isinstance(inp, dict):
                    return (f"{inp.get('name','')} {inp.get('type','')} "
                            f"{str(inp.get('description',''))[:40]}")
                return ""
            input_tokens = " ".join(_inp_tokens(inp) for inp in chain.required_inputs)
            parts.append(f"requires inputs: {input_tokens}")
        parts.extend(chain.example_queries)
        parts.extend(chain.tags)
        return ". ".join(p.strip() for p in parts if p.strip())

    def _rebuild_chain_embedding_index(self, chains: List["WorkflowChain"]) -> None:
        """Recompute the in-memory embedding index for all chains."""
        global _CHAIN_EMBED_MODEL, _CHAIN_EMBED_NAMES, _CHAIN_EMBED_MATRIX, _CHAIN_EMBED_DESC_HASH
        if not _EMBEDDINGS_AVAILABLE:
            return
        try:
            texts = [self._chain_embed_text(c) for c in chains]
            _CHAIN_EMBED_NAMES = [c.name for c in chains]
            import hashlib as _hashlib
            _CHAIN_EMBED_DESC_HASH = _hashlib.md5(
                "|".join(f"{c.name}:{c.description or ''}:{','.join(c.tags)}" for c in chains).encode()
            ).hexdigest()
            # Prefer the shared embed server for batch encoding; fall back to
            # in-process model load when the server is unavailable.
            matrix = None
            try:
                from galaxy.ai.embed_client import get_client as _get_embed_client
                matrix = _get_embed_client().encode_batch_chain(texts)
            except Exception:
                pass
            if matrix is None:
                if _CHAIN_EMBED_MODEL is None:
                    with _EMBED_INIT_LOCK:
                        if _CHAIN_EMBED_MODEL is None:
                            log.info("[ChainIndex] Loading %s for chain embedding search", _CHAIN_EMBED_MODEL_NAME)
                            try:
                                from .vector_search import _detect_device_safe
                                device = _detect_device_safe(timeout_seconds=5.0)
                            except Exception:
                                device = "cpu"
                            _CHAIN_EMBED_MODEL = _ST(_CHAIN_EMBED_MODEL_NAME, device=device,
                                                    local_files_only=True)
                matrix = _CHAIN_EMBED_MODEL.encode(
                    texts, convert_to_numpy=True, show_progress_bar=False
                )
            _CHAIN_EMBED_MATRIX = matrix
            log.info("[ChainIndex] Indexed %d chains (desc_hash=%s)", len(chains), _CHAIN_EMBED_DESC_HASH[:8])
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
        global _CHAIN_EMBED_MODEL, _CHAIN_EMBED_NAMES, _CHAIN_EMBED_MATRIX, _CHAIN_EMBED_DESC_HASH
        if not _EMBEDDINGS_AVAILABLE or _CHAIN_EMBED_MODEL is None:
            return []

        # Rebuild index if chain set changed OR descriptions/tags changed
        import hashlib as _hashlib
        current_names = [c.name for c in all_chains]
        current_desc_hash = _hashlib.md5(
            "|".join(f"{c.name}:{c.description or ''}:{','.join(c.tags)}" for c in all_chains).encode()
        ).hexdigest()
        if current_names != _CHAIN_EMBED_NAMES or current_desc_hash != _CHAIN_EMBED_DESC_HASH:
            self._rebuild_chain_embedding_index(all_chains)

        if _CHAIN_EMBED_MATRIX is None or len(_CHAIN_EMBED_NAMES) == 0:
            return []

        try:
            # Prefer the shared embed server; fall back to in-process model.
            q_emb = None
            try:
                from galaxy.ai.embed_client import get_client as _get_embed_client
                q_emb = _get_embed_client().encode_chain(query)
            except Exception:
                pass
            if q_emb is None:
                if _CHAIN_EMBED_MODEL is None:
                    return []
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

    def _llm_judge_pair(
        self,
        query: str,
        chain_a: "WorkflowChain",
        chain_b: "WorkflowChain",
    ) -> str:
        """Robin-style pairwise comparison. Returns 'A' / 'B' / 'tie'.

        Used by _pairwise_tournament. Single LLM call per invocation — caller
        runs 3 times for majority voting (see Robin paper, Nature 2026:
        early versions of Robin tried LLM-as-judge absolute scoring; rejected
        for calibration failure + position bias; pairwise + 3-run voting
        chosen instead).
        """
        if self._llm_client is None:
            return "tie"

        def _format(c: "WorkflowChain") -> str:
            steps = ", ".join(
                s.get("workflow_name", "") or s.get("name", "")
                for s in (c.steps or [])[:5]
            )
            return (
                f"  Name: {c.name}\n"
                f"  Display: {c.display_name}\n"
                f"  Domain: {getattr(c, 'domain', '?')}\n"
                f"  Scope: {(c.description or '')[:200]}\n"
                f"  Steps: {steps}"
            )

        prompt = (
            f"You are a bioinformatics workflow router comparing two candidate chains.\n\n"
            f"User request: \"{query}\"\n\n"
            f"Chain A:\n{_format(chain_a)}\n\n"
            f"Chain B:\n{_format(chain_b)}\n\n"
            f"RULES:\n"
            f"1. Pick the chain whose FULL scope (domain + steps + data types) best matches the user's request.\n"
            f"2. A subset match (chain covers ONE component the user asked for, but not the rest) loses to a closer-domain match.\n"
            f"3. Cross-domain matches (e.g. variant-calling chain for a single-cell query) lose to in-domain matches even if one keyword overlaps.\n"
            f"4. Return EXACTLY one of these literal strings, with no other characters:\n"
            f"   A     (Chain A is the better match)\n"
            f"   B     (Chain B is the better match)\n"
            f"   tie   (neither is clearly better)\n"
            f"No prose. No punctuation. Just the letter or 'tie'."
        )
        try:
            raw = (self._llm_client.generate(prompt, max_tokens=8, temperature=0.0) or "").strip().upper()
            # Tolerate trailing punctuation / quotes
            raw = raw.rstrip(".,;:!?\"'`")
            if raw == "A":
                return "A"
            if raw == "B":
                return "B"
            if raw.startswith("TIE") or raw == "T":
                return "tie"
            log.warning(f"[ChainIndex] pairwise judge returned unrecognized: {raw!r}; treating as tie")
            return "tie"
        except Exception as exc:
            log.warning(f"[ChainIndex] pairwise judge LLM call failed: {exc}; treating as tie")
            return "tie"

    def _pairwise_tournament(
        self,
        query: str,
        candidates: List["WorkflowChain"],
        runs_per_pair: int = 3,
    ) -> Optional["WorkflowChain"]:
        """Round-robin pairwise tournament with majority voting per pair.

        Per Robin (Nature 2026): each pair is judged `runs_per_pair` times
        and the majority winner is recorded. Final winner is the candidate
        with the most pair wins; ties are broken by the candidates' original
        embedding rank (input order).

        For N candidates: N*(N-1)/2 pairs * runs_per_pair LLM calls.
        With the current limit=3 candidates and 3 runs/pair: 9 calls.
        """
        n = len(candidates)
        if n == 0:
            return None
        if n == 1:
            return candidates[0]

        wins: Dict[str, int] = {c.name: 0 for c in candidates}
        for i in range(n):
            for j in range(i + 1, n):
                a, b = candidates[i], candidates[j]
                # 3-run majority voting per pair (Robin's recipe)
                votes = {"A": 0, "B": 0, "tie": 0}
                for _ in range(runs_per_pair):
                    votes[self._llm_judge_pair(query, a, b)] += 1
                if votes["A"] > votes["B"] and votes["A"] >= votes["tie"]:
                    wins[a.name] += 1
                    log.info(f"[ChainIndex] tournament: {a.name} beats {b.name} ({votes})")
                elif votes["B"] > votes["A"] and votes["B"] >= votes["tie"]:
                    wins[b.name] += 1
                    log.info(f"[ChainIndex] tournament: {b.name} beats {a.name} ({votes})")
                else:
                    log.info(f"[ChainIndex] tournament: {a.name} vs {b.name} tied ({votes})")

        # Winner = most wins; ties broken by original embedding order (earlier wins)
        max_wins = max(wins.values())
        if max_wins == 0:
            # Total stalemate — fall back to embedding's top-1
            log.info("[ChainIndex] tournament: total stalemate; using embedding top-1")
            return candidates[0]
        for c in candidates:  # iterate in original order to break ties
            if wins[c.name] == max_wins:
                log.info(f"[ChainIndex] tournament winner: {c.name} ({max_wins} wins)")
                return c
        return candidates[0]  # unreachable

    def _llm_confirm_chain(
        self,
        query: str,
        chain: "WorkflowChain",
    ) -> str:
        """After tournament picks a winner, validate it's actually a match
        (not just "least bad"). Returns 'confirm' / 'clarify:<question>' /
        'none'.

        This is the same scope-check as the old single-shot _llm_select_chain
        but applied to ONE candidate (the tournament winner) instead of
        being asked to choose AND validate in one call. Cleaner separation
        of concerns; better calibrated.
        """
        if self._llm_client is None:
            return "none"

        def _format_inputs(c: "WorkflowChain") -> str:
            if not c.required_inputs:
                return "unspecified"
            return ", ".join(
                f"{inp.get('name','')} ({inp.get('type','')})"
                for inp in c.required_inputs[:3]
            )

        prompt = (
            f"You are a bioinformatics workflow router validating a chain match.\n\n"
            f"User request: \"{query}\"\n\n"
            f"Candidate chain: {chain.name}\n"
            f"  Display: {chain.display_name}\n"
            f"  Domain: {getattr(chain, 'domain', '?')}\n"
            f"  Scope: {(chain.description or '')[:200]}\n"
            f"  Required inputs: {_format_inputs(chain)}\n"
            f"  Steps: {', '.join(s.get('workflow_name', '') or s.get('name', '') for s in chain.steps[:5])}\n\n"
            f"RULES:\n"
            f"1. Confirm ONLY if the user's request clearly covers this chain's FULL scope (domain + all major steps).\n"
            f"2. If the chain is a subset match (user asked for one component of a larger chain), return 'none'.\n"
            f"3. If a key context is missing (e.g. sample type, disease, data modality), ask ONE short clarifying question.\n"
            f"4. Return EXACTLY one of these literal strings, with no other characters:\n"
            f"   confirm                    (full-scope match)\n"
            f"   clarify:<question>         (probable match, need one detail)\n"
            f"   none                       (no match or too narrow)\n"
            f"No prose."
        )
        try:
            raw = (self._llm_client.generate(prompt, max_tokens=60, temperature=0.0) or "").strip()
            log.info(f"[ChainIndex] confirm response for {chain.name}: {raw!r}")
            low = raw.lower()
            if low.startswith("confirm"):
                return "confirm"
            if low.startswith("clarify:"):
                return raw  # caller parses
            if low.startswith("none"):
                return "none"
            # Garbage → treat as no-match (safer than wrong-chain)
            log.warning(f"[ChainIndex] confirm unrecognized: {raw!r}; treating as none")
            return "none"
        except Exception as exc:
            log.warning(f"[ChainIndex] confirm LLM call failed: {exc}; treating as none")
            return "none"

    def _llm_select_chain(
        self,
        query: str,
        candidates: List["WorkflowChain"],
    ) -> Optional[List["WorkflowChain"]]:
        """Ask the LLM to pick the best chain in ONE call (rank + scope-confirm combined).

        Returns:
          [chain]           — LLM confirmed a specific chain with high confidence
          [chain(clarify)]  — LLM wants to clarify; chain has clarification_needed=True
          []                — no chain matches
          None              — LLM unavailable; caller falls back to embedding ranking

        Response format (LLM):
          "chain:<name>"          → confident match
          "clarify:<name>|<q>"   → match but needs one clarifying question first
          "none"                  → no match
        """
        if self._llm_client is None or not candidates:
            return None

        def _format_chain(c: "WorkflowChain") -> str:
            steps = ", ".join(
                s.get("workflow_name", "") or s.get("name", "")
                for s in (c.steps or [])[:5]
            )
            inputs = ", ".join(
                f"{inp.get('name', '')} ({inp.get('type', '')})"
                for inp in (c.required_inputs or [])[:3]
            ) or "unspecified"
            return (
                f"  Name: {c.name}\n"
                f"  Display: {c.display_name}\n"
                f"  Domain: {getattr(c, 'domain', '?')}\n"
                f"  Scope: {(c.description or '')[:200]}\n"
                f"  Inputs: {inputs}\n"
                f"  Steps: {steps}"
            )

        chain_block = "\n\n".join(
            f"Chain {i + 1}:\n{_format_chain(c)}" for i, c in enumerate(candidates)
        )
        names = [c.name for c in candidates]

        prompt = (
            f"You are a bioinformatics workflow router selecting the best pipeline chain.\n\n"
            f"User request: \"{query}\"\n\n"
            f"Candidates:\n{chain_block}\n\n"
            f"RULES:\n"
            f"1. Pick the candidate whose FULL scope (domain + all major steps + inputs) best matches the request.\n"
            f"2. Confirm ONLY if the user's request clearly covers the chosen chain's FULL scope.\n"
            f"3. A subset match (chain covers only ONE component the user asked for) → return 'none'.\n"
            f"4. A cross-domain match (e.g. variant-calling chain for a single-cell query) → return 'none'.\n"
            f"5. If a key context is missing (sample type, disease, data modality), ask ONE short clarifying question.\n"
            f"6. Return EXACTLY one of these literal strings (use the exact chain Name field):\n"
            f"   chain:<name>               (confident full-scope match)\n"
            f"   clarify:<name>|<question>  (probable match, need one detail)\n"
            f"   none                       (no chain matches or too narrow)\n"
            f"No prose. Just the literal string."
        )
        try:
            raw = (self._llm_client.generate(prompt, max_tokens=120, temperature=0.0,
                                            use_fast_model=True) or "").strip()
            log.info(f"[ChainIndex] select_chain response: {raw!r}")
            low = raw.lower()

            if low.startswith("chain:"):
                picked_name = raw[6:].strip()
                # Find candidate by name (exact, then prefix)
                winner = next((c for c in candidates if c.name == picked_name), None)
                if winner is None:
                    winner = next((c for c in candidates if c.name.startswith(picked_name)), None)
                if winner is None and candidates:
                    log.warning(f"[ChainIndex] LLM returned unknown chain name {picked_name!r}; using top candidate")
                    winner = candidates[0]
                log.info(f"[ChainIndex] select_chain confirmed: {winner.name}")
                return [winner]

            if low.startswith("clarify:"):
                rest = raw[8:].strip()
                if "|" in rest:
                    picked_name, question = rest.split("|", 1)
                    picked_name = picked_name.strip()
                    question = question.strip()
                else:
                    picked_name = rest.strip()
                    question = ""
                winner = next((c for c in candidates if c.name == picked_name), None)
                if winner is None and candidates:
                    winner = candidates[0]
                question = question or (
                    f"Could you confirm the full scope? This pipeline covers: "
                    f"{(winner.description or '')[:120]}"
                )
                import copy
                c_copy = copy.copy(winner)
                c_copy.clarification_needed = True
                c_copy.clarification_question = question
                log.info(f"[ChainIndex] clarification needed for {winner.name}: {question}")
                return [c_copy]

            log.info(f"[ChainIndex] no chain match: {raw!r}")
            return []
        except Exception as exc:
            log.warning(f"[ChainIndex] select_chain failed: {exc}; returning []")
            return []

    # ------------------------------------------------------------------
    # ── Data-type helpers — code-based input/output compatibility ──────────
    # Used by both chain filtering and workflow scoring.
    # ------------------------------------------------------------------

    # Raw/unprocessed data types a user might start with
    _RAW_TYPES: frozenset = frozenset({"fastq", "fq", "bam", "cram", "vcf", "bcf", "fastq.gz", "fq.gz"})
    # Processed/derived data types that result from a prior pipeline step
    _PROCESSED_TYPES: frozenset = frozenset({
        "directory", "h5ad", "h5", "mtx", "anndata", "cellranger_output",
        "count_matrix", "counts_matrix", "loom", "rds",
    })

    @staticmethod
    def _detect_query_data_types(query: str) -> frozenset:
        """Return the set of data types the user appears to have from query text.

        Only returns types the user *explicitly* mentions. Returns empty set when
        the query doesn't describe input data (e.g. pure analysis questions).
        """
        q = query.lower()
        types: set = set()
        if re.search(
            r'\bfastq\b|\.fastq|\.fq\b'             # explicit format
            r'|raw reads?|sequencing reads?'           # "raw reads", "sequencing reads"
            r'|raw sequencing\b|sequencing files?\b'  # "raw sequencing files", "sequencing files"
            r'|paired.end reads?'                      # "paired-end reads"
            r'|\balign\b.{0,40}\breads?\b'             # "align reads", "align the reads"
            r'|\breads?\b.{0,20}\balign'               # "reads to align"
            r'|\bseq(uencing)?\s+reads?\b',            # "seq reads", "sequencing reads"
            q
        ):
            types.add("fastq")
        if re.search(r'\b\.bam\b|bam files?|aligned reads?|sorted bam', q):
            types.add("bam")
        if re.search(r'\b\.cram\b|cram files?', q):
            types.add("cram")
        if re.search(r'\bvcf\b|\.vcf|variant calls?', q):
            types.add("vcf")
        # Only detect count_matrix when user is PROVIDING it as input (not generating it)
        # Exclude: "generate/produce/create/output a count matrix" (they want to produce it)
        count_m = re.search(r'count.?matri[cx]|counts.?matri[cx]|gene.?count|feature.count|expression matrix', q)
        if count_m:
            # Check if it's preceded by a generation verb → they're producing it, not providing it
            leading_text = q[max(0, count_m.start() - 40):count_m.start()]
            generation_verbs = ('generate', 'produce', 'creat', 'output', 'build', 'make', 'get')
            if not any(v in leading_text for v in generation_verbs):
                types.add("counts_matrix")
        if re.search(r'\.h5ad\b|h5ad|anndata|scanpy object', q):
            types.add("h5ad")
        if re.search(r'cell.?ranger output|cellranger output|10x output|\.h5 file|matrix\.mtx', q):
            types.add("cellranger_output")
        if re.search(r'\.pdb\b|protein structure|crystal structure', q):
            types.add("pdb")
        if re.search(r'\bsmiles\b|compound.?library|ligand.?library|\.sdf\b', q):
            types.add("smiles")
        return frozenset(types)

    @classmethod
    def _chain_input_compatible(cls, chain: "WorkflowChain", user_types: frozenset) -> bool:
        """Return False when user's data types are structurally incompatible with
        the chain's required_inputs.

        Specifically: if the user only has raw data (FASTQ/BAM/VCF) and the chain
        requires processed outputs (Cell Ranger directory, h5ad, count matrix, etc.),
        reject. This is a hard check — no LLM needed.

        When user_types is empty (query didn't mention explicit input data), returns
        True so we don't over-filter ambiguous queries.
        """
        if not chain.required_inputs or not user_types:
            return True
        # If user has only raw data but no processed data
        user_has_raw_only = bool(user_types & cls._RAW_TYPES) and not (user_types & cls._PROCESSED_TYPES)
        if not user_has_raw_only:
            return True
        # Check if any required input is a processed type
        for inp in chain.required_inputs:
            # required_inputs may be stored as plain strings (legacy bioc_*_v2 chains)
            # or as dicts with name/type/description — handle both safely.
            if isinstance(inp, str):
                inp_type = inp.lower()
            elif isinstance(inp, dict):
                inp_type = inp.get("type", "").lower()
            else:
                continue
            # Handle pipe-separated alternatives: "fastq|bam" → {"fastq","bam"}
            inp_subtypes = frozenset(t.strip() for t in inp_type.split("|"))
            if inp_subtypes & cls._PROCESSED_TYPES:
                return False
        return True

    # ── Per-chain required-context registry ──────────────────────────────────
    # Maps chain name → list of term-groups.  A chain is rejected if the user
    # query does not contain at least one term from EVERY listed group.
    # This prevents single-step "GATK germline calling" queries from triggering
    # multi-modal pipelines that also need RNA-seq, etc.
    _CHAIN_REQUIRED_CONTEXT: Dict[str, List[frozenset]] = {
        'rare_disease_multimodal_workup': [
            # Group 1: MUST signal rare disease or undiagnosed clinical context.
            frozenset({'rare disease', 'rare_disease', 'rare-disease', 'rare genetic',
                       'undiagnosed', 'unexplained', 'unresolved diagnosis',
                       'inherited disease', 'hereditary disease', 'mendelian',
                       'trio', 'proband'}),
            # Group 2: MUST also signal multi-modal data (WGS + RNA-seq).
            # This separates "rare disease variant calling" (→ nf-core/raredisease alone)
            # from "rare disease multi-modal workup" (WGS + RNA = this chain).
            frozenset({'rna-seq', 'rnaseq', 'rna seq', 'transcriptome', 'transcriptomic',
                       'rna data', 'outrider', 'fraser', 'drop',
                       'aberrant expression', 'splicing outlier',
                       'wgs and rna', 'wgs + rna', 'genome and transcriptome',
                       'multimodal', 'multi-modal', 'multi modal',
                       'paired wgs', 'paired rna'}),
        ],
        'cutandtag_chromatin_analysis': [
            # MUST signal CUT&Tag assay explicitly.
            # Prevents this chain from firing for ATAC-seq, Hi-C, scRNA-seq, ChIP-seq, or
            # any other chromatin/sequencing query that shares peak-calling / epigenomics
            # vocabulary but is NOT a CUT&Tag experiment.
            # Structural principle: chains require a specific assay signal, not just domain proximity.
            frozenset({'cut&tag', 'cutandtag', 'cut-and-tag', 'cuttag',
                       'cut & tag', 'pa-tn5', 'protein a-tn5', 'protein a tn5',
                       'cut and tag', 'cutntag'}),
        ],
        'bulk_rnaseq_de_analysis': [
            # MUST signal either (a) the user is explicitly requesting differential expression
            # analysis, OR (b) they clearly already have processed count data as input.
            # Queries about "processing raw RNA-seq samples" or "producing a counts matrix"
            # route to nf-core/rnaseq instead.
            # Avoids false-positive substring matches (e.g. "produce a gene counts matrix"
            # should NOT match — the user is producing counts, not inputting them).
            frozenset({'differential expression', 'differential abundance',
                       'deseq2', 'edger', 'limma', 'voom',
                       'de analysis', 'differentially expressed',
                       'salmon output', 'salmon quant', 'salmon quantification',
                       'kallisto output', 'my count table', 'my counts table',
                       'my count matrix', 'have a count', 'have counts',
                       'pathway enrichment', 'gsea', 'go enrichment', 'gene ontology',
                       'enrichment analysis', 'pathway analysis',
                       'upregulated', 'downregulated', 'differentially',
                       'fold change', 'log2fc', 'padj', 'fdr'}),
        ],
        'single_cell_multimodal_analysis': [
            # MUST signal single-cell assay explicitly.
            # Bulk RNA-seq queries ("process 30 bulk RNA-seq samples", "produce a gene counts
            # matrix") share vocabulary with this chain but describe completely different assays.
            # Required: user must mention single-cell sequencing technology, barcodes, or Cell Ranger.
            # EXCLUDED from this list: generic biology terms like "cell types", "clustering" that
            # appear in bulk RNA-seq analysis of heterogeneous samples.
            frozenset({'single cell', 'single-cell', 'scrnaseq', 'scrna-seq', 'scrna seq',
                       'sc-rnaseq', 'sc rna', '10x genomics', '10x chromium',
                       'cell ranger', 'cellranger', 'droplet-based', 'droplet sequencing',
                       'dropseq', 'drop-seq', 'smartseq', 'smart-seq', 'smart seq',
                       'indrops', 'seq-well', 'cell barcode', 'barcoded cells',
                       'cells per sample', 'per-cell reads', 'umi counts',
                       'scrnaseq qc', 'scanpy', 'seurat', 'anndata'}),
        ],
    }

    @classmethod
    def _chain_multimodal_context_compatible(cls, chain: "WorkflowChain", query: str) -> bool:
        """Return False if the query lacks required context terms for a multi-modal chain.

        Prevents a query like "GATK germline variant calling" from matching a chain
        that requires BOTH WGS and RNA-seq context.  Returns True for chains that have
        no context requirements defined (conservative: only filter chains we've explicitly
        annotated).
        """
        required_groups = cls._CHAIN_REQUIRED_CONTEXT.get(chain.name)
        if not required_groups:
            return True  # no constraint for this chain — pass through
        q_lower = query.lower()
        for term_group in required_groups:
            if not any(term in q_lower for term in term_group):
                log.info(
                    "[ChainIndex] Multi-modality filter: %r lacks required context for %s "
                    "(need one of: %s)", query[:60], chain.name, sorted(term_group)[:5],
                )
                return False
        return True

    # Chain search — embedding similarity + LLM reranking
    # ------------------------------------------------------------------

    def search_chains(self, query: str, domain: Optional[str] = None,
                      limit: int = 3, min_score: float = 0.25,
                      skip_llm_rerank: bool = False) -> List["WorkflowChain"]:
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
                # ── Code-based input-type pre-filter (before LLM) ─────────────
                # Hard-reject chains whose required_inputs are structurally
                # incompatible with what the user's query says they have.
                # E.g. user says "FASTQ files" → reject chains needing Cell Ranger output.
                user_types = self._detect_query_data_types(query)
                if user_types:
                    compatible = [c for c in top_candidates if self._chain_input_compatible(c, user_types)]
                    if len(compatible) < len(top_candidates):
                        log.info(
                            "[ChainIndex] Input-type pre-filter removed %d/%d candidates for %r "
                            "(user_types=%s)",
                            len(top_candidates) - len(compatible), len(top_candidates),
                            query[:60], sorted(user_types),
                        )
                    top_candidates = compatible
                if not top_candidates:
                    return []  # all candidates filtered out — fall through to workflow search
                # ── Multi-modality context pre-filter ─────────────────────────
                # Some chains require multiple distinct data modalities (e.g. WGS + RNA-seq).
                # If the user query doesn't signal at least one term from each modality group,
                # the chain is a false positive and should be rejected in code — not left to
                # a potentially overconfident LLM decision.
                top_candidates = [
                    c for c in top_candidates
                    if self._chain_multimodal_context_compatible(c, query)
                ]
                if not top_candidates:
                    log.info(
                        "[ChainIndex] Multi-modality pre-filter removed all candidates for %r",
                        query[:60],
                    )
                    return []
                # LLM reranking from short candidate list
                # Returns [chain] (match), [] (explicit no-match), or None (unavailable)
                # skip_llm_rerank: the ~3s LLM scope-check is the dominant chain-search
                # latency and serializes concurrent requests. Callers on a latency-
                # critical path (connector) skip it and trust the embedding ranking.
                if not skip_llm_rerank:
                    llm_result = self._llm_select_chain(query, top_candidates)
                    if llm_result is not None:
                        return llm_result  # trust LLM decision (including explicit [])
                # LLM unavailable or skipped — trust embedding ranking
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
        # Apply input-type pre-filter and multimodal context filter to Tier-2 results as well
        # (same filters as Tier-1 embedding path — important for CUDA-unavailable environments)
        user_types = self._detect_query_data_types(query)
        return [
            c for s, c in scored[:limit]
            if s >= min_score
            and self._chain_multimodal_context_compatible(c, query)
            and self._chain_input_compatible(c, user_types)
        ]

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
