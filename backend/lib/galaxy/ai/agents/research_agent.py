"""
ResearchAgent - Literature-backed research question answering

Provides evidence-based answers to research questions using:
- Literature search (PubMed, arXiv, Semantic Scholar)
- Benchmark knowledge for tool comparisons
- Scientific thinking skills for structured reasoning
- Citation generation and methods section writing

This agent addresses the SGI-Bench finding that LLMs need domain expertise
and literature grounding to provide scientifically accurate responses.
"""

import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import json

log = logging.getLogger(__name__)


@dataclass
class Citation:
    """A literature citation."""
    title: str
    authors: List[str]
    year: int
    journal: str
    doi: Optional[str] = None
    pmid: Optional[str] = None
    abstract: Optional[str] = None
    relevance_score: float = 0.0


@dataclass
class ResearchResponse:
    """Response from the ResearchAgent."""
    answer: str
    citations: List[Citation] = field(default_factory=list)
    confidence: float = 0.8
    follow_up_questions: List[str] = field(default_factory=list)
    methods_used: List[str] = field(default_factory=list)
    benchmark_evidence: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class ResearchAgent:
    """
    Agent for answering research questions with literature-backed evidence.

    Uses a multi-step process:
    1. Analyze the question to identify key concepts
    2. Search literature (PubMed, arXiv, etc.)
    3. Query benchmark knowledge for tool comparisons
    4. Synthesize findings with skill-guided prompts
    5. Generate response with citations
    """

    def __init__(
        self,
        llm_client: Optional[Any] = None,
        skill_loader: Optional[Any] = None,
        benchmark_db: Optional[Any] = None,
        literature_client: Optional[Any] = None,
        max_citations: int = 5,
        max_workers: int = 3
    ):
        """
        Initialize ResearchAgent.

        Args:
            llm_client: LLM client for Claude API calls
            skill_loader: SkillLoader for loading scientific skills
            benchmark_db: BenchmarkKnowledgeDB for tool comparisons
            literature_client: UnifiedLiteratureClient for citation retrieval
            max_citations: Maximum citations to include in response
            max_workers: Max parallel workers for literature search
        """
        self.llm_client = llm_client
        self.skill_loader = skill_loader
        self.benchmark_db = benchmark_db
        self.literature_client = literature_client
        self.max_citations = max_citations
        self.max_workers = max_workers

        # Lazy import to avoid circular dependencies
        self._init_components()

    def _init_components(self):
        """Initialize components lazily."""
        # Import LLM client if not provided
        if self.llm_client is None:
            try:
                from galaxy.ai.llm_client import LLMClient
                from galaxy.ai.config import DEFAULT_AI_CONFIG
                self.llm_client = LLMClient(DEFAULT_AI_CONFIG)
            except ImportError:
                log.warning("LLMClient not available")
            except Exception as e:
                log.warning(f"LLMClient initialization failed: {e}")

        # Import SkillLoader if not provided
        if self.skill_loader is None:
            try:
                from galaxy.ai.agents.skill_loader import SkillLoader
                self.skill_loader = SkillLoader()
            except ImportError:
                log.warning("SkillLoader not available")

        # Import BenchmarkKnowledgeDB if not provided
        if self.benchmark_db is None:
            try:
                from galaxy.ai.benchmark_knowledge import BenchmarkKnowledgeDB
                self.benchmark_db = BenchmarkKnowledgeDB()
            except ImportError:
                log.warning("BenchmarkKnowledgeDB not available")

        # Import UnifiedLiteratureClient if not provided
        if self.literature_client is None:
            try:
                from galaxy.ai.agents.literature_clients import create_literature_client
                self.literature_client = create_literature_client()
            except ImportError:
                log.warning("UnifiedLiteratureClient not available")

    async def answer_question(
        self,
        question: str,
        context: Optional[Dict[str, Any]] = None,
        include_citations: bool = True,
        include_benchmark_evidence: bool = True
    ) -> ResearchResponse:
        """
        Answer a research question with literature-backed evidence.

        Args:
            question: The research question to answer
            context: Optional context (domain, workflow results, etc.)
            include_citations: Whether to search and include citations
            include_benchmark_evidence: Whether to query benchmarks

        Returns:
            ResearchResponse with answer, citations, and evidence
        """
        try:
            # Step 1: Analyze question
            analysis = await self._analyze_question(question, context)

            # Step 2: Gather evidence in parallel
            evidence = await self._gather_evidence(
                question=question,
                analysis=analysis,
                include_citations=include_citations,
                include_benchmark_evidence=include_benchmark_evidence
            )

            # Step 3: Synthesize response
            response = await self._synthesize_response(
                question=question,
                analysis=analysis,
                evidence=evidence,
                context=context
            )

            return response

        except Exception as e:
            log.error(f"Error answering question: {e}")
            return ResearchResponse(
                answer=f"I encountered an error while researching your question: {str(e)}",
                error=str(e),
                confidence=0.0
            )

    async def _analyze_question(
        self,
        question: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Analyze the question to extract key concepts and intent."""
        # Determine intent type
        intent = self._classify_intent(question)

        # Extract key terms
        key_terms = self._extract_key_terms(question)

        # Determine domain
        domain = context.get('domain') if context else None
        if not domain:
            domain = self._infer_domain(question, key_terms)

        return {
            'intent': intent,
            'key_terms': key_terms,
            'domain': domain,
            'is_tool_comparison': self._is_tool_comparison(question),
            'is_method_question': self._is_method_question(question)
        }

    def _classify_intent(self, question: str) -> str:
        """Classify the intent of the question."""
        question_lower = question.lower()

        if any(word in question_lower for word in ['compare', 'vs', 'versus', 'better', 'best']):
            return 'result_comparison'
        elif any(word in question_lower for word in ['how', 'method', 'protocol', 'procedure']):
            return 'research_question'
        elif any(word in question_lower for word in ['conclude', 'interpret', 'mean', 'implication']):
            return 'conclusion_drawing'
        elif any(word in question_lower for word in ['hypothesis', 'predict', 'expect']):
            return 'hypothesis_generation'
        elif any(word in question_lower for word in ['literature', 'review', 'papers', 'studies']):
            return 'literature_survey'
        else:
            return 'research_question'

    def _extract_key_terms(self, question: str) -> List[str]:
        """Extract key scientific terms from the question."""
        # Common scientific terms to look for
        bio_terms = [
            'rna-seq', 'dna', 'protein', 'gene', 'genome', 'transcriptome',
            'alignment', 'variant', 'expression', 'differential', 'single-cell',
            'chip-seq', 'atac-seq', 'methylation', 'sequencing', 'assembly',
            'annotation', 'pathway', 'enrichment', 'clustering', 'normalization'
        ]

        # Tool names
        tool_names = [
            'star', 'hisat2', 'bowtie', 'bwa', 'salmon', 'kallisto',
            'deseq2', 'edger', 'limma', 'scanpy', 'seurat', 'scvi',
            'gatk', 'deepvariant', 'freebayes', 'macs2', 'homer'
        ]

        question_lower = question.lower()
        found_terms = []

        for term in bio_terms + tool_names:
            if term in question_lower:
                found_terms.append(term)

        # Also extract any capitalized terms (likely proper nouns/tool names)
        words = question.split()
        for word in words:
            if word[0].isupper() and len(word) > 2 and word.lower() not in ['the', 'what', 'how', 'why']:
                found_terms.append(word)

        return list(set(found_terms))

    def _infer_domain(self, question: str, key_terms: List[str]) -> str:
        """Infer the scientific domain from the question."""
        domain_keywords = {
            'genomics': ['dna', 'genome', 'variant', 'snp', 'indel', 'assembly', 'wgs', 'wes'],
            'transcriptomics': ['rna', 'transcriptome', 'expression', 'differential', 'rna-seq'],
            'proteomics': ['protein', 'mass spec', 'peptide', 'proteome'],
            'single-cell': ['single-cell', 'scrna', 'scatac', '10x', 'clustering'],
            'epigenomics': ['chip-seq', 'atac-seq', 'methylation', 'histone', 'chromatin'],
            'metagenomics': ['microbiome', 'metagenome', '16s', 'shotgun', 'taxonomy'],
            'pharmacology': ['drug', 'compound', 'target', 'binding', 'admet', 'docking']
        }

        question_lower = question.lower()
        terms_lower = [t.lower() for t in key_terms]

        for domain, keywords in domain_keywords.items():
            for keyword in keywords:
                if keyword in question_lower or keyword in terms_lower:
                    return domain

        return 'general'

    def _is_tool_comparison(self, question: str) -> bool:
        """Check if the question is about comparing tools."""
        comparison_words = ['compare', 'vs', 'versus', 'better', 'best', 'difference', 'prefer']
        return any(word in question.lower() for word in comparison_words)

    def _is_method_question(self, question: str) -> bool:
        """Check if the question is about methodology."""
        method_words = ['how', 'method', 'protocol', 'procedure', 'steps', 'workflow', 'pipeline']
        return any(word in question.lower() for word in method_words)

    async def _gather_evidence(
        self,
        question: str,
        analysis: Dict[str, Any],
        include_citations: bool,
        include_benchmark_evidence: bool
    ) -> Dict[str, Any]:
        """Gather evidence from multiple sources."""
        evidence = {
            'citations': [],
            'benchmark_results': None,
            'skill_guidance': ''
        }

        # Load relevant skills
        if self.skill_loader:
            intent = analysis.get('intent', 'research_question')
            evidence['skill_guidance'] = self.skill_loader.load_skills_for_intent(
                intent,
                include_references=False,
                max_tokens=4000
            )

            # Also load domain-specific skills
            domain = analysis.get('domain')
            if domain and domain != 'general':
                domain_skills = self.skill_loader.load_skills_for_domain(
                    domain,
                    include_references=False,
                    max_tokens=2000
                )
                evidence['skill_guidance'] += f"\n\n{domain_skills}"

        # Search literature using UnifiedLiteratureClient
        if include_citations and self.literature_client:
            try:
                key_terms = analysis.get('key_terms', [])
                search_query = ' '.join(key_terms) if key_terms else question

                # Use bioinformatics-focused search
                citations = await self.literature_client.search_bioinformatics(
                    query=search_query,
                    max_results=self.max_citations,
                    recent_years=5
                )

                evidence['citations'] = citations
                log.info(f"Retrieved {len(citations)} citations from literature search")
            except Exception as e:
                log.warning(f"Literature search failed: {e}")

        # Query benchmarks for tool comparisons
        if include_benchmark_evidence and self.benchmark_db:
            if analysis.get('is_tool_comparison'):
                # Try to extract tool names and compare
                benchmark_results = self._query_benchmarks(question, analysis)
                evidence['benchmark_results'] = benchmark_results

        return evidence

    def _query_benchmarks(
        self,
        question: str,
        analysis: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Query benchmark database for tool comparisons."""
        if not self.benchmark_db:
            return None

        try:
            # Use semantic search on the question
            results = self.benchmark_db.query_semantic(question, top_k=5)

            if results:
                return {
                    'query': question,
                    'results': results,
                    'best_tool': results[0].get('tool_name') if results else None,
                    'evidence': results[0].get('evidence_text') if results else None
                }
        except Exception as e:
            log.warning(f"Benchmark query failed: {e}")

        return None

    async def _synthesize_response(
        self,
        question: str,
        analysis: Dict[str, Any],
        evidence: Dict[str, Any],
        context: Optional[Dict[str, Any]] = None
    ) -> ResearchResponse:
        """Synthesize a response from gathered evidence."""
        if not self.llm_client:
            return ResearchResponse(
                answer="LLM client not available for response synthesis.",
                error="LLM client not initialized",
                confidence=0.0
            )

        # Build the synthesis prompt
        prompt = self._build_synthesis_prompt(question, analysis, evidence, context)

        try:
            # Call LLM for synthesis
            response = await self._call_llm(prompt)

            # Parse the response
            parsed = self._parse_llm_response(response)

            # Build citations from literature search and benchmark evidence
            citations = []

            # Add citations from literature search (LiteratureCitation -> Citation)
            if evidence.get('citations'):
                for lit_citation in evidence['citations'][:self.max_citations]:
                    citations.append(Citation(
                        title=lit_citation.title,
                        authors=lit_citation.authors,
                        year=lit_citation.year or 2023,
                        journal=lit_citation.journal or "Unknown",
                        doi=lit_citation.doi,
                        pmid=lit_citation.pmid,
                        abstract=lit_citation.abstract,
                        relevance_score=lit_citation.relevance_score
                    ))

            # Add citations from benchmark evidence
            if evidence.get('benchmark_results'):
                for result in evidence['benchmark_results'].get('results', [])[:self.max_citations]:
                    if result.get('doi'):
                        # Avoid duplicate DOIs
                        existing_dois = {c.doi for c in citations if c.doi}
                        if result.get('doi') not in existing_dois:
                            citations.append(Citation(
                                title=result.get('study_name', 'Benchmark Study'),
                                authors=[],
                                year=2023,  # Default
                                journal='Benchmark',
                                doi=result.get('doi')
                            ))

            return ResearchResponse(
                answer=parsed.get('answer', response),
                citations=citations,
                confidence=parsed.get('confidence', 0.8),
                follow_up_questions=parsed.get('follow_ups', []),
                methods_used=list(analysis.keys()),
                benchmark_evidence=evidence.get('benchmark_results')
            )

        except Exception as e:
            log.error(f"LLM synthesis failed: {e}")
            return ResearchResponse(
                answer=f"Error synthesizing response: {str(e)}",
                error=str(e),
                confidence=0.0
            )

    def _build_synthesis_prompt(
        self,
        question: str,
        analysis: Dict[str, Any],
        evidence: Dict[str, Any],
        context: Optional[Dict[str, Any]] = None
    ) -> str:
        """Build the prompt for LLM synthesis."""
        prompt_parts = []

        # Add skill guidance if available
        if evidence.get('skill_guidance'):
            prompt_parts.append(f"## Scientific Skill Guidance\n{evidence['skill_guidance'][:4000]}")

        # Add benchmark evidence
        if evidence.get('benchmark_results'):
            benchmark_text = self._format_benchmark_evidence(evidence['benchmark_results'])
            prompt_parts.append(f"## Benchmark Evidence\n{benchmark_text}")

        # Add context if available
        if context:
            prompt_parts.append(f"## Context\n{json.dumps(context, indent=2)}")

        # Add the question
        prompt_parts.append(f"""
## Research Question
{question}

## Analysis
- Intent: {analysis.get('intent')}
- Domain: {analysis.get('domain')}
- Key Terms: {', '.join(analysis.get('key_terms', []))}

## Instructions
Please provide a comprehensive, evidence-based answer to the research question.

1. Ground your answer in the benchmark evidence and scientific principles provided
2. Be specific about tool recommendations if applicable
3. Cite evidence sources when making claims
4. Acknowledge limitations and uncertainties
5. Suggest follow-up questions if relevant

Format your response as a clear, well-structured answer that a scientist would find useful.
""")

        return "\n\n".join(prompt_parts)

    def _format_benchmark_evidence(self, benchmark_results: Dict[str, Any]) -> str:
        """Format benchmark results for the prompt."""
        if not benchmark_results:
            return "No benchmark data available."

        lines = []
        lines.append(f"Query: {benchmark_results.get('query', 'N/A')}")

        if benchmark_results.get('best_tool'):
            lines.append(f"Best Tool: {benchmark_results['best_tool']}")

        if benchmark_results.get('evidence'):
            lines.append(f"Evidence: {benchmark_results['evidence']}")

        results = benchmark_results.get('results', [])
        if results:
            lines.append("\nRanked Results:")
            for i, result in enumerate(results[:5], 1):
                tool = result.get('tool_name', 'Unknown')
                rank = result.get('rank', 'N/A')
                metric = result.get('metric_name', '')
                value = result.get('metric_value', '')
                lines.append(f"  {i}. {tool} (Rank: {rank}, {metric}: {value})")

        return "\n".join(lines)

    async def _call_llm(self, prompt: str) -> str:
        """Call the LLM with the synthesis prompt."""
        if not self.llm_client:
            raise ValueError("LLM client not available")

        # Use the generate method from LLMClient
        response = await self.llm_client.generate(
            prompt=prompt,
            max_tokens=2000,
            temperature=0.7
        )

        return response

    def _parse_llm_response(self, response: str) -> Dict[str, Any]:
        """Parse the LLM response to extract structured data."""
        # For now, return the response as-is with default metadata
        # In future, could parse structured sections
        return {
            'answer': response,
            'confidence': 0.8,
            'follow_ups': []
        }

    # Synchronous wrapper for compatibility
    def answer_question_sync(
        self,
        question: str,
        context: Optional[Dict[str, Any]] = None,
        include_citations: bool = True,
        include_benchmark_evidence: bool = True
    ) -> ResearchResponse:
        """Synchronous wrapper for answer_question.

        Properly handles event loop creation to avoid "Event loop is closed" errors.
        Works correctly in Python 3.10+ where get_event_loop() behavior changed.
        """
        import asyncio

        async_coro = self.answer_question(
            question=question,
            context=context,
            include_citations=include_citations,
            include_benchmark_evidence=include_benchmark_evidence
        )

        # Check if we're already inside an async context
        try:
            loop = asyncio.get_running_loop()
            # We're inside an async context - use nest_asyncio or run in thread
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(asyncio.run, async_coro)
                return future.result()
        except RuntimeError:
            # No running event loop - safe to use asyncio.run()
            # asyncio.run() creates a new event loop, runs the coroutine, and closes it
            return asyncio.run(async_coro)


# Factory function
def create_research_agent(
    llm_client: Optional[Any] = None,
    skill_loader: Optional[Any] = None,
    benchmark_db: Optional[Any] = None,
    literature_client: Optional[Any] = None
) -> ResearchAgent:
    """Create a ResearchAgent instance."""
    return ResearchAgent(
        llm_client=llm_client,
        skill_loader=skill_loader,
        benchmark_db=benchmark_db,
        literature_client=literature_client
    )
