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
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
from difflib import SequenceMatcher

log = logging.getLogger(__name__)

# Database path
DB_PATH = Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"

# Source priority (higher = preferred)
SOURCE_PRIORITY = {
    "nfcore": 100,          # nf-core full pipelines (community standard, CI-tested)
    "nfcore_converted": 95, # nf-core converted to Galaxy format
    "biomni_nextflow": 85,  # Biomni Nextflow subworkflows (tested, Docker-native)
    "bioconductor": 75,     # Bioconductor R-package nf-core module wrappers
    "galaxy_local": 60,     # Galaxy community .ga workflows
    "unknown": 50,          # Unknown-source Galaxy workflows
    "biomni": 10,           # Legacy Biomni Galaxy format (superseded by Nextflow)
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
            'electron': 2.0, 'microscopy': 2.0,
            'resolution': 2.0, 'map': 1.5, 'density': 1.5,
            'sharpening': 2.5, 'fsc': 2.5,

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

    def search(self,
               query: str,
               domain: Optional[str] = None,
               source: Optional[str] = None,
               format: Optional[str] = None,
               limit: int = 10,
               include_workflow_json: bool = False) -> List[WorkflowMatch]:
        """
        Search for workflows matching the query.

        Args:
            query: Natural language search query
            domain: Filter by domain (genomics, proteomics, etc.)
            source: Filter by source (nfcore, biomni, etc.)
            format: Filter by format (galaxy_ga, nextflow)
            limit: Maximum results to return
            include_workflow_json: Include full workflow JSON in results

        Returns:
            List of WorkflowMatch objects sorted by relevance
        """
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            # Build FTS query
            fts_query = self._build_fts_query(query)

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
                match = self._create_match(row, query, include_workflow_json)
                results.append(match)

            # Sort by custom score (includes source priority)
            results.sort(key=lambda x: x.score, reverse=True)

            return results[:limit]

        except sqlite3.OperationalError as e:
            log.warning(f"FTS search failed: {e}, falling back to LIKE search")
            return self._fallback_search(query, domain, source, format, limit, include_workflow_json)

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
            preferred.update({'pharmacology', 'drug_discovery', 'biochemistry', 'structural_biology'})
            penalized.update({'microbiology', 'metagenomics', 'transcriptomics'})

        return preferred, penalized

    def _build_fts_query(self, query: str) -> str:
        """Build FTS5 query from natural language with safe tokenization and abbreviation expansion."""
        # Robust tokenization: strip punctuation that can break FTS syntax.
        words = re.findall(r"[a-z0-9]+", query.lower())

        # Remove common words
        stopwords = {'i', 'want', 'to', 'the', 'a', 'an', 'for', 'with', 'and', 'or', 'from', 'in', 'on', 'my', 'run'}
        words = [w for w in words if w not in stopwords and len(w) > 1]

        # Expand abbreviations
        expanded_words = []
        for word in words:
            if word in self.ABBREVIATION_MAP:
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

    def _create_match(self, row: tuple, query: str, include_json: bool) -> WorkflowMatch:
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

        # Calculate custom score
        score = self._calculate_score(query, name, description or "", tools, tags, source, domain or "general", fts_score)
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
                         fts_score: float) -> float:
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

        # 5. Source priority (~5% weight)
        source_bonus = SOURCE_PRIORITY.get(source, 0) / 50.0  # Normalize to ~2.0 max
        score += source_bonus

        # 6. Domain preference bias (critical for avoiding cross-domain QC mismatches)
        preferred_domains, penalized_domains = self._infer_domain_preferences(query)
        domain_value = (workflow_domain or "general").lower()
        if domain_value in preferred_domains:
            score += 4.0
        if domain_value in penalized_domains:
            score -= 4.0

        return round(score, 2)

    def _classify_match(self, score: float) -> str:
        """Classify match confidence.

        Thresholds calibrated to require meaningful keyword overlap:
        - high_confidence: Strong keyword matches + name overlap (score >= 12)
        - medium_confidence: Some keyword matches (score >= 6)
        - low_confidence: Weak matches that need adaptation
        """
        if score >= 12.0:
            return "high_confidence"
        elif score >= 6.0:
            return "medium_confidence"
        else:
            return "low_confidence"

    def _fallback_search(self,
                         query: str,
                         domain: Optional[str],
                         source: Optional[str],
                         format: Optional[str],
                         limit: int,
                         include_json: bool) -> List[WorkflowMatch]:
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
                match = self._create_match(row, query, include_json)
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

            return {
                "total": total,
                "by_source": by_source,
                "by_domain": by_domain,
                "by_format": by_format
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
