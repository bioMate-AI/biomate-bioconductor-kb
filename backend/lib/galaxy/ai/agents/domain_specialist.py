"""
Domain Specialist Agent Pool

Provides domain-specific tool recommendations by running specialized prompts
in parallel using ThreadPoolExecutor.

Leverages:
- UnifiedToolSearch for category-filtered tool retrieval
- Domain-specific prompts for contextual recommendations
- Parallel execution for speed
"""

import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import json

log = logging.getLogger(__name__)


@dataclass
class ToolRecommendation:
    """A tool recommendation from a domain specialist."""
    tool_id: str
    tool_name: str
    category: str
    rationale: str
    parameters: Dict[str, Any] = field(default_factory=dict)
    confidence: float = 0.8


@dataclass
class WorkflowStep:
    """A suggested workflow step."""
    step_number: int
    tool_id: str
    tool_name: str
    description: str
    inputs: List[str] = field(default_factory=list)
    outputs: List[str] = field(default_factory=list)


@dataclass
class DomainRecommendation:
    """Result from a domain specialist."""
    domain: str
    recommended_tools: List[ToolRecommendation] = field(default_factory=list)
    workflow_steps: List[WorkflowStep] = field(default_factory=list)
    domain_notes: str = ""
    confidence: float = 0.8
    error: Optional[str] = None


class DomainSpecialistPool:
    """
    Pool of domain specialists that run in parallel.

    Each specialist:
    1. Searches tools filtered by domain category
    2. Uses domain-specific LLM prompt for recommendations
    3. Returns structured recommendations
    """

    # Domain-specific prompt templates
    DOMAIN_PROMPTS: Dict[str, str] = {
        "genomics": """You are a genomics expert. Given the user's request and available tools,
recommend the best tools for DNA/genome analysis including alignment, variant calling, and annotation.
Consider: sequencing type (WGS/WES/targeted), organism, and data quality requirements.""",

        "transcriptomics": """You are a transcriptomics expert. Given the user's request and available tools,
recommend the best tools for RNA-seq analysis including alignment, quantification, and differential expression.
Consider: library type, strandedness, and statistical analysis needs.""",

        "proteomics": """You are a proteomics expert. Given the user's request and available tools,
recommend the best tools for mass spectrometry data analysis including peptide identification and quantification.
Consider: acquisition type (DIA/DDA), quantification method, and PTM analysis needs.""",

        "metabolomics": """You are a metabolomics expert. Given the user's request and available tools,
recommend the best tools for metabolite profiling including peak detection, annotation, and pathway analysis.
Consider: platform (LC-MS/GC-MS), data format, and identification database needs.""",

        "single-cell": """You are a single-cell genomics expert. Given the user's request and available tools,
recommend the best tools for scRNA-seq analysis including QC, normalization, clustering, and cell type annotation.
Consider: technology (10X/Smart-seq), integration needs, and trajectory analysis.""",

        "metagenomics": """You are a metagenomics expert. Given the user's request and available tools,
recommend the best tools for microbiome analysis including taxonomic profiling and functional annotation.
Consider: sequencing type (16S/shotgun), database choice, and diversity analysis needs.""",

        "structural_biology": """You are a structural biology expert. Given the user's request and available tools,
recommend the best tools for protein structure analysis including prediction, docking, and visualization.
Consider: model availability, binding site analysis, and molecular dynamics needs.""",

        "pharmacology": """You are a pharmacology expert. Given the user's request and available tools,
recommend the best tools for drug analysis including ADMET prediction, target identification, and safety assessment.
Consider: compound type, therapeutic area, and regulatory requirements.""",

        "default": """You are a bioinformatics expert. Given the user's request and available tools,
recommend the most appropriate tools for the analysis. Prioritize well-validated tools with good documentation.""",
    }

    def __init__(self, tool_search, llm_client, max_workers: int = 3):
        """
        Initialize specialist pool.

        Args:
            tool_search: UnifiedToolSearch instance for tool retrieval
            llm_client: LLM client with generate() method
            max_workers: Maximum parallel specialists (default 3)
        """
        self.tool_search = tool_search
        self.llm_client = llm_client
        self.max_workers = max_workers

    def consult_specialists(
        self,
        query: str,
        domains: List[str],
        parallel: bool = True,
        tools_per_domain: int = 15
    ) -> Dict[str, DomainRecommendation]:
        """
        Consult domain specialists in parallel.

        Args:
            query: User's query
            domains: List of domains to consult
            parallel: Run in parallel (default True)
            tools_per_domain: Max tools to retrieve per domain

        Returns:
            Dict mapping domain -> DomainRecommendation
        """
        if not domains:
            return {}

        log.info(f"Consulting specialists for domains: {domains}")

        if parallel and len(domains) > 1:
            return self._consult_parallel(query, domains, tools_per_domain)
        else:
            return self._consult_sequential(query, domains, tools_per_domain)

    def _consult_parallel(
        self,
        query: str,
        domains: List[str],
        tools_per_domain: int
    ) -> Dict[str, DomainRecommendation]:
        """Run specialists in parallel using ThreadPoolExecutor."""
        results = {}

        with ThreadPoolExecutor(max_workers=min(len(domains), self.max_workers)) as executor:
            futures = {
                executor.submit(
                    self._consult_single,
                    query,
                    domain,
                    tools_per_domain
                ): domain
                for domain in domains
            }

            for future in as_completed(futures):
                domain = futures[future]
                try:
                    results[domain] = future.result()
                    log.info(f"Specialist for {domain} completed: "
                            f"{len(results[domain].recommended_tools)} tools")
                except Exception as e:
                    log.error(f"Specialist for {domain} failed: {e}")
                    results[domain] = DomainRecommendation(
                        domain=domain,
                        error=str(e)
                    )

        return results

    def _consult_sequential(
        self,
        query: str,
        domains: List[str],
        tools_per_domain: int
    ) -> Dict[str, DomainRecommendation]:
        """Run specialists sequentially."""
        results = {}
        for domain in domains:
            try:
                results[domain] = self._consult_single(query, domain, tools_per_domain)
            except Exception as e:
                log.error(f"Specialist for {domain} failed: {e}")
                results[domain] = DomainRecommendation(domain=domain, error=str(e))
        return results

    def _consult_single(
        self,
        query: str,
        domain: str,
        tools_per_domain: int
    ) -> DomainRecommendation:
        """
        Consult a single domain specialist.

        1. Search tools filtered by domain
        2. Build domain-specific prompt
        3. Get LLM recommendations
        4. Parse into structured format
        """
        # Step 1: Get domain-relevant tools
        tools = self._get_domain_tools(query, domain, tools_per_domain)

        if not tools:
            log.warning(f"No tools found for domain: {domain}")
            return DomainRecommendation(
                domain=domain,
                domain_notes=f"No specialized tools found for {domain}"
            )

        # Step 2: Build domain-specific prompt
        prompt = self._build_specialist_prompt(query, domain, tools)

        # Step 3: Get LLM recommendations
        try:
            response = self.llm_client.generate(
                prompt=prompt,
                max_tokens=1500,
                temperature=0.3
            )
            response_text = response if isinstance(response, str) else response.get('text', '')
        except Exception as e:
            log.error(f"LLM call failed for {domain}: {e}")
            # Fallback: return top tools without LLM ranking
            return self._fallback_recommendation(domain, tools)

        # Step 4: Parse response
        return self._parse_specialist_response(domain, response_text, tools)

    def _get_domain_tools(
        self,
        query: str,
        domain: str,
        limit: int
    ) -> List[Dict[str, Any]]:
        """Get tools relevant to domain using category filtering."""
        from .domain_router import DomainRouter

        # Get categories for this domain
        router = DomainRouter()
        categories = router.get_category_filter(domain)

        # Search with category filter if available
        all_tools = []
        if categories:
            for category in categories[:2]:  # Limit to top 2 categories
                try:
                    # Use the search with category
                    tools = self.tool_search._fts5_search(
                        query,
                        category=category,
                        limit=limit // 2
                    )
                    all_tools.extend(tools)
                except Exception:
                    pass

        # Also search without category filter
        general_tools = self.tool_search.search(query, limit=limit)
        all_tools.extend(general_tools)

        # Deduplicate by tool_id
        seen = set()
        unique_tools = []
        for tool in all_tools:
            tool_id = tool.get('tool_id')
            if tool_id and tool_id not in seen:
                seen.add(tool_id)
                unique_tools.append(tool)

        return unique_tools[:limit]

    def _build_specialist_prompt(
        self,
        query: str,
        domain: str,
        tools: List[Dict]
    ) -> str:
        """Build domain-specific prompt for LLM."""
        domain_context = self.DOMAIN_PROMPTS.get(domain, self.DOMAIN_PROMPTS["default"])

        tool_catalog = "\n".join([
            f"- {t.get('name', 'Unknown')} ({t.get('tool_id', '')}): "
            f"{(t.get('description', '') or '')[:150]}"
            for t in tools[:20]  # Limit tools in prompt
        ])

        return f"""{domain_context}

User Request: {query}

Available Tools:
{tool_catalog}

Respond in JSON format:
{{
    "recommended_tools": [
        {{
            "tool_id": "tool_id_here",
            "tool_name": "Tool Name",
            "rationale": "Why this tool is recommended",
            "confidence": 0.9
        }}
    ],
    "workflow_steps": [
        {{
            "step_number": 1,
            "tool_id": "tool_id",
            "tool_name": "Tool Name",
            "description": "What this step does",
            "inputs": ["input1"],
            "outputs": ["output1"]
        }}
    ],
    "domain_notes": "Any domain-specific considerations"
}}

Rules:
1. Only recommend tools from the Available Tools list
2. Order workflow_steps logically (QC first, then processing, then analysis)
3. Include 3-7 recommended tools, 3-6 workflow steps
4. Be specific about tool selection rationale
"""

    def _parse_specialist_response(
        self,
        domain: str,
        response_text: str,
        available_tools: List[Dict]
    ) -> DomainRecommendation:
        """Parse LLM response into structured recommendation."""
        # Extract JSON from response
        try:
            # Find JSON in response
            import re
            json_match = re.search(r'\{[\s\S]*\}', response_text)
            if json_match:
                data = json.loads(json_match.group())
            else:
                raise ValueError("No JSON found in response")
        except (json.JSONDecodeError, ValueError) as e:
            log.warning(f"Failed to parse specialist response: {e}")
            return self._fallback_recommendation(domain, available_tools)

        # Build tool lookup
        tool_lookup = {t['tool_id']: t for t in available_tools}

        # Parse recommended tools
        rec_tools = []
        for item in data.get('recommended_tools', [])[:7]:
            tool_id = item.get('tool_id', '')
            if tool_id in tool_lookup:
                rec_tools.append(ToolRecommendation(
                    tool_id=tool_id,
                    tool_name=item.get('tool_name', tool_lookup[tool_id].get('name', '')),
                    category=tool_lookup[tool_id].get('category', ''),
                    rationale=item.get('rationale', ''),
                    confidence=item.get('confidence', 0.8)
                ))

        # Parse workflow steps
        wf_steps = []
        for item in data.get('workflow_steps', [])[:6]:
            tool_id = item.get('tool_id', '')
            if tool_id in tool_lookup:
                wf_steps.append(WorkflowStep(
                    step_number=item.get('step_number', len(wf_steps) + 1),
                    tool_id=tool_id,
                    tool_name=item.get('tool_name', ''),
                    description=item.get('description', ''),
                    inputs=item.get('inputs', []),
                    outputs=item.get('outputs', [])
                ))

        return DomainRecommendation(
            domain=domain,
            recommended_tools=rec_tools,
            workflow_steps=wf_steps,
            domain_notes=data.get('domain_notes', ''),
            confidence=0.8 if rec_tools else 0.5
        )

    def _fallback_recommendation(
        self,
        domain: str,
        tools: List[Dict]
    ) -> DomainRecommendation:
        """Create fallback recommendation when LLM fails."""
        # Just return top tools as recommendations
        rec_tools = [
            ToolRecommendation(
                tool_id=t.get('tool_id', ''),
                tool_name=t.get('name', ''),
                category=t.get('category', ''),
                rationale=f"Relevant tool for {domain}",
                confidence=0.6
            )
            for t in tools[:5]
        ]

        return DomainRecommendation(
            domain=domain,
            recommended_tools=rec_tools,
            domain_notes=f"Fallback recommendations for {domain}",
            confidence=0.5
        )
