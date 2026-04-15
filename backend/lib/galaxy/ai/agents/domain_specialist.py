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
import time
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import concurrent.futures
import json

from ..domain_registry import DOMAIN_SPECIALIST_PROMPTS as _REGISTRY_PROMPTS

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

    # Domain-specific prompt templates — sourced from domain_registry.py
    # DO NOT edit here; edit backend/lib/galaxy/ai/domain_registry.py instead.
    DOMAIN_PROMPTS: Dict[str, str] = _REGISTRY_PROMPTS

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
        tools_per_domain: int = 15,
        available_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, DomainRecommendation]:
        """
        Consult domain specialists in parallel.

        Args:
            query: User's query
            domains: List of domains to consult
            parallel: Run in parallel (default True)
            tools_per_domain: Max tools to retrieve per domain
            available_datasets: Optional list of dataset dicts {id, name, type} the user
                already has — injected into the specialist prompt so the workflow entry
                point matches the available input data type.

        Returns:
            Dict mapping domain -> DomainRecommendation
        """
        if not domains:
            return {}

        log.info(f"Consulting specialists for domains: {domains}")

        if parallel and len(domains) > 1:
            return self._consult_parallel(query, domains, tools_per_domain, available_datasets)
        else:
            return self._consult_sequential(query, domains, tools_per_domain, available_datasets)

    def _consult_parallel(
        self,
        query: str,
        domains: List[str],
        tools_per_domain: int,
        available_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, DomainRecommendation]:
        """Run specialists in parallel using ThreadPoolExecutor."""
        results = {}

        with ThreadPoolExecutor(max_workers=min(len(domains), self.max_workers)) as executor:
            futures = {
                executor.submit(
                    self._consult_single,
                    query,
                    domain,
                    tools_per_domain,
                    available_datasets,
                ): domain
                for domain in domains
            }

            try:
                for future in as_completed(futures, timeout=30):  # 30s total wall-clock for all domains
                    domain = futures[future]
                    try:
                        results[domain] = future.result(timeout=25)  # 25s per individual specialist
                        log.info(f"Specialist for {domain} completed: "
                                f"{len(results[domain].recommended_tools)} tools")
                    except concurrent.futures.TimeoutError:
                        log.warning(f"Specialist for {domain} timed out after 25s — using fallback")
                        results[domain] = DomainRecommendation(domain=domain, error="timeout")
                    except Exception as e:
                        log.error(f"Specialist for {domain} failed: {e}")
                        results[domain] = DomainRecommendation(domain=domain, error=str(e))
            except concurrent.futures.TimeoutError:
                log.warning("Overall parallel specialist timeout (30s) — filling missing domains with fallback")
                for domain in domains:
                    if domain not in results:
                        results[domain] = DomainRecommendation(domain=domain, error="timeout")

        return results

    def _consult_sequential(
        self,
        query: str,
        domains: List[str],
        tools_per_domain: int,
        available_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, DomainRecommendation]:
        """Run specialists sequentially."""
        results = {}
        for domain in domains:
            try:
                results[domain] = self._consult_single(query, domain, tools_per_domain, available_datasets)
            except Exception as e:
                log.error(f"Specialist for {domain} failed: {e}")
                results[domain] = DomainRecommendation(domain=domain, error=str(e))
        return results

    def _consult_single(
        self,
        query: str,
        domain: str,
        tools_per_domain: int,
        available_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> DomainRecommendation:
        """
        Consult a single domain specialist.

        1. Search tools filtered by domain
        2. Build domain-specific prompt (with dataset type context if provided)
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
        prompt = self._build_specialist_prompt(query, domain, tools, available_datasets)

        # Step 3: Get LLM recommendations (retry up to 2 times on transient errors)
        last_err = None
        for attempt in range(3):
            try:
                response = self.llm_client.generate(
                    prompt=prompt,
                    max_tokens=1500,
                    temperature=0.0
                )
                response_text = response if isinstance(response, str) else response.get('text', '')
                # Step 4: Parse response
                return self._parse_specialist_response(domain, response_text, tools)
            except Exception as e:
                last_err = e
                err_str = str(e).lower()
                is_transient = any(x in err_str for x in ('rate_limit', 'overloaded', '529', '503', '502', 'timeout'))
                if not is_transient or attempt == 2:
                    log.error(f"LLM call failed for {domain} (attempt {attempt + 1}): {e}")
                    return self._fallback_recommendation(domain, tools)
                wait = 2 ** attempt  # 1s, 2s
                log.warning(f"Transient error for {domain} (attempt {attempt + 1}), retrying in {wait}s: {e}")
                time.sleep(wait)
        return self._fallback_recommendation(domain, tools)

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
        tools: List[Dict],
        available_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> str:
        """Build domain-specific prompt for LLM."""
        domain_context = self.DOMAIN_PROMPTS.get(domain, self.DOMAIN_PROMPTS["default"])

        tool_catalog = "\n".join([
            f"- {t.get('name', 'Unknown')} ({t.get('tool_id', '')}): "
            f"{(t.get('description', '') or '')[:150]}"
            for t in tools[:20]
        ])

        # Inject relevant data format context derived from BioMNI catalog matches.
        # These are not confirmed user files — they are reference datasets that matched
        # the query, indicating the likely data modality of the analysis.
        dataset_context = ""
        if available_datasets:
            type_summary = []
            seen_types: set = set()
            for ds in available_datasets:
                fmt = (ds.get('type') or ds.get('fileType') or ds.get('extension') or '').lower()
                if fmt and fmt not in seen_types:
                    seen_types.add(fmt)
                    type_summary.append(fmt)
            if type_summary:
                dataset_context = f"""
Relevant Data Formats:
This analysis involves data in these formats: {', '.join(type_summary)}
Design the workflow entry point to accept these input types.
"""

        return f"""{domain_context}

User Request: {query}
{dataset_context}
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
