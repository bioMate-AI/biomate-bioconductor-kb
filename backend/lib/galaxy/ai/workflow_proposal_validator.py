"""
Workflow Proposal Validator

Validates LLM-proposed workflows against:
1. Tool Index - ensures tools exist in Galaxy
2. Knowledge Base - ensures tool choices follow best practices

This implements the "LLM-Propose-Then-Validate" architecture where:
- LLM uses full domain knowledge to propose ideal workflows
- Validators check against actual tool availability and benchmarks
- Refinement loop fixes issues with evidence-based suggestions
"""

import sqlite3
import json
import logging
import re
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from pathlib import Path
from difflib import SequenceMatcher

log = logging.getLogger(__name__)

# Database paths
_TOOLS_DB = Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db"
_BENCHMARK_DB = Path(__file__).parent.parent.parent.parent / "database" / "benchmark_knowledge.db"


@dataclass
class ToolMatch:
    """A matched tool from the index."""
    tool_id: str
    name: str
    score: float
    match_type: str  # "exact", "fuzzy", "semantic"
    description: str = ""
    category: str = ""


@dataclass
class ToolValidation:
    """Result of validating a proposed tool."""
    status: str  # "FOUND", "SUBSTITUTE", "MISSING"
    proposed_tool: str
    galaxy_tool_id: Optional[str] = None
    galaxy_tool_name: Optional[str] = None
    confidence: float = 0.0
    substitutes: List[ToolMatch] = field(default_factory=list)
    message: str = ""


@dataclass
class KnowledgeValidation:
    """Result of validating tool choice against knowledge base."""
    is_recommended: bool
    tool_id: str
    decision_rules: List[Dict] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    alternatives: List[str] = field(default_factory=list)
    benchmark_evidence: List[Dict] = field(default_factory=list)
    best_practices: List[str] = field(default_factory=list)
    citations: List[Dict] = field(default_factory=list)


@dataclass
class StepValidation:
    """Validation result for a single workflow step."""
    step_number: int
    proposed_tool: str
    purpose: str
    tool_validation: ToolValidation
    knowledge_validation: Optional[KnowledgeValidation] = None


@dataclass
class WorkflowValidation:
    """Complete validation result for a proposed workflow."""
    workflow_name: str
    steps: List[StepValidation]
    all_tools_available: bool
    all_tools_recommended: bool
    needs_refinement: bool
    refinement_suggestions: List[str] = field(default_factory=list)
    confidence_score: float = 0.0


class ToolIndexValidator:
    """
    Validates proposed tools against the Galaxy tool index.

    Uses multiple matching strategies:
    1. Exact match on tool_id or name
    2. Fuzzy match using string similarity
    3. Semantic match using category and description
    """

    # Common tool name variations and aliases
    TOOL_ALIASES = {
        # Aligners
        "star": ["rna_star", "star_aligner", "star-aligner"],
        "hisat2": ["hisat", "hisat_2"],
        "bowtie2": ["bowtie", "bowtie_2"],
        "bwa": ["bwa_mem", "bwa-mem", "bwa_mem2"],
        "minimap2": ["minimap", "minimap_2"],

        # Quantification
        "salmon": ["salmon_quant"],
        "kallisto": ["kallisto_quant"],
        "featurecounts": ["subread_featurecounts", "featureCounts", "feature_counts"],
        "htseq": ["htseq_count", "htseq-count"],
        "rsem": ["rsem_calculate_expression"],

        # Differential expression
        "deseq2": ["deseq", "DESeq2"],
        "edger": ["edgeR"],
        "limma": ["limma_voom"],

        # Quality control
        "fastqc": ["FastQC", "fast_qc"],
        "multiqc": ["MultiQC", "multi_qc"],
        "fastp": ["fastp_filter"],
        "trimmomatic": ["trimmomatic_paired", "trimmomatic_single"],
        "cutadapt": ["cutadapt_trim"],

        # Variant calling
        "gatk": ["gatk4", "gatk_haplotypecaller", "gatk4_haplotypecaller"],
        "bcftools": ["bcftools_call", "bcftools_mpileup"],
        "freebayes": ["freebayes_caller"],
        "deepvariant": ["deep_variant"],

        # Single-cell
        "scanpy": ["scanpy_pp", "scanpy_tl", "scanpy_pl"],
        "seurat": ["seurat_pipeline"],
        "cellranger": ["cell_ranger", "cellranger_count"],

        # Assembly
        "spades": ["SPAdes", "spades_assembler"],
        "megahit": ["megahit_assembler"],
        "trinity": ["trinity_assembler"],

        # Other
        "samtools": ["samtools_sort", "samtools_index", "samtools_view"],
        "bedtools": ["bedtools_intersect", "bedtools_merge"],
        "picard": ["picard_markduplicates", "picard_sortsam"],
    }

    def __init__(self, db_path: str = None):
        self.db_path = str(db_path or _TOOLS_DB)
        self._tool_cache = None

    def _get_connection(self) -> sqlite3.Connection:
        """Get database connection."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _load_tool_cache(self) -> Dict[str, Dict]:
        """Load tool index into memory for fast matching."""
        if self._tool_cache is not None:
            return self._tool_cache

        self._tool_cache = {}
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("""
                SELECT tool_id, name, description, category, tags
                FROM tools
                WHERE tool_id IS NOT NULL
            """)
            for row in cursor.fetchall():
                tool_id = row['tool_id']
                self._tool_cache[tool_id] = {
                    'tool_id': tool_id,
                    'name': row['name'] or '',
                    'description': row['description'] or '',
                    'category': row['category'] or '',
                    'tags': row['tags'] or ''
                }
            conn.close()
            log.info(f"Loaded {len(self._tool_cache)} tools into cache")
        except Exception as e:
            log.error(f"Failed to load tool cache: {e}")
            self._tool_cache = {}
        return self._tool_cache

    def _normalize_name(self, name: str) -> str:
        """Normalize tool name for matching."""
        # Lowercase and remove common suffixes/prefixes
        name = name.lower().strip()
        # Remove version numbers
        name = re.sub(r'[\d\.]+$', '', name)
        # Remove common suffixes
        for suffix in ['_tool', '_wrapper', '_galaxy', '-galaxy']:
            name = name.replace(suffix, '')
        # Replace separators with underscore
        name = re.sub(r'[-\s]+', '_', name)
        return name.strip('_')

    def _string_similarity(self, s1: str, s2: str) -> float:
        """Calculate string similarity using SequenceMatcher."""
        return SequenceMatcher(None, s1.lower(), s2.lower()).ratio()

    def _exact_match(self, proposed_tool: str) -> Optional[ToolMatch]:
        """Try exact match on tool_id or name."""
        cache = self._load_tool_cache()
        proposed_lower = proposed_tool.lower()
        proposed_normalized = self._normalize_name(proposed_tool)

        for tool_id, tool_info in cache.items():
            tool_id_lower = tool_id.lower()
            name_lower = tool_info['name'].lower()
            name_normalized = self._normalize_name(tool_info['name'])

            # Exact match on tool_id
            if proposed_lower == tool_id_lower:
                return ToolMatch(
                    tool_id=tool_id,
                    name=tool_info['name'],
                    score=1.0,
                    match_type="exact",
                    description=tool_info['description'],
                    category=tool_info['category']
                )

            # Exact match on name
            if proposed_lower == name_lower or proposed_normalized == name_normalized:
                return ToolMatch(
                    tool_id=tool_id,
                    name=tool_info['name'],
                    score=1.0,
                    match_type="exact",
                    description=tool_info['description'],
                    category=tool_info['category']
                )

        return None

    def _alias_match(self, proposed_tool: str) -> Optional[ToolMatch]:
        """Try matching using known tool aliases."""
        proposed_normalized = self._normalize_name(proposed_tool)
        cache = self._load_tool_cache()

        # Check if proposed tool matches any alias
        for canonical, aliases in self.TOOL_ALIASES.items():
            all_names = [canonical] + aliases
            for alias in all_names:
                if self._normalize_name(alias) == proposed_normalized:
                    # Found an alias, now find the actual tool
                    for tool_id, tool_info in cache.items():
                        tool_normalized = self._normalize_name(tool_info['name'])
                        id_normalized = self._normalize_name(tool_id)

                        # Check if tool matches any of the canonical names
                        for name in all_names:
                            name_norm = self._normalize_name(name)
                            if name_norm in tool_normalized or name_norm in id_normalized:
                                return ToolMatch(
                                    tool_id=tool_id,
                                    name=tool_info['name'],
                                    score=0.95,
                                    match_type="alias",
                                    description=tool_info['description'],
                                    category=tool_info['category']
                                )
        return None

    def _fuzzy_match(self, proposed_tool: str, threshold: float = 0.6) -> List[ToolMatch]:
        """Find tools with similar names using fuzzy matching."""
        cache = self._load_tool_cache()
        proposed_normalized = self._normalize_name(proposed_tool)
        matches = []

        for tool_id, tool_info in cache.items():
            name_normalized = self._normalize_name(tool_info['name'])
            id_normalized = self._normalize_name(tool_id)

            # Calculate similarity scores
            name_score = self._string_similarity(proposed_normalized, name_normalized)
            id_score = self._string_similarity(proposed_normalized, id_normalized)
            best_score = max(name_score, id_score)

            # Also check if proposed is contained in tool name/id
            if proposed_normalized in name_normalized or proposed_normalized in id_normalized:
                best_score = max(best_score, 0.8)

            if best_score >= threshold:
                matches.append(ToolMatch(
                    tool_id=tool_id,
                    name=tool_info['name'],
                    score=best_score,
                    match_type="fuzzy",
                    description=tool_info['description'],
                    category=tool_info['category']
                ))

        # Sort by score descending
        matches.sort(key=lambda x: x.score, reverse=True)
        return matches[:5]  # Return top 5

    def _category_match(self, proposed_tool: str, purpose: str = "") -> List[ToolMatch]:
        """Find tools in the same category that might be alternatives."""
        cache = self._load_tool_cache()
        proposed_lower = proposed_tool.lower()
        purpose_lower = purpose.lower()
        matches = []

        # Determine likely category from proposed tool name or purpose
        category_keywords = {
            'alignment': ['align', 'aligner', 'mapping', 'mapper', 'star', 'hisat', 'bowtie', 'bwa'],
            'quantification': ['quant', 'count', 'expression', 'salmon', 'kallisto', 'featurecount'],
            'differential': ['differential', 'deseq', 'edger', 'limma', 'de analysis'],
            'quality': ['qc', 'quality', 'fastqc', 'multiqc', 'trim', 'filter'],
            'variant': ['variant', 'snp', 'mutation', 'gatk', 'bcftools', 'freebayes'],
            'assembly': ['assembly', 'assemble', 'spades', 'megahit', 'trinity'],
        }

        likely_category = None
        for cat, keywords in category_keywords.items():
            for kw in keywords:
                if kw in proposed_lower or kw in purpose_lower:
                    likely_category = cat
                    break
            if likely_category:
                break

        if likely_category:
            for tool_id, tool_info in cache.items():
                tool_text = f"{tool_info['name']} {tool_info['description']} {tool_info['category']}".lower()
                for kw in category_keywords[likely_category]:
                    if kw in tool_text:
                        matches.append(ToolMatch(
                            tool_id=tool_id,
                            name=tool_info['name'],
                            score=0.5,
                            match_type="category",
                            description=tool_info['description'],
                            category=tool_info['category']
                        ))
                        break

        # Remove duplicates and sort
        seen = set()
        unique_matches = []
        for m in matches:
            if m.tool_id not in seen:
                seen.add(m.tool_id)
                unique_matches.append(m)

        unique_matches.sort(key=lambda x: x.score, reverse=True)
        return unique_matches[:5]

    def validate_tool(self, proposed_tool: str, purpose: str = "") -> ToolValidation:
        """
        Validate a proposed tool against the Galaxy tool index.

        Args:
            proposed_tool: Tool name proposed by LLM
            purpose: Purpose/context for the tool (helps with alternatives)

        Returns:
            ToolValidation with status and match details
        """
        log.debug(f"Validating tool: {proposed_tool}")

        # 1. Try exact match
        exact = self._exact_match(proposed_tool)
        if exact:
            return ToolValidation(
                status="FOUND",
                proposed_tool=proposed_tool,
                galaxy_tool_id=exact.tool_id,
                galaxy_tool_name=exact.name,
                confidence=1.0,
                message=f"Exact match found: {exact.name}"
            )

        # 2. Try alias match
        alias = self._alias_match(proposed_tool)
        if alias:
            return ToolValidation(
                status="FOUND",
                proposed_tool=proposed_tool,
                galaxy_tool_id=alias.tool_id,
                galaxy_tool_name=alias.name,
                confidence=0.95,
                message=f"Found via alias: {alias.name}"
            )

        # 3. Try fuzzy match
        fuzzy_matches = self._fuzzy_match(proposed_tool)
        if fuzzy_matches and fuzzy_matches[0].score >= 0.8:
            best = fuzzy_matches[0]
            return ToolValidation(
                status="FOUND",
                proposed_tool=proposed_tool,
                galaxy_tool_id=best.tool_id,
                galaxy_tool_name=best.name,
                confidence=best.score,
                substitutes=fuzzy_matches[1:],
                message=f"Close match found: {best.name} (similarity: {best.score:.0%})"
            )

        # 4. Substitutes available
        if fuzzy_matches:
            return ToolValidation(
                status="SUBSTITUTE",
                proposed_tool=proposed_tool,
                confidence=fuzzy_matches[0].score,
                substitutes=fuzzy_matches,
                message=f"Tool not found. Similar tools: {', '.join(m.name for m in fuzzy_matches[:3])}"
            )

        # 5. Try category-based alternatives
        category_matches = self._category_match(proposed_tool, purpose)
        if category_matches:
            return ToolValidation(
                status="SUBSTITUTE",
                proposed_tool=proposed_tool,
                confidence=0.5,
                substitutes=category_matches,
                message=f"Tool not found. Category alternatives: {', '.join(m.name for m in category_matches[:3])}"
            )

        # 6. Not found
        return ToolValidation(
            status="MISSING",
            proposed_tool=proposed_tool,
            confidence=0.0,
            message=f"Tool '{proposed_tool}' not found in Galaxy tool index"
        )


class KnowledgeValidator:
    """
    Validates tool choices against benchmark knowledge and best practices.

    Checks:
    1. Benchmark decision rules (e.g., "for short reads use Bowtie2")
    2. Performance rankings from benchmark studies
    3. Best practice recommendations
    """

    def __init__(self, benchmark_db_path: str = None, tool_knowledge_provider=None):
        self.benchmark_db_path = str(benchmark_db_path or _BENCHMARK_DB)
        self.tool_knowledge = tool_knowledge_provider

    def _get_connection(self) -> Optional[sqlite3.Connection]:
        """Get benchmark database connection."""
        try:
            if not Path(self.benchmark_db_path).exists():
                log.warning(f"Benchmark database not found: {self.benchmark_db_path}")
                return None
            conn = sqlite3.connect(self.benchmark_db_path)
            conn.row_factory = sqlite3.Row
            return conn
        except Exception as e:
            log.warning(f"Failed to connect to benchmark DB: {e}")
            return None

    def _get_decision_rules(self, tool_name: str, task_context: str) -> List[Dict]:
        """Get applicable decision rules for a tool."""
        conn = self._get_connection()
        if not conn:
            return []

        rules = []
        try:
            cursor = conn.cursor()

            # Search for rules mentioning this tool
            tool_pattern = f"%{tool_name.lower()}%"
            cursor.execute("""
                SELECT rule_type, condition, recommendation, recommended_tools, reason, evidence
                FROM decision_rules
                WHERE LOWER(recommended_tools) LIKE ? OR LOWER(recommendation) LIKE ?
            """, (tool_pattern, tool_pattern))

            for row in cursor.fetchall():
                rules.append({
                    'rule_type': row['rule_type'],
                    'condition': row['condition'],
                    'recommendation': row['recommendation'],
                    'recommended_tools': json.loads(row['recommended_tools']) if row['recommended_tools'] else [],
                    'reason': row['reason'],
                    'evidence': row['evidence']
                })

            conn.close()
        except Exception as e:
            log.debug(f"Error getting decision rules: {e}")

        return rules

    def _get_benchmark_results(self, tool_name: str) -> List[Dict]:
        """Get benchmark results for a tool."""
        conn = self._get_connection()
        if not conn:
            return []

        results = []
        try:
            cursor = conn.cursor()

            tool_pattern = f"%{tool_name.lower()}%"
            cursor.execute("""
                SELECT br.task_id, br.metric, br.score, br.rank, br.condition, br.notes,
                       bt.task_name, bt.task_type, bt.biological_question,
                       bs.title as benchmark_title, bs.doi
                FROM benchmark_results br
                JOIN benchmark_tasks bt ON br.benchmark_id = bt.benchmark_id AND br.task_id = bt.task_id
                JOIN benchmark_studies bs ON br.benchmark_id = bs.benchmark_id
                WHERE LOWER(br.tool_name) LIKE ?
                ORDER BY br.rank ASC
                LIMIT 10
            """, (tool_pattern,))

            for row in cursor.fetchall():
                results.append({
                    'task': row['task_name'],
                    'task_type': row['task_type'],
                    'metric': row['metric'],
                    'score': row['score'],
                    'rank': row['rank'],
                    'benchmark': row['benchmark_title'],
                    'doi': row['doi']
                })

            conn.close()
        except Exception as e:
            log.debug(f"Error getting benchmark results: {e}")

        return results

    def _get_alternatives_from_benchmarks(self, tool_name: str, task_context: str) -> List[str]:
        """Get better-performing alternatives from benchmarks."""
        conn = self._get_connection()
        if not conn:
            return []

        alternatives = []
        try:
            cursor = conn.cursor()

            # Find tasks where this tool was evaluated
            tool_pattern = f"%{tool_name.lower()}%"
            cursor.execute("""
                SELECT DISTINCT br2.tool_name, br2.rank, br2.score
                FROM benchmark_results br1
                JOIN benchmark_results br2 ON br1.benchmark_id = br2.benchmark_id
                    AND br1.task_id = br2.task_id
                WHERE LOWER(br1.tool_name) LIKE ?
                    AND br2.rank < br1.rank
                ORDER BY br2.rank ASC
                LIMIT 5
            """, (tool_pattern,))

            for row in cursor.fetchall():
                alternatives.append(row['tool_name'])

            conn.close()
        except Exception as e:
            log.debug(f"Error getting alternatives: {e}")

        return alternatives

    def validate_tool_choice(
        self,
        tool_id: str,
        tool_name: str,
        task_context: str = "",
        data_characteristics: Dict = None
    ) -> KnowledgeValidation:
        """
        Validate a tool choice against knowledge base.

        Args:
            tool_id: Galaxy tool ID
            tool_name: Tool name for matching
            task_context: What the tool will be used for
            data_characteristics: Data properties (read length, organism, etc.)

        Returns:
            KnowledgeValidation with recommendations and evidence
        """
        data_characteristics = data_characteristics or {}

        # Get decision rules
        rules = self._get_decision_rules(tool_name, task_context)

        # Get benchmark results
        benchmark_evidence = self._get_benchmark_results(tool_name)

        # Check for warnings based on rules and data characteristics
        warnings = []
        for rule in rules:
            # Check if rule condition applies to data characteristics
            condition = rule.get('condition', '').lower()

            # Example conditions
            if 'short read' in condition and data_characteristics.get('read_length', 100) < 75:
                if tool_name.lower() not in [t.lower() for t in rule.get('recommended_tools', [])]:
                    warnings.append(f"For short reads (<75bp): {rule['recommendation']}")

            if 'long read' in condition and data_characteristics.get('read_length', 100) > 1000:
                if tool_name.lower() not in [t.lower() for t in rule.get('recommended_tools', [])]:
                    warnings.append(f"For long reads: {rule['recommendation']}")

        # Get alternatives from benchmarks
        alternatives = self._get_alternatives_from_benchmarks(tool_name, task_context)

        # Get best practices from tool knowledge provider
        best_practices = []
        citations = []
        if self.tool_knowledge:
            try:
                knowledge = self.tool_knowledge.get_tool_knowledge(tool_id)
                if knowledge:
                    best_practices = knowledge.best_practices or []
                    if knowledge.citation:
                        citations = [knowledge.citation.to_dict()]
            except Exception as e:
                log.debug(f"Error getting tool knowledge: {e}")

        return KnowledgeValidation(
            is_recommended=len(warnings) == 0,
            tool_id=tool_id,
            decision_rules=rules,
            warnings=warnings,
            alternatives=alternatives,
            benchmark_evidence=benchmark_evidence,
            best_practices=best_practices,
            citations=citations
        )


class WorkflowProposalValidator:
    """
    Validates entire proposed workflows.

    Orchestrates tool index and knowledge validation for each step.
    Generates refinement suggestions when issues are found.
    """

    def __init__(self, tool_validator: ToolIndexValidator = None, knowledge_validator: KnowledgeValidator = None):
        self.tool_validator = tool_validator or ToolIndexValidator()
        self.knowledge_validator = knowledge_validator or KnowledgeValidator()

    def validate_workflow(
        self,
        proposed_workflow: Dict[str, Any],
        user_context: Dict[str, Any] = None
    ) -> WorkflowValidation:
        """
        Validate an entire proposed workflow.

        Args:
            proposed_workflow: LLM-proposed workflow with structure:
                {
                    "workflow_name": "...",
                    "steps": [
                        {"step": 1, "tool_name": "STAR", "purpose": "..."},
                        ...
                    ]
                }
            user_context: Data characteristics and constraints

        Returns:
            WorkflowValidation with results for each step
        """
        user_context = user_context or {}
        workflow_name = proposed_workflow.get('workflow_name', 'Unnamed Workflow')
        steps = proposed_workflow.get('steps', [])

        step_validations = []
        all_tools_available = True
        all_tools_recommended = True
        refinement_suggestions = []
        total_confidence = 0.0

        for step in steps:
            step_num = step.get('step', len(step_validations) + 1)
            proposed_tool = step.get('tool_name', step.get('proposed_tool', ''))
            purpose = step.get('purpose', '')

            # Validate tool exists
            tool_validation = self.tool_validator.validate_tool(proposed_tool, purpose)

            if tool_validation.status == "MISSING":
                all_tools_available = False
                refinement_suggestions.append(
                    f"Step {step_num}: Tool '{proposed_tool}' not found. No alternatives available."
                )
            elif tool_validation.status == "SUBSTITUTE":
                all_tools_available = False
                subs = [s.name for s in tool_validation.substitutes[:3]]
                refinement_suggestions.append(
                    f"Step {step_num}: Tool '{proposed_tool}' not found. Consider: {', '.join(subs)}"
                )

            # Validate against knowledge (if tool found)
            knowledge_validation = None
            if tool_validation.galaxy_tool_id:
                knowledge_validation = self.knowledge_validator.validate_tool_choice(
                    tool_id=tool_validation.galaxy_tool_id,
                    tool_name=tool_validation.galaxy_tool_name or proposed_tool,
                    task_context=purpose,
                    data_characteristics=user_context.get('data_characteristics', {})
                )

                if not knowledge_validation.is_recommended:
                    all_tools_recommended = False
                    for warning in knowledge_validation.warnings:
                        refinement_suggestions.append(f"Step {step_num}: {warning}")

            step_validations.append(StepValidation(
                step_number=step_num,
                proposed_tool=proposed_tool,
                purpose=purpose,
                tool_validation=tool_validation,
                knowledge_validation=knowledge_validation
            ))

            total_confidence += tool_validation.confidence

        # Calculate overall confidence
        avg_confidence = total_confidence / len(steps) if steps else 0.0

        needs_refinement = not all_tools_available or not all_tools_recommended

        return WorkflowValidation(
            workflow_name=workflow_name,
            steps=step_validations,
            all_tools_available=all_tools_available,
            all_tools_recommended=all_tools_recommended,
            needs_refinement=needs_refinement,
            refinement_suggestions=refinement_suggestions,
            confidence_score=avg_confidence
        )

    def generate_refinement_prompt(self, validation: WorkflowValidation, original_workflow: Dict) -> str:
        """
        Generate a prompt for LLM to refine the workflow based on validation.

        Args:
            validation: WorkflowValidation result
            original_workflow: Original proposed workflow

        Returns:
            Prompt string for LLM refinement
        """
        issues = []

        for step in validation.steps:
            tv = step.tool_validation
            kv = step.knowledge_validation

            if tv.status == "MISSING":
                issues.append(f"- Step {step.step_number} ({step.proposed_tool}): NOT AVAILABLE. No alternatives found.")
            elif tv.status == "SUBSTITUTE":
                subs = [s.name for s in tv.substitutes[:3]]
                issues.append(f"- Step {step.step_number} ({step.proposed_tool}): NOT AVAILABLE. Alternatives: {', '.join(subs)}")
            elif tv.status == "FOUND" and kv and kv.warnings:
                for warning in kv.warnings:
                    issues.append(f"- Step {step.step_number} ({step.proposed_tool}): {warning}")

        prompt = f"""Your proposed workflow needs refinement based on system validation.

ORIGINAL PROPOSAL:
{json.dumps(original_workflow, indent=2)}

VALIDATION ISSUES:
{chr(10).join(issues)}

Please revise the workflow:
1. Replace unavailable tools with suggested alternatives
2. Consider the benchmark-based recommendations
3. Use the exact tool names that were found in our system

Return the revised workflow as JSON with the same structure."""

        return prompt


# Factory function
def create_workflow_validator() -> WorkflowProposalValidator:
    """Create a configured WorkflowProposalValidator."""
    tool_validator = ToolIndexValidator()

    # Try to load tool knowledge provider
    tool_knowledge = None
    try:
        from .tool_knowledge_provider import ToolKnowledgeProvider
        tool_knowledge = ToolKnowledgeProvider()
    except Exception as e:
        log.debug(f"Could not load ToolKnowledgeProvider: {e}")

    knowledge_validator = KnowledgeValidator(tool_knowledge_provider=tool_knowledge)

    return WorkflowProposalValidator(tool_validator, knowledge_validator)
