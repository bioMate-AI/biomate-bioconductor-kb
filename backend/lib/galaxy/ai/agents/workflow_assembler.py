"""
Workflow Assembler Agent

Synthesizes domain specialist recommendations into a validated workflow.
Adds scientific validation using tool citations and domain expertise.

Responsibilities:
1. Merge recommendations from multiple domain specialists
2. Resolve conflicts between domains
3. Validate scientific correctness
4. Add citation support
5. Generate final workflow structure
"""

import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
import json

from .domain_specialist import DomainRecommendation, ToolRecommendation, WorkflowStep

log = logging.getLogger(__name__)


@dataclass
class ValidationResult:
    """Result of scientific validation."""
    is_valid: bool = True
    issues: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    suggestions: List[str] = field(default_factory=list)


@dataclass
class Citation:
    """Tool citation."""
    tool_id: str
    tool_name: str
    doi: Optional[str] = None
    pmid: Optional[str] = None
    title: Optional[str] = None


@dataclass
class AssembledWorkflow:
    """Final assembled workflow with validation."""
    workflow_steps: List[WorkflowStep]
    recommended_tools: List[ToolRecommendation]
    validation: ValidationResult
    citations: List[Citation]
    domain_sources: List[str]
    confidence: float
    assembly_notes: str = ""


class WorkflowAssembler:
    """
    Assembles and validates workflows from domain specialist recommendations.

    Uses a single LLM call for:
    - Conflict resolution between domains
    - Workflow optimization
    - Scientific validation
    """

    def __init__(self, llm_client, citation_db=None):
        """
        Initialize workflow assembler.

        Args:
            llm_client: LLM client for synthesis
            citation_db: Optional citation database
        """
        self.llm_client = llm_client
        self.citation_db = citation_db or {}

    def assemble(
        self,
        query: str,
        domain_recommendations: Dict[str, DomainRecommendation],
        user_context: Optional[Dict] = None
    ) -> AssembledWorkflow:
        """
        Assemble workflow from domain recommendations.

        Args:
            query: Original user query
            domain_recommendations: Dict of domain -> recommendations
            user_context: Optional user context for personalization

        Returns:
            AssembledWorkflow with validation and citations
        """
        if not domain_recommendations:
            return AssembledWorkflow(
                workflow_steps=[],
                recommended_tools=[],
                validation=ValidationResult(is_valid=False, issues=["No domain recommendations"]),
                citations=[],
                domain_sources=[],
                confidence=0.0
            )

        # Step 1: Merge recommendations (non-LLM)
        merged = self._merge_recommendations(domain_recommendations)

        # Step 2: Add citations (non-LLM)
        citations = self._collect_citations(merged['tools'])

        # Step 3: Validate and refine with LLM (single call)
        refined = self._validate_and_refine(query, merged, user_context)

        # Step 4: Scientific validation (non-LLM)
        validation = self._scientific_validation(refined)

        # Step 5: Compute confidence
        confidence = self._compute_confidence(
            domain_recommendations,
            refined,
            validation
        )

        return AssembledWorkflow(
            workflow_steps=refined.get('workflow_steps', []),
            recommended_tools=merged['tools'],
            validation=validation,
            citations=citations,
            domain_sources=list(domain_recommendations.keys()),
            confidence=confidence,
            assembly_notes=refined.get('notes', '')
        )

    def _merge_recommendations(
        self,
        domain_recs: Dict[str, DomainRecommendation]
    ) -> Dict[str, Any]:
        """Merge recommendations from multiple domains."""
        all_tools: Dict[str, ToolRecommendation] = {}
        all_steps: List[WorkflowStep] = []
        domain_notes: List[str] = []

        for domain, rec in domain_recs.items():
            if rec.error:
                continue

            # Merge tools (deduplicate by tool_id)
            for tool in rec.recommended_tools:
                if tool.tool_id not in all_tools:
                    all_tools[tool.tool_id] = tool
                else:
                    # Average confidence if tool appears in multiple domains
                    existing = all_tools[tool.tool_id]
                    existing.confidence = (existing.confidence + tool.confidence) / 2

            # Collect workflow steps
            for step in rec.workflow_steps:
                all_steps.append(step)

            # Collect domain notes
            if rec.domain_notes:
                domain_notes.append(f"[{domain}] {rec.domain_notes}")

        # Sort tools by confidence
        sorted_tools = sorted(
            all_tools.values(),
            key=lambda t: t.confidence,
            reverse=True
        )

        return {
            'tools': sorted_tools[:10],  # Top 10 tools
            'steps': all_steps,
            'notes': '\n'.join(domain_notes)
        }

    def _collect_citations(
        self,
        tools: List[ToolRecommendation]
    ) -> List[Citation]:
        """Collect citations for recommended tools."""
        citations = []

        # Use citation database if available
        if self.citation_db:
            for tool in tools:
                if tool.tool_id in self.citation_db:
                    cite_data = self.citation_db[tool.tool_id]
                    citations.append(Citation(
                        tool_id=tool.tool_id,
                        tool_name=tool.tool_name,
                        doi=cite_data.get('doi'),
                        pmid=cite_data.get('pmid'),
                        title=cite_data.get('title')
                    ))
        else:
            # Create placeholder citations
            for tool in tools[:5]:
                citations.append(Citation(
                    tool_id=tool.tool_id,
                    tool_name=tool.tool_name
                ))

        return citations

    def _validate_and_refine(
        self,
        query: str,
        merged: Dict[str, Any],
        user_context: Optional[Dict]
    ) -> Dict[str, Any]:
        """Use LLM to validate and refine the workflow."""
        tools_text = "\n".join([
            f"- {t.tool_name} ({t.tool_id}): {t.rationale}"
            for t in merged['tools'][:10]
        ])

        steps_text = "\n".join([
            f"{s.step_number}. {s.tool_name}: {s.description}"
            for s in merged['steps'][:8]
        ])

        user_context_text = ""
        if user_context:
            if user_context.get('expertise_level'):
                user_context_text += f"- Expertise: {user_context['expertise_level']}\n"
            if user_context.get('domain_preference'):
                user_context_text += f"- Preferred domain: {user_context['domain_preference']}\n"

        user_context_section = f"User Context:\n{user_context_text}" if user_context_text else ""
        prompt = f"""Review and optimize this bioinformatics workflow for the user's request.

User Request: {query}

{user_context_section}

Recommended Tools:
{tools_text}

Proposed Workflow Steps:
{steps_text}

Domain Notes:
{merged.get('notes', 'None')}

Tasks:
1. Verify the workflow is scientifically valid
2. Optimize step ordering (QC first, then processing, then analysis)
3. Remove redundant or conflicting steps
4. Add any missing essential steps
5. Note any concerns or recommendations

Respond in JSON:
{{
    "workflow_steps": [
        {{
            "step_number": 1,
            "tool_id": "tool_id",
            "tool_name": "Tool Name",
            "description": "What this step does"
        }}
    ],
    "issues": ["Any scientific issues found"],
    "recommendations": ["Suggestions for improvement"],
    "notes": "Assembly notes"
}}
"""

        try:
            response = self.llm_client.generate(
                prompt=prompt,
                max_tokens=1500,
                temperature=0.0
            )
            response_text = response if isinstance(response, str) else response.get('text', '')

            # Parse JSON from response
            import re
            json_match = re.search(r'\{[\s\S]*\}', response_text)
            if json_match:
                data = json.loads(json_match.group())

                # Convert to WorkflowStep objects
                workflow_steps = [
                    WorkflowStep(
                        step_number=s.get('step_number', i + 1),
                        tool_id=s.get('tool_id', ''),
                        tool_name=s.get('tool_name', ''),
                        description=s.get('description', '')
                    )
                    for i, s in enumerate(data.get('workflow_steps', []))
                ]

                return {
                    'workflow_steps': workflow_steps,
                    'issues': data.get('issues', []),
                    'recommendations': data.get('recommendations', []),
                    'notes': data.get('notes', '')
                }
        except Exception as e:
            log.warning(f"LLM refinement failed: {e}")

        # Fallback: return merged steps as-is
        return {
            'workflow_steps': merged['steps'][:6],
            'issues': [],
            'recommendations': [],
            'notes': 'Fallback assembly (LLM refinement unavailable)'
        }

    def _scientific_validation(
        self,
        refined: Dict[str, Any]
    ) -> ValidationResult:
        """Perform scientific validation checks."""
        issues = refined.get('issues', [])
        warnings = []
        suggestions = refined.get('recommendations', [])

        steps = refined.get('workflow_steps', [])

        # Check 1: Minimum steps
        if len(steps) < 2:
            warnings.append("Workflow has fewer than 2 steps - may be incomplete")

        # Check 2: QC step
        has_qc = any(
            'qc' in s.description.lower() or
            'quality' in s.description.lower() or
            'fastqc' in s.tool_id.lower()
            for s in steps
        )
        if not has_qc and len(steps) > 2:
            suggestions.append("Consider adding a quality control step at the beginning")

        # Check 3: Step ordering
        tool_ids = [s.tool_id for s in steps]
        # Basic check: QC tools should come before analysis tools
        qc_positions = [i for i, tid in enumerate(tool_ids) if 'qc' in tid.lower()]
        analysis_positions = [i for i, tid in enumerate(tool_ids) if 'analysis' in tid.lower() or 'deseq' in tid.lower()]
        if qc_positions and analysis_positions:
            if min(qc_positions) > min(analysis_positions):
                warnings.append("QC steps should typically come before analysis steps")

        return ValidationResult(
            is_valid=len(issues) == 0,
            issues=issues,
            warnings=warnings,
            suggestions=suggestions
        )

    def _compute_confidence(
        self,
        domain_recs: Dict[str, DomainRecommendation],
        refined: Dict[str, Any],
        validation: ValidationResult
    ) -> float:
        """Compute overall confidence score."""
        # Base confidence from domain specialists
        domain_confidences = [
            rec.confidence for rec in domain_recs.values()
            if not rec.error
        ]
        base_conf = sum(domain_confidences) / len(domain_confidences) if domain_confidences else 0.5

        # Penalties
        if validation.issues:
            base_conf -= 0.1 * len(validation.issues)
        if validation.warnings:
            base_conf -= 0.05 * len(validation.warnings)

        # Boost for multi-domain agreement
        if len(domain_recs) > 1:
            base_conf += 0.1

        return max(0.1, min(1.0, base_conf))
