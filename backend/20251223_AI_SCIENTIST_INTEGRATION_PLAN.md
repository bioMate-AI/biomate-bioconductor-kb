# BioMate AI Scientist Integration Plan (REVISED v3)

**Date**: 2025-12-23 (Updated: 2025-12-30)
**Author**: Claude Code
**Status**: PENDING REVIEW
**Branch**: `new_framework_platform`

---

## Executive Summary

This plan proposes integrating **claude-scientific-skills** (K-Dense AI / Einstein) into BioMate to provide AI scientist capabilities:

1. **Answer user questions** with literature-backed evidence (hypothesis-generation skill)
2. **Draw conclusions** from workflow outputs with related work comparison (peer-review skill)
3. **Provide citations** for evidence-based recommendations (pubmed-database skill)
4. **Hypothesis generation** for research exploration (hypothesis-generation skill)

**Key Decision**: Integrate **claude-scientific-skills** - a **prompt-based skill system** that provides:
- 24 scientific database skills (PubMed, ChEMBL, UniProt, GWAS, etc.)
- Scientific thinking skills (hypothesis-generation, peer-review, exploratory-data-analysis)
- 41 scientific package skills (BioPython, RDKit, Scanpy, etc.)
- Reference materials with workflows, templates, and best practices

**NOT building from scratch** - load skill prompts dynamically to guide Claude's responses.

### What are Claude Skills?
Claude skills are **structured prompt documents** (SKILL.md files) that guide Claude on how to approach specific tasks. Each skill includes:
- Workflow steps
- Reference materials
- Templates and examples
- Best practices

The skills at `/home/yzhang/biomate/research_repos/claude-scientific-skills-biomate/` provide ready-to-use scientific workflows.

---

## Part 1: What to Integrate

### NOT Integrating: ToolUniverse Tools
- BioMate already has comprehensive tool coverage (9,103 tools)
- Tools like AlphaFold, UniProt, ChEMBL, OpenTarget, PubMed already exist in biomni
- Adding ToolUniverse tools would create duplication

### INTEGRATING: Claude Scientific Skills (K-Dense)

| Skill | Path | Purpose |
|-------|------|---------|
| **hypothesis-generation** | `scientific-thinking/hypothesis-generation/` | Generate evidence-based hypotheses, answer research questions |
| **peer-review** | `scientific-thinking/peer-review/` | Compare results with literature, evaluate methodology |
| **exploratory-data-analysis** | `scientific-thinking/exploratory-data-analysis/` | Draw conclusions from workflow outputs |
| **pubmed-database** | `scientific-databases/pubmed-database/` | Literature search with advanced query construction |
| **scientific-writing** | `scientific-thinking/scientific-writing/` | Generate methods sections, summaries |
| **scientific-critical-thinking** | `scientific-thinking/scientific-critical-thinking/` | Evaluate claims, identify biases |

### Existing BioMate Tools to Leverage

These biomni tools already exist and will be used by the skills:

| Tool | Purpose |
|------|---------|
| `query_pubmed` | PubMed literature search |
| `query_arxiv` | arXiv preprint search |
| `query_scholar` | Google Scholar search |
| `advanced_web_search_claude` | Web search with Claude |
| `extract_pdf_content` | PDF extraction |
| `extract_url_content` | URL content extraction |

---

## Part 2: Use Cases

### 2.1 Answering User Questions

```
User: "What's the best alignment algorithm for long-read RNA-seq?"

Research Agent Response:
"For long-read RNA-seq alignment, minimap2 is widely recommended [1] due to
its splice-aware algorithm optimized for noisy long reads [2]. STAR with
--outFilterMultimapNmax can also work but was designed for short reads [3].
Recent benchmarks show minimap2 achieves 95% accuracy on ONT reads [4].

Sources:
[1] Li H. (2018) Minimap2: pairwise alignment for nucleotide sequences
[2] Kovaka S. et al. (2019) Transcriptome assembly from long-read RNA-seq
[3] Dobin A. et al. (2013) STAR: ultrafast universal RNA-seq aligner
[4] Chen Y. et al. (2023) Long-read RNA-seq alignment benchmarking"
```

### 2.2 Comparing Results with Related Work

```
User: [After running differential expression workflow]
"How do my results compare with other BRCA1 studies?"

Research Agent Response:
"Your analysis identified 342 differentially expressed genes (p<0.05, |logFC|>1).

Comparison with related work:
- Richardson et al. (2018) found 287 DEGs in BRCA1-mutant breast cancer [1]
- Your top hits (TP53, CDKN1A, GADD45A) overlap 78% with their findings [1]
- Novel finding: Your MDM4 upregulation is consistent with recent TCGA analysis [2]
- The pathway enrichment (DNA repair, p53 signaling) matches expected biology [3]

Your results appear consistent with established literature.

Sources:
[1] Richardson et al. (2018) Transcriptomic analysis of BRCA1 tumors
[2] TCGA Network (2023) Pan-cancer BRCA1/2 analysis
[3] Yoshida K. et al. (2015) BRCA1 function in DNA damage response"
```

### 2.3 Drawing Conclusions from Output

```
User: "Based on this docking result, what can I conclude about drug binding?"

Research Agent Response:
"Analysis of your AutoDock Vina results:

Binding affinity: -8.4 kcal/mol
This is comparable to known inhibitors of this target [1]:
- Gefitinib: -8.1 kcal/mol [2]
- Erlotinib: -7.9 kcal/mol [2]

Key interactions:
- Your compound shows H-bond with Met793 (conserved in EGFR inhibitors) [3]
- Hydrophobic contact with Leu718 matches Type I inhibitor profile [4]

Conclusion: Binding profile suggests potential as EGFR inhibitor, warranting
cellular assays. Similar binding mode to approved drugs is encouraging.

Sources:
[1] Yun CH et al. (2007) EGFR kinase domain structure
[2] Park JH et al. (2019) Comparative docking of EGFR inhibitors
[3] Liu Y et al. (2018) Structural basis of EGFR inhibition
[4] Wu J et al. (2020) Classification of kinase inhibitor binding modes"
```

---

## Part 3: Architecture (Multi-Agent with Skill-Enhanced Research)

### 3.1 High-Level Flow

Intent classification happens at the `AIAssistant` level, routing to specialized agents. The **ResearchAgent** internally uses **SkillLoader** as an implementation detail.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AIAssistant                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   User Query                                                             │
│       │                                                                  │
│       ▼                                                                  │
│   ┌────────────────────────────────────────────────────────────────────┐│
│   │              UNIFIED INTENT ROUTER                                  ││
│   │                                                                     ││
│   │   Intent Types:                                                    ││
│   │   • workflow_generation → AgentOrchestrator                        ││
│   │   • research_question → ResearchAgent                              ││
│   │   • result_comparison → ResearchAgent                              ││
│   │   • conclusion_drawing → ResearchAgent                             ││
│   │   • tool_search → UnifiedToolSearch                                ││
│   └────────────────────────────┬───────────────────────────────────────┘│
│                                │                                         │
│         ┌──────────────────────┼──────────────────────────────────────┐ │
│         ▼                      ▼                                      ▼ │
│   ┌───────────────┐    ┌───────────────┐                    ┌─────────┐│
│   │ AgentOrch.    │    │ ResearchAgent │                    │ToolSrch ││
│   │ (existing)    │    │ (NEW)         │                    │(exists) ││
│   │               │    │               │                    │         ││
│   │ • DomainRouter│    │ Internally:   │                    │         ││
│   │ • Specialists │    │ • SkillLoader │                    │         ││
│   │ • Assembler   │    │ • LitSearch   │                    │         ││
│   │               │    │ • Synthesizer │                    │         ││
│   └───────────────┘    └───────────────┘                    └─────────┘│
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 ResearchAgent Internal Architecture

The ResearchAgent is a **multi-agent system** that uses SkillLoader internally to guide its sub-agents:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         RESEARCH AGENT                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Input: (query, intent_type, workflow_results?)                        │
│       │                                                                  │
│       ▼                                                                  │
│   ┌────────────────────────────────────────────────────────────────────┐│
│   │                    SKILL LOADER (Internal)                          ││
│   │                                                                     ││
│   │   Loads relevant skill prompts based on task:                      ││
│   │   • research_question → hypothesis-generation, pubmed-database     ││
│   │   • result_comparison → peer-review, pubmed-database               ││
│   │   • conclusion_drawing → exploratory-data-analysis                 ││
│   │                                                                     ││
│   │   Skills guide how sub-agents behave, NOT top-level routing        ││
│   └────────────────────────────┬───────────────────────────────────────┘│
│                                │                                         │
│                                ▼                                         │
│   ┌────────────────────────────────────────────────────────────────────┐│
│   │                    SUB-AGENTS (Parallel)                            ││
│   │                                                                     ││
│   │   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐   ││
│   │   │ LiteratureSearch│  │ QueryAnalyzer   │  │ ContextBuilder  │   ││
│   │   │ Agent           │  │ Agent           │  │ Agent           │   ││
│   │   │                 │  │                 │  │                 │   ││
│   │   │ Uses:           │  │ Uses:           │  │ Uses:           │   ││
│   │   │ • pubmed skill  │  │ • hypothesis    │  │ • peer-review   │   ││
│   │   │ • query_pubmed  │  │   skill         │  │   skill         │   ││
│   │   │ • query_arxiv   │  │ • Extracts key  │  │ • Builds context│   ││
│   │   │ • Sem. Scholar  │  │   terms         │  │   from results  │   ││
│   │   └────────┬────────┘  └────────┬────────┘  └────────┬────────┘   ││
│   │            │                    │                    │             ││
│   └────────────┼────────────────────┼────────────────────┼─────────────┘│
│                │                    │                    │              │
│                └────────────────────┼────────────────────┘              │
│                                     ▼                                    │
│   ┌────────────────────────────────────────────────────────────────────┐│
│   │                    SYNTHESIS AGENT                                  ││
│   │                                                                     ││
│   │   Uses skill-guided prompts to:                                    ││
│   │   • Combine literature findings                                    ││
│   │   • Compare with user's workflow results (if any)                  ││
│   │   • Generate evidence-based response with citations                ││
│   │   • Apply critical thinking skill for caveats                      ││
│   └────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│   Output: ResearchResponse(answer, citations, confidence, follow_ups)   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 SkillLoader Design (Internal to ResearchAgent)

The SkillLoader is an **internal component** of ResearchAgent that manages loading and caching of claude-scientific-skills:

```python
class SkillLoader:
    """
    Loads claude-scientific-skills dynamically based on task type.
    Skills are prompt documents that guide Claude's responses.
    """

    SKILLS_BASE_PATH = "/home/yzhang/biomate/research_repos/claude-scientific-skills-biomate"

    # Map intents to skills
    INTENT_TO_SKILLS = {
        UserIntent.RESEARCH_QUESTION: [
            "scientific-thinking/hypothesis-generation",
            "scientific-databases/pubmed-database"
        ],
        UserIntent.RESULT_COMPARISON: [
            "scientific-thinking/peer-review",
            "scientific-databases/pubmed-database"
        ],
        UserIntent.CONCLUSION_DRAWING: [
            "scientific-thinking/exploratory-data-analysis",
            "scientific-thinking/scientific-critical-thinking"
        ]
    }

    def load_skills(self, intent: UserIntent, include_references: bool = False) -> str:
        """Load skill prompts for the given intent."""
        skill_paths = self.INTENT_TO_SKILLS.get(intent, [])
        combined_prompt = ""

        for skill_path in skill_paths:
            skill_md = self._load_skill_file(skill_path)
            combined_prompt += f"\n## {skill_path.split('/')[-1].upper()} SKILL\n{skill_md}\n"

            if include_references:
                refs = self._load_references(skill_path)
                combined_prompt += refs

        return combined_prompt
```

### 3.4 Intent-to-Skill Mapping (Used by ResearchAgent)

| Intent | Primary Skill | Secondary Skills | BioMate Tools Used |
|--------|--------------|------------------|-------------------|
| `research_question` | hypothesis-generation | pubmed-database | query_pubmed, query_arxiv, advanced_web_search_claude |
| `result_comparison` | peer-review | pubmed-database | query_pubmed, extract_pdf_content |
| `conclusion_drawing` | exploratory-data-analysis | scientific-critical-thinking | (workflow outputs) |
| `literature_survey` | pubmed-database | scientific-writing | query_pubmed, query_scholar |

### 3.5 Integration Flow Examples

**User asks a research question:**
```
User: "What's the best alignment algorithm for long-read RNA-seq?"

1. UnifiedIntentRouter.route(query)
   → Keywords: "best", "algorithm" → research_question (confidence: 0.85)

2. AIAssistant routes to ResearchAgent.answer(query, intent=RESEARCH_QUESTION)

3. ResearchAgent internally:
   a) SkillLoader loads: hypothesis-generation + pubmed-database skills
   b) LiteratureSearchAgent (parallel):
      - Uses pubmed skill to build optimal query
      - Calls query_pubmed, query_arxiv
      - Returns relevant papers
   c) QueryAnalyzerAgent:
      - Uses hypothesis skill to extract key concepts
      - Identifies comparison criteria
   d) SynthesisAgent:
      - Combines literature with skill-guided prompts
      - Generates evidence-based response with citations

4. ResearchAgent returns ResearchResponse:
   - answer: "For long-read RNA-seq, minimap2 is recommended [1]..."
   - citations: [{title: "Minimap2...", pmid: "...", ...}]
   - confidence: 0.85
   - follow_up_suggestions: ["How does minimap2 handle splice sites?"]

5. Return formatted response to user
```

**User asks to compare results:**
```
User: "How do my DEG results compare with other BRCA1 studies?"
Context: workflow_results from recent DESeq2 run

1. UnifiedIntentRouter.route(query, has_workflow_context=True)
   → result_comparison (confidence: 0.9)

2. AIAssistant routes to ResearchAgent.answer(query, intent=RESULT_COMPARISON, workflow_results=...)

3. ResearchAgent internally:
   a) SkillLoader loads: peer-review + pubmed-database skills
   b) ContextBuilderAgent:
      - Uses peer-review skill framework
      - Extracts key findings from user's DEG results
      - Identifies comparison points (gene lists, fold changes, pathways)
   c) LiteratureSearchAgent (parallel):
      - Searches for BRCA1 differential expression studies
      - Returns relevant papers with DEG lists
   d) SynthesisAgent:
      - Uses peer-review skill to structure comparison
      - Highlights agreements, novel findings, discrepancies
      - Generates comparison with citations

4. ResearchAgent returns comparison with literature backing

5. Return formatted response to user
```

**User asks to draw conclusions:**
```
User: "What can I conclude from this docking result?"
Context: AutoDock Vina output

1. UnifiedIntentRouter.route(query, has_workflow_context=True)
   → conclusion_drawing (confidence: 0.85)

2. AIAssistant routes to ResearchAgent.answer(query, intent=CONCLUSION_DRAWING, workflow_results=...)

3. ResearchAgent internally:
   a) SkillLoader loads: exploratory-data-analysis + scientific-critical-thinking skills
   b) ContextBuilderAgent:
      - Parses docking results (binding affinity, poses)
      - Uses EDA skill for pattern recognition
   c) LiteratureSearchAgent (parallel):
      - Searches for reference compounds against same target
      - Returns benchmark binding affinities
   d) SynthesisAgent:
      - Uses critical thinking skill for caveats
      - Interprets results in context of literature
      - Notes limitations, suggests validation

4. ResearchAgent returns evidence-based conclusions

5. Return formatted response to user
```

---

## Part 4: Implementation

### 4.1 UnifiedIntentRouter (New Component)

```python
# lib/galaxy/ai/agents/unified_intent_router.py

"""
Unified Intent Router

Routes user queries to appropriate handlers based on intent:
- workflow_generation → AgentOrchestrator
- research_question → ResearchAgent
- result_comparison → ResearchAgent
- conclusion_drawing → ResearchAgent
- tool_search → UnifiedToolSearch

Uses same hybrid pattern as EnhancedDomainRouter:
- Fast keyword matching for high confidence
- LLM fallback for ambiguous queries
"""

import re
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any
from enum import Enum

log = logging.getLogger(__name__)


class UserIntent(Enum):
    """Types of user intents."""
    WORKFLOW_GENERATION = "workflow_generation"
    RESEARCH_QUESTION = "research_question"
    RESULT_COMPARISON = "result_comparison"
    CONCLUSION_DRAWING = "conclusion_drawing"
    TOOL_SEARCH = "tool_search"
    GENERAL_CHAT = "general_chat"


@dataclass
class IntentDecision:
    """Result of intent routing."""
    intent: UserIntent
    confidence: float
    routing_method: str  # 'keyword' or 'llm'
    has_workflow_context: bool
    extracted_entities: Dict[str, Any] = field(default_factory=dict)
    matched_patterns: List[str] = field(default_factory=list)


class UnifiedIntentRouter:
    """
    Routes user queries to appropriate handlers.

    Follows same hybrid pattern as EnhancedDomainRouter:
    - Fast keyword matching for high confidence (>0.7)
    - LLM fallback for ambiguous queries
    """

    LLM_THRESHOLD = 0.7

    # Keyword patterns for each intent (ordered by priority)
    INTENT_PATTERNS = {
        UserIntent.WORKFLOW_GENERATION: [
            r'\b(run|execute|perform|do)\b.*(analysis|workflow|pipeline)',
            r'\b(create|build|generate|make)\b.*(workflow|pipeline)',
            r'\b(analyze|process)\b.*\b(my|the|this)\b.*\b(data|file|sample)',
            r'\bpipeline\s+for\b',
            r'\bworkflow\s+to\b',
        ],
        UserIntent.RESULT_COMPARISON: [
            r'\b(compare|comparison)\b.*(result|finding|output)',
            r'\b(consistent|similar|differ)\b.*(literature|paper|study|publication)',
            r'\bhow\s+(do|does)\s+(my|these)\s+result',
            r'\b(match|align)\b.*(published|known|existing)',
        ],
        UserIntent.CONCLUSION_DRAWING: [
            r'\b(conclude|conclusion|interpret|interpretation)\b',
            r'\bwhat\s+(can|do|does)\s+(i|we|this)\s+(conclude|mean)',
            r'\bexplain\s+(these|my|the)\s+result',
            r'\bwhat\s+does\s+this\s+(mean|indicate|suggest)',
            r'\binterpret\s+(these|my|the)',
        ],
        UserIntent.RESEARCH_QUESTION: [
            r'\bwhat\s+is\s+(the\s+)?(best|recommended|optimal)',
            r'\bhow\s+(does|do|can|should)\b',
            r'\bwhy\s+(does|do|is|are)\b',
            r'\bwhich\s+(tool|method|approach|algorithm)',
            r'\brecommend\b',
            r'\bbest\s+practice',
            r'\bwhat\s+are\s+the\s+(advantages|disadvantages|pros|cons)',
        ],
        UserIntent.TOOL_SEARCH: [
            r'\b(find|search|look\s+for)\b.*\btool',
            r'\bwhat\s+tools?\s+(can|are|is)',
            r'\bavailable\s+tools?\b',
            r'\btools?\s+for\b',
        ],
    }

    def __init__(self, llm_client=None):
        self.llm_client = llm_client
        self._compile_patterns()

    def _compile_patterns(self):
        """Pre-compile regex patterns for performance."""
        self._compiled_patterns = {}
        for intent, patterns in self.INTENT_PATTERNS.items():
            self._compiled_patterns[intent] = [
                re.compile(p, re.IGNORECASE) for p in patterns
            ]

    def route(
        self,
        query: str,
        has_workflow_context: bool = False,
        user_context: Optional[Dict] = None
    ) -> IntentDecision:
        """
        Route query to appropriate handler.

        Args:
            query: User's query
            has_workflow_context: Whether user has recent workflow results
            user_context: Optional user context

        Returns:
            IntentDecision with intent type and confidence
        """
        # Fast path: keyword matching
        keyword_result = self._keyword_route(query, has_workflow_context)

        if keyword_result.confidence >= self.LLM_THRESHOLD:
            return keyword_result

        # Slow path: LLM analysis (if available and confidence is low)
        if self.llm_client and keyword_result.confidence < self.LLM_THRESHOLD:
            return self._llm_route(query, keyword_result, has_workflow_context)

        return keyword_result

    def _keyword_route(
        self,
        query: str,
        has_workflow_context: bool
    ) -> IntentDecision:
        """Fast keyword-based routing."""
        scores = {}
        matched = {}

        for intent, patterns in self._compiled_patterns.items():
            score = 0.0
            matches = []
            for pattern in patterns:
                if pattern.search(query):
                    score += 0.3
                    matches.append(pattern.pattern)
            scores[intent] = min(score, 1.0)
            matched[intent] = matches

        # Boost result_comparison and conclusion_drawing if has_workflow_context
        if has_workflow_context:
            scores[UserIntent.RESULT_COMPARISON] *= 1.3
            scores[UserIntent.CONCLUSION_DRAWING] *= 1.3

        # Find best match
        best_intent = max(scores, key=scores.get)
        best_score = scores[best_intent]

        # Default to general_chat if no good match
        if best_score < 0.2:
            best_intent = UserIntent.GENERAL_CHAT
            best_score = 0.5

        return IntentDecision(
            intent=best_intent,
            confidence=min(best_score, 1.0),
            routing_method='keyword',
            has_workflow_context=has_workflow_context,
            matched_patterns=matched.get(best_intent, [])
        )

    def _llm_route(
        self,
        query: str,
        keyword_hint: IntentDecision,
        has_workflow_context: bool
    ) -> IntentDecision:
        """LLM-based routing for ambiguous queries."""
        prompt = f"""Classify this user query into one of these intent categories:

Query: "{query}"
User has workflow results: {has_workflow_context}

Categories:
- workflow_generation: User wants to run/create/execute an analysis pipeline
- research_question: User is asking about methods, tools, best practices
- result_comparison: User wants to compare their results with literature
- conclusion_drawing: User wants to interpret/understand their results
- tool_search: User is looking for specific tools
- general_chat: General conversation, not fitting above

Respond with JSON:
{{"intent": "category_name", "confidence": 0.0-1.0, "reason": "brief explanation"}}
"""
        try:
            response = self.llm_client.generate(prompt, max_tokens=150, temperature=0.1)
            import json
            result = json.loads(response)

            intent_str = result.get('intent', 'general_chat')
            try:
                intent = UserIntent(intent_str)
            except ValueError:
                intent = keyword_hint.intent

            return IntentDecision(
                intent=intent,
                confidence=result.get('confidence', 0.5),
                routing_method='llm',
                has_workflow_context=has_workflow_context,
                extracted_entities={'llm_reason': result.get('reason', '')}
            )
        except Exception as e:
            log.warning(f"LLM intent routing failed: {e}, using keyword result")
            return keyword_hint
```

### 4.2 AIAssistant Integration

```python
# lib/galaxy/ai/ai_assistant.py (modifications)

class AIAssistant:
    def __init__(self, config: Optional[AIConfig] = None, galaxy_app=None):
        # ... existing init ...
        self._intent_router = None
        self._research_agent = None

    @property
    def intent_router(self):
        """Lazy-load UnifiedIntentRouter."""
        if self._intent_router is None:
            from .agents.unified_intent_router import UnifiedIntentRouter
            from .llm_client import LLMClient
            llm_client = LLMClient(self.config)
            self._intent_router = UnifiedIntentRouter(llm_client=llm_client)
            log.info("UnifiedIntentRouter loaded on-demand")
        return self._intent_router

    @property
    def research_agent(self):
        """Lazy-load ResearchAgent."""
        if self._research_agent is None:
            from .agents.research_agent import ResearchAgent
            from .services.semantic_scholar_client import SemanticScholarClient
            from .services.pubmed_client import PubMedClient
            from .llm_client import LLMClient

            llm_client = LLMClient(self.config)
            pubmed = PubMedClient(api_key=self.config.pubmed_api_key)
            semantic_scholar = SemanticScholarClient()

            self._research_agent = ResearchAgent(
                llm_client=llm_client,
                pubmed_client=pubmed,
                semantic_scholar_client=semantic_scholar
            )
            log.info("ResearchAgent loaded on-demand")
        return self._research_agent

    async def process_query(
        self,
        query: str,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        workflow_results: Optional[Dict] = None,
        uploaded_datasets: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Main entry point - routes query to appropriate handler based on intent.

        Args:
            query: User's natural language query
            user_id: Optional user ID for personalization
            session_id: Optional session ID for audit
            workflow_results: Optional recent workflow results for context
            uploaded_datasets: Optional user's uploaded datasets

        Returns:
            Response dict with type-specific content
        """
        # 1. Route intent
        intent_decision = self.intent_router.route(
            query=query,
            has_workflow_context=workflow_results is not None
        )

        log.info(f"Intent routed: {intent_decision.intent.value} "
                f"(confidence={intent_decision.confidence:.2f}, "
                f"method={intent_decision.routing_method})")

        # 2. Dispatch to appropriate handler
        if intent_decision.intent == UserIntent.WORKFLOW_GENERATION:
            return self.generate_workflow_multi_agent(
                user_intent=query,
                user_id=user_id,
                session_id=session_id,
                uploaded_datasets=uploaded_datasets
            )

        elif intent_decision.intent in [
            UserIntent.RESEARCH_QUESTION,
            UserIntent.RESULT_COMPARISON,
            UserIntent.CONCLUSION_DRAWING
        ]:
            response = await self.research_agent.answer(
                query=query,
                workflow_results=workflow_results,
                intent_type=intent_decision.intent
            )
            return {
                'type': 'research_response',
                'intent': intent_decision.intent.value,
                'answer': response.answer,
                'citations': [c.__dict__ for c in response.citations],
                'confidence': response.confidence,
                'follow_up_suggestions': response.follow_up_suggestions,
                'routing_method': intent_decision.routing_method
            }

        elif intent_decision.intent == UserIntent.TOOL_SEARCH:
            # Use existing tool search
            results = self.unified_tool_search.search(query)
            return {
                'type': 'tool_search',
                'tools': results,
                'routing_method': intent_decision.routing_method
            }

        else:
            # General chat - direct LLM response
            return {
                'type': 'general_chat',
                'response': await self._generate_chat_response(query),
                'routing_method': intent_decision.routing_method
            }
```

### 4.3 ResearchAgent Class

```python
# lib/galaxy/ai/agents/research_agent.py

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any
from enum import Enum
import asyncio

from ..llm_client import LLMClient
from ..types.citation import Citation

class QueryType(Enum):
    GENERAL_QUESTION = "general_question"
    RESULT_COMPARISON = "result_comparison"
    CONCLUSION_DRAWING = "conclusion_drawing"
    LITERATURE_SURVEY = "literature_survey"


@dataclass
class ResearchResponse:
    """Response from ResearchAgent with citations."""
    answer: str
    citations: List[Citation]
    confidence: float
    query_type: QueryType
    follow_up_suggestions: List[str] = field(default_factory=list)
    related_workflows: List[str] = field(default_factory=list)


class ResearchAgent:
    """
    Agent for answering research questions with literature backing.

    Capabilities:
    - Answer user questions with literature synthesis
    - Compare workflow results with published findings
    - Draw evidence-based conclusions from outputs
    - Provide inline citations and sources
    """

    def __init__(
        self,
        llm_client: LLMClient,
        pubmed_client=None,
        semantic_scholar_client=None,
        cache_enabled: bool = True
    ):
        self.llm = llm_client
        self.pubmed = pubmed_client
        self.semantic_scholar = semantic_scholar_client
        self._cache = {} if cache_enabled else None

    async def answer(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None,
        workflow_results: Optional[Dict] = None,
        max_citations: int = 5
    ) -> ResearchResponse:
        """
        Answer a research question with literature backing.

        Args:
            query: User's question
            context: Optional context (user history, domain, etc.)
            workflow_results: Optional workflow output to analyze
            max_citations: Maximum citations to include

        Returns:
            ResearchResponse with answer, citations, and metadata
        """
        # 1. Classify query type
        query_type = await self._classify_query(query, workflow_results)

        # 2. Search relevant literature
        papers = await self._search_literature(query, query_type, max_citations * 2)

        # 3. Compress and synthesize
        synthesis = await self._synthesize_literature(papers, query, query_type)

        # 4. Generate response
        if query_type == QueryType.RESULT_COMPARISON and workflow_results:
            answer = await self._compare_with_literature(
                workflow_results, synthesis, query
            )
        elif query_type == QueryType.CONCLUSION_DRAWING and workflow_results:
            answer = await self._draw_conclusions(
                workflow_results, synthesis, query
            )
        else:
            answer = await self._answer_question(query, synthesis)

        # 5. Extract citations used
        citations = self._extract_citations(answer, papers)

        return ResearchResponse(
            answer=answer,
            citations=citations[:max_citations],
            confidence=self._calculate_confidence(citations, synthesis),
            query_type=query_type,
            follow_up_suggestions=await self._suggest_followups(query, answer)
        )

    async def _classify_query(
        self,
        query: str,
        workflow_results: Optional[Dict]
    ) -> QueryType:
        """Classify the type of research query."""
        prompt = f"""Classify this research query:

Query: {query}
Has workflow results: {workflow_results is not None}

Categories:
- general_question: Asking about methods, tools, concepts
- result_comparison: Comparing results with existing literature
- conclusion_drawing: Drawing conclusions from analysis output
- literature_survey: Requesting overview of a topic

Respond with just the category name."""

        response = await self.llm.generate(prompt, max_tokens=50)
        return QueryType(response.strip().lower())

    async def _search_literature(
        self,
        query: str,
        query_type: QueryType,
        limit: int
    ) -> List[Dict]:
        """Search multiple literature sources."""
        # Build optimized search query
        search_query = self._build_search_query(query, query_type)

        # Search in parallel
        tasks = []
        if self.pubmed:
            tasks.append(self.pubmed.search(search_query, limit=limit))
        if self.semantic_scholar:
            tasks.append(self.semantic_scholar.search(search_query, limit=limit))

        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Combine and deduplicate
        papers = []
        seen_dois = set()
        for result in results:
            if isinstance(result, Exception):
                continue
            for paper in result:
                doi = paper.get('doi')
                if doi and doi not in seen_dois:
                    seen_dois.add(doi)
                    papers.append(paper)
                elif not doi:
                    papers.append(paper)

        return papers[:limit]

    async def _synthesize_literature(
        self,
        papers: List[Dict],
        query: str,
        query_type: QueryType
    ) -> Dict:
        """Compress and synthesize literature (Kosmos-style 20:1 compression)."""
        if not papers:
            return {"summary": "", "key_findings": [], "conflicts": []}

        # Build paper summaries
        paper_texts = []
        for p in papers[:10]:  # Limit to top 10
            text = f"""
Title: {p.get('title', 'Unknown')}
Authors: {', '.join(p.get('authors', [])[:3])}
Year: {p.get('year', 'Unknown')}
Abstract: {p.get('abstract', 'No abstract')[:500]}
"""
            paper_texts.append(text)

        combined = "\n---\n".join(paper_texts)

        prompt = f"""Synthesize these papers to answer: {query}

Papers:
{combined}

Provide:
1. Key findings relevant to the question
2. Points of agreement across papers
3. Any conflicts or debates
4. Gaps in current knowledge

Be concise (compress 20:1). Extract only what's needed to answer the question."""

        response = await self.llm.generate(prompt, max_tokens=1000)

        return {
            "summary": response,
            "papers": papers,
            "query_type": query_type
        }

    async def _compare_with_literature(
        self,
        workflow_results: Dict,
        synthesis: Dict,
        query: str
    ) -> str:
        """Compare workflow results with published findings."""
        prompt = f"""Compare these analysis results with published literature:

User's Results:
{self._format_results(workflow_results)}

Literature Synthesis:
{synthesis.get('summary', 'No synthesis available')}

User's Question: {query}

Provide a comparison that:
1. Shows how user's results align with or differ from published findings
2. Highlights any novel findings
3. Notes any expected vs unexpected results
4. Uses inline citations [1], [2], etc.

Be specific and cite relevant papers."""

        return await self.llm.generate(prompt, max_tokens=1500)

    async def _draw_conclusions(
        self,
        workflow_results: Dict,
        synthesis: Dict,
        query: str
    ) -> str:
        """Draw evidence-based conclusions from output."""
        prompt = f"""Draw conclusions from these analysis results:

Results:
{self._format_results(workflow_results)}

Supporting Literature:
{synthesis.get('summary', 'No synthesis available')}

User's Question: {query}

Provide conclusions that:
1. Interpret the results in biological/scientific context
2. Support interpretations with literature evidence [1], [2]
3. Note confidence level and caveats
4. Suggest next steps or validation experiments

Be balanced - note limitations."""

        return await self.llm.generate(prompt, max_tokens=1500)

    async def _answer_question(
        self,
        query: str,
        synthesis: Dict
    ) -> str:
        """Answer a general research question with citations."""
        prompt = f"""Answer this research question using the literature:

Question: {query}

Literature:
{synthesis.get('summary', 'No synthesis available')}

Provide an answer that:
1. Directly addresses the question
2. Uses inline citations [1], [2], etc.
3. Notes any uncertainty or debate in the field
4. Is clear for non-experts

Do NOT make claims without citation support."""

        return await self.llm.generate(prompt, max_tokens=1500)

    def _extract_citations(
        self,
        answer: str,
        papers: List[Dict]
    ) -> List[Citation]:
        """Extract citations used in the answer."""
        citations = []
        for i, paper in enumerate(papers):
            marker = f"[{i+1}]"
            if marker in answer:
                citations.append(Citation(
                    type="paper",
                    title=paper.get('title', 'Unknown'),
                    url=paper.get('url', ''),
                    doi=paper.get('doi'),
                    pmid=paper.get('pmid'),
                    authors=paper.get('authors', []),
                    year=paper.get('year'),
                    relevance=1.0 - (i * 0.1)  # Higher rank = more relevant
                ))
        return citations

    def _format_results(self, results: Dict) -> str:
        """Format workflow results for LLM prompt."""
        if not results:
            return "No results provided"
        # Truncate large results
        import json
        text = json.dumps(results, indent=2, default=str)
        if len(text) > 3000:
            text = text[:3000] + "\n... (truncated)"
        return text

    def _calculate_confidence(
        self,
        citations: List[Citation],
        synthesis: Dict
    ) -> float:
        """Calculate confidence score for the response."""
        if not citations:
            return 0.3  # Low confidence without citations

        # Factors: number of citations, recency, agreement
        base = min(len(citations) * 0.15, 0.6)  # Up to 0.6 from citations

        # Recency bonus
        recent_count = sum(1 for c in citations if c.year and c.year >= 2020)
        recency = min(recent_count * 0.1, 0.2)

        return min(base + recency + 0.2, 1.0)  # Cap at 1.0

    async def _suggest_followups(
        self,
        query: str,
        answer: str
    ) -> List[str]:
        """Suggest follow-up questions or actions."""
        prompt = f"""Based on this Q&A, suggest 2-3 follow-up questions:

Question: {query}
Answer: {answer[:500]}

Provide short, specific follow-up questions."""

        response = await self.llm.generate(prompt, max_tokens=200)
        return [q.strip() for q in response.split('\n') if q.strip()][:3]

    def _build_search_query(self, query: str, query_type: QueryType) -> str:
        """Build optimized search query for literature databases."""
        # Extract key terms and add domain-specific modifiers
        base_query = query

        if query_type == QueryType.RESULT_COMPARISON:
            base_query += " comparison benchmark"
        elif query_type == QueryType.GENERAL_QUESTION:
            base_query += " review methods"

        return base_query
```

### 4.2 Literature Clients

```python
# lib/galaxy/ai/services/semantic_scholar_client.py

import aiohttp
from typing import List, Dict, Optional
import asyncio

class SemanticScholarClient:
    """Client for Semantic Scholar API."""

    BASE_URL = "https://api.semanticscholar.org/graph/v1"

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key
        self._rate_limiter = asyncio.Semaphore(10)  # 100 req/5min = ~10/30sec

    async def search(
        self,
        query: str,
        limit: int = 10,
        fields: str = "title,authors,year,abstract,url,citationCount,externalIds"
    ) -> List[Dict]:
        """Search for papers."""
        async with self._rate_limiter:
            async with aiohttp.ClientSession() as session:
                params = {
                    "query": query,
                    "limit": limit,
                    "fields": fields
                }
                headers = {}
                if self.api_key:
                    headers["x-api-key"] = self.api_key

                async with session.get(
                    f"{self.BASE_URL}/paper/search",
                    params=params,
                    headers=headers
                ) as response:
                    if response.status != 200:
                        return []
                    data = await response.json()

                papers = []
                for p in data.get("data", []):
                    papers.append({
                        "title": p.get("title"),
                        "authors": [a.get("name") for a in p.get("authors", [])],
                        "year": p.get("year"),
                        "abstract": p.get("abstract"),
                        "url": p.get("url"),
                        "doi": p.get("externalIds", {}).get("DOI"),
                        "pmid": p.get("externalIds", {}).get("PubMed"),
                        "citations": p.get("citationCount", 0)
                    })
                return papers


# lib/galaxy/ai/services/pubmed_client.py

class PubMedClient:
    """Client for PubMed E-utilities API."""

    BASE_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

    def __init__(self, api_key: Optional[str] = None, email: Optional[str] = None):
        self.api_key = api_key
        self.email = email
        self._rate_limiter = asyncio.Semaphore(3 if not api_key else 10)

    async def search(self, query: str, limit: int = 10) -> List[Dict]:
        """Search PubMed for papers."""
        async with self._rate_limiter:
            # 1. Search for IDs
            ids = await self._esearch(query, limit)
            if not ids:
                return []

            # 2. Fetch details
            papers = await self._efetch(ids)
            return papers

    async def _esearch(self, query: str, limit: int) -> List[str]:
        """Search for PubMed IDs."""
        async with aiohttp.ClientSession() as session:
            params = {
                "db": "pubmed",
                "term": query,
                "retmax": limit,
                "retmode": "json"
            }
            if self.api_key:
                params["api_key"] = self.api_key

            async with session.get(
                f"{self.BASE_URL}/esearch.fcgi",
                params=params
            ) as response:
                if response.status != 200:
                    return []
                data = await response.json()
                return data.get("esearchresult", {}).get("idlist", [])

    async def _efetch(self, ids: List[str]) -> List[Dict]:
        """Fetch paper details by PMIDs."""
        async with aiohttp.ClientSession() as session:
            params = {
                "db": "pubmed",
                "id": ",".join(ids),
                "retmode": "xml"
            }
            if self.api_key:
                params["api_key"] = self.api_key

            async with session.get(
                f"{self.BASE_URL}/efetch.fcgi",
                params=params
            ) as response:
                if response.status != 200:
                    return []
                xml_text = await response.text()
                return self._parse_pubmed_xml(xml_text)

    def _parse_pubmed_xml(self, xml_text: str) -> List[Dict]:
        """Parse PubMed XML response."""
        import xml.etree.ElementTree as ET

        papers = []
        try:
            root = ET.fromstring(xml_text)
            for article in root.findall(".//PubmedArticle"):
                paper = {}

                # Title
                title_elem = article.find(".//ArticleTitle")
                paper["title"] = title_elem.text if title_elem is not None else ""

                # Authors
                authors = []
                for author in article.findall(".//Author"):
                    last = author.find("LastName")
                    first = author.find("ForeName")
                    if last is not None:
                        name = last.text
                        if first is not None:
                            name = f"{first.text} {name}"
                        authors.append(name)
                paper["authors"] = authors

                # Year
                year_elem = article.find(".//PubDate/Year")
                paper["year"] = int(year_elem.text) if year_elem is not None else None

                # Abstract
                abstract_elem = article.find(".//AbstractText")
                paper["abstract"] = abstract_elem.text if abstract_elem is not None else ""

                # PMID
                pmid_elem = article.find(".//PMID")
                pmid = pmid_elem.text if pmid_elem is not None else None
                paper["pmid"] = pmid
                paper["url"] = f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/" if pmid else ""

                # DOI
                doi_elem = article.find(".//ArticleId[@IdType='doi']")
                paper["doi"] = doi_elem.text if doi_elem is not None else None

                papers.append(paper)
        except ET.ParseError:
            pass

        return papers
```

### 4.3 Integration with AIAssistant

```python
# lib/galaxy/ai/ai_assistant.py (modifications)

class AIAssistant:
    def __init__(self, config: AIConfig = None, ...):
        # ... existing init ...
        self._research_agent = None

    @property
    def research_agent(self):
        """Lazy-load ResearchAgent."""
        if self._research_agent is None:
            from .agents.research_agent import ResearchAgent
            from .services.semantic_scholar_client import SemanticScholarClient
            from .services.pubmed_client import PubMedClient

            llm_client = self.llm_client

            # Initialize literature clients
            pubmed = PubMedClient(
                api_key=self.config.pubmed_api_key,
                email=self.config.contact_email
            )
            semantic_scholar = SemanticScholarClient(
                api_key=self.config.semantic_scholar_api_key
            )

            self._research_agent = ResearchAgent(
                llm_client=llm_client,
                pubmed_client=pubmed,
                semantic_scholar_client=semantic_scholar
            )
        return self._research_agent

    async def answer_research_question(
        self,
        query: str,
        context: Optional[Dict] = None,
        workflow_results: Optional[Dict] = None
    ) -> ResearchResponse:
        """Answer a research question with literature backing."""
        return await self.research_agent.answer(
            query=query,
            context=context,
            workflow_results=workflow_results
        )
```

### 4.4 API Endpoints

```python
# lib/galaxy/webapps/galaxy/api/ai_assistant.py (additions)

@router.post("/api/ai_assistant/research/ask")
async def ask_research_question(
    query: str = Body(..., description="Research question"),
    context: Optional[Dict] = Body(None, description="Optional context"),
    workflow_results: Optional[Dict] = Body(None, description="Workflow output to analyze"),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Answer a research question with literature-backed evidence.

    Use cases:
    - General questions about methods/tools
    - Comparing workflow results with literature
    - Drawing conclusions from analysis output
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    response = await ai_assistant.answer_research_question(
        query=query,
        context=context,
        workflow_results=workflow_results
    )

    return {
        "answer": response.answer,
        "citations": [
            {
                "title": c.title,
                "authors": c.authors,
                "year": c.year,
                "url": c.url,
                "doi": c.doi,
                "pmid": c.pmid
            }
            for c in response.citations
        ],
        "confidence": response.confidence,
        "query_type": response.query_type.value,
        "follow_up_suggestions": response.follow_up_suggestions
    }


@router.post("/api/ai_assistant/research/compare")
async def compare_results_with_literature(
    workflow_id: str = Body(..., description="Workflow ID"),
    results_summary: Dict = Body(..., description="Summary of results to compare"),
    focus_question: Optional[str] = Body(None, description="Specific aspect to compare"),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Compare workflow results with published literature.
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    query = focus_question or f"Compare these results with published findings"

    response = await ai_assistant.answer_research_question(
        query=query,
        workflow_results=results_summary
    )

    return {
        "comparison": response.answer,
        "citations": [c.__dict__ for c in response.citations],
        "confidence": response.confidence
    }
```

---

## Part 5: Files to Create

| File | Purpose |
|------|---------|
| `lib/galaxy/ai/agents/unified_intent_router.py` | **NEW** - High-level intent routing (keyword + LLM) |
| `lib/galaxy/ai/agents/research_agent.py` | Main ResearchAgent class |
| `lib/galaxy/ai/services/semantic_scholar_client.py` | Semantic Scholar API client |
| `lib/galaxy/ai/services/pubmed_client.py` | PubMed E-utilities client |
| `lib/galaxy/ai/types/citation.py` | Citation data model |
| `lib/galaxy/ai/tests/test_intent_router.py` | Intent router tests |
| `lib/galaxy/ai/tests/test_research_agent.py` | ResearchAgent tests |

## Part 6: Files to Modify

| File | Changes |
|------|---------|
| `lib/galaxy/ai/ai_assistant.py` | Add `intent_router`, `research_agent` properties; Add `process_query()` method |
| `lib/galaxy/ai/agents/__init__.py` | Export `UnifiedIntentRouter`, `ResearchAgent` |
| `lib/galaxy/ai/config.py` | Add `pubmed_api_key`, `semantic_scholar_api_key` configs |
| `lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Update `/chat` endpoint to use `process_query()` |
| `requirements.txt` | Add `aiohttp` if not present |

---

## Part 7: Implementation Timeline

### Phase 1: Core Agent (3-4 days)
- Create ResearchAgent class
- Implement query classification
- Implement literature synthesis

### Phase 2: Literature Clients (2-3 days)
- PubMed client with E-utilities
- Semantic Scholar client
- Rate limiting and caching

### Phase 3: Integration (2-3 days)
- Add to AIAssistant
- API endpoints
- Error handling

### Phase 4: Testing & Polish (2-3 days)
- Unit tests
- Integration tests
- Response quality tuning

**Total: ~2 weeks**

---

## Part 8: What's NOT Included (Intentionally)

| Feature | Reason |
|---------|--------|
| ToolUniverse tool integration | BioMate already has 9,103 tools |
| Full paper generation | Not our focus |
| Hypothesis generation | Low priority, can add later |
| Knowledge graph | Complex, low ROI for initial version |

---

---

# PART B: INTELLIGENT EXECUTION & BACKGROUND TASK SYSTEM

This section covers the intelligent execution strategy, background task management, and seamless multi-chat experience that makes BioMate a true AI assistant.

---

## Part 9: The Problem Statement

### Current Limitations

1. **No Intelligent Execution Strategy**
   - User must manually decide: pilot run vs full run
   - No guidance on when to test first vs run immediately
   - No consideration of dataset size, complexity, or user experience

2. **Blocking Workflow Execution**
   - User cannot continue chatting while workflow runs
   - Must wait for completion or lose context
   - Cannot start new projects during long runs

3. **No Background Task Tracking**
   - If user closes browser, no way to know workflow completed
   - No notifications (chat or email)
   - No way to track multiple running workflows

4. **Pilot Run Not Integrated**
   - Pilot panel exists but user must manually trigger it
   - No intelligent suggestion of "you should test this first"
   - No connection between pilot results and full run decision

### The Vision

```
User: "Analyze my RNA-seq data with 500 samples"

BioMate: "I've created a workflow for your 500-sample RNA-seq analysis.

📊 **Recommendation**: This is a large dataset with a new workflow.
   I suggest running a **pilot test** on 50 samples first to:
   - Verify parameters work correctly
   - Estimate full run time (~3h based on similar analyses)
   - Catch any issues before processing all data

   [🧪 Start Pilot (5 min)] [▶️ Run Full (skip pilot)] [💬 Ask me questions]

User: [Clicks "Start Pilot"]

BioMate: "Pilot started! You can:
   - Continue chatting - I'll notify you when it's done
   - Start a new project - this runs in the background
   - Ask me research questions while you wait

   📬 I'll also email you when complete."

[User continues chatting about research questions...]

BioMate: "✅ **Pilot Complete!**
   - Runtime: 4m 32s
   - Estimated full run: 2h 45m
   - All quality checks passed
   - Recommended parameter change: --min-counts 10 → 5

   [📊 View Results] [🚀 Start Full Run] [🔄 Adjust & Re-run]"
```

---

## Part 10: Execution Strategy Advisor

### 10.1 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      EXECUTION STRATEGY ADVISOR                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Workflow + Dataset + User Context                                          │
│               │                                                              │
│               ▼                                                              │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                    ANALYSIS FACTORS                                    │ │
│   │                                                                        │ │
│   │   Dataset:                    Workflow:                               │ │
│   │   • Sample count              • Step count                            │ │
│   │   • File size (total)         • Tool complexity                       │ │
│   │   • Is new upload?            • Has user run before?                  │ │
│   │   • Data type                 • Known failure rate                    │ │
│   │                                                                        │ │
│   │   User:                       Estimates:                              │ │
│   │   • Experience level          • Runtime (from history)                │ │
│   │   • Pilot preference          • Memory requirement                    │ │
│   │   • Recent corrections        • Cost (if cloud)                       │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│               │                                                              │
│               ▼                                                              │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                    DECISION ENGINE                                     │ │
│   │                                                                        │ │
│   │   Rules + Learned Patterns → Strategy Recommendation                  │ │
│   │                                                                        │ │
│   │   Outputs:                                                            │ │
│   │   • execution_mode: "pilot_first" | "direct_run" | "ask_user"        │ │
│   │   • run_mode: "foreground" | "background"                            │ │
│   │   • pilot_config: {fraction, strategy, ...}                          │ │
│   │   • confidence: 0.0-1.0                                              │ │
│   │   • reasoning: "why this recommendation"                             │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│               │                                                              │
│               ▼                                                              │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                    USER PRESENTATION                                   │ │
│   │                                                                        │ │
│   │   High confidence → Show recommendation with rationale                │ │
│   │   Medium confidence → Show options with pros/cons                     │ │
│   │   Low confidence → Ask user preference                                │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 10.2 Decision Matrix

| Condition | Execution Mode | Run Mode | Reasoning |
|-----------|---------------|----------|-----------|
| New dataset + Unknown workflow | `pilot_first` | background | Test with subset to catch issues early |
| Dataset > 100 samples | `pilot_first` | background | Large dataset benefits from pilot |
| Estimated runtime > 10 min | `direct_run` | background | Run in background, notify on completion |
| Estimated runtime 2-10 min | `direct_run` | foreground | Reasonable wait, show progress |
| Estimated runtime < 2 min | `direct_run` | foreground | Quick run, keep user engaged |
| User ran similar workflow before | `direct_run` | depends on size | Trust user's parameters |
| Workflow has high failure rate (>20%) | `pilot_first` | background | Reduce wasted compute |
| User explicitly prefers pilot | `pilot_first` | background | Respect user preference |
| User is new (< 5 workflows) | `pilot_first` | background | Help learn the system |
| Complex workflow (> 5 steps) | `pilot_first` | background | More things can go wrong |

### 10.3 Implementation

```python
# lib/galaxy/ai/execution/strategy_advisor.py

"""
Execution Strategy Advisor

Analyzes workflow, dataset, and user context to recommend
optimal execution strategy (pilot vs full, foreground vs background).
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any
from enum import Enum
import logging

log = logging.getLogger(__name__)


class ExecutionMode(Enum):
    """Recommended execution mode."""
    PILOT_FIRST = "pilot_first"      # Run pilot before full
    DIRECT_RUN = "direct_run"        # Run full directly
    ASK_USER = "ask_user"            # Not confident, ask user


class RunMode(Enum):
    """Whether to run in foreground or background."""
    FOREGROUND = "foreground"  # User waits, sees progress
    BACKGROUND = "background"  # User continues, gets notified


@dataclass
class ExecutionStrategy:
    """Recommended execution strategy."""
    execution_mode: ExecutionMode
    run_mode: RunMode
    confidence: float
    reasoning: str

    # Pilot configuration (if pilot_first)
    pilot_config: Optional[Dict] = None

    # Estimates
    estimated_runtime_seconds: Optional[int] = None
    estimated_memory_gb: Optional[float] = None

    # User presentation
    recommendation_message: str = ""
    options: List[Dict[str, Any]] = field(default_factory=list)


@dataclass
class DatasetAnalysis:
    """Analysis of user's dataset."""
    sample_count: int
    total_size_bytes: int
    file_count: int
    data_types: List[str]
    is_new_upload: bool
    has_quality_issues: bool = False


@dataclass
class WorkflowAnalysis:
    """Analysis of the workflow."""
    workflow_id: str
    step_count: int
    tool_ids: List[str]
    complexity_score: float  # 0-1, based on tools and connections
    historical_success_rate: float  # From past runs
    historical_avg_runtime: Optional[int]  # seconds
    user_has_run_before: bool
    requires_gpu: bool = False


@dataclass
class UserAnalysis:
    """Analysis of user context."""
    user_id: str
    total_workflows_run: int
    experience_level: str  # "novice", "intermediate", "expert"
    pilot_preference: Optional[bool]  # User's stated preference
    recent_correction_rate: float  # How often user corrects parameters
    domain_expertise: List[str]


class ExecutionStrategyAdvisor:
    """
    Analyzes context and recommends execution strategy.

    Factors considered:
    - Dataset size and characteristics
    - Workflow complexity and history
    - User experience and preferences
    - Estimated runtime and resources
    """

    # Thresholds (configurable)
    LARGE_DATASET_THRESHOLD = 100  # samples
    LONG_RUNTIME_THRESHOLD = 600   # 10 minutes
    MEDIUM_RUNTIME_THRESHOLD = 120 # 2 minutes
    HIGH_FAILURE_RATE = 0.2        # 20%
    COMPLEX_WORKFLOW_THRESHOLD = 5 # steps
    NOVICE_WORKFLOW_COUNT = 5

    def __init__(
        self,
        workflow_history_service=None,
        user_patterns_service=None,
        runtime_estimator=None
    ):
        self.workflow_history = workflow_history_service
        self.user_patterns = user_patterns_service
        self.runtime_estimator = runtime_estimator

    def analyze_and_recommend(
        self,
        workflow_id: str,
        workflow_ga: Dict,
        dataset_info: Dict,
        user_id: str
    ) -> ExecutionStrategy:
        """
        Analyze context and recommend execution strategy.

        Args:
            workflow_id: Workflow identifier
            workflow_ga: Galaxy workflow definition (ga format)
            dataset_info: Information about user's dataset
            user_id: User identifier

        Returns:
            ExecutionStrategy with recommendation
        """
        # 1. Analyze components
        dataset = self._analyze_dataset(dataset_info)
        workflow = self._analyze_workflow(workflow_id, workflow_ga, user_id)
        user = self._analyze_user(user_id)

        # 2. Estimate runtime
        estimated_runtime = self._estimate_runtime(workflow, dataset)

        # 3. Apply decision rules
        strategy = self._decide_strategy(dataset, workflow, user, estimated_runtime)

        # 4. Generate user-facing message
        strategy = self._generate_presentation(strategy, dataset, workflow, user)

        log.info(f"Strategy recommendation for workflow {workflow_id}: "
                f"mode={strategy.execution_mode.value}, "
                f"run={strategy.run_mode.value}, "
                f"confidence={strategy.confidence:.2f}")

        return strategy

    def _analyze_dataset(self, dataset_info: Dict) -> DatasetAnalysis:
        """Analyze user's dataset."""
        return DatasetAnalysis(
            sample_count=dataset_info.get('sample_count', 1),
            total_size_bytes=dataset_info.get('total_size_bytes', 0),
            file_count=dataset_info.get('file_count', 1),
            data_types=dataset_info.get('data_types', []),
            is_new_upload=dataset_info.get('is_new_upload', True),
            has_quality_issues=dataset_info.get('has_quality_issues', False)
        )

    def _analyze_workflow(
        self,
        workflow_id: str,
        workflow_ga: Dict,
        user_id: str
    ) -> WorkflowAnalysis:
        """Analyze workflow complexity and history."""
        steps = workflow_ga.get('steps', {})
        tool_ids = [s.get('tool_id') for s in steps.values() if s.get('tool_id')]

        # Get historical data if available
        success_rate = 0.8  # Default
        avg_runtime = None
        user_has_run = False

        if self.workflow_history:
            history = self.workflow_history.get_workflow_stats(workflow_id)
            if history:
                success_rate = history.get('success_rate', 0.8)
                avg_runtime = history.get('avg_runtime_seconds')
            user_has_run = self.workflow_history.user_has_run_workflow(
                user_id, workflow_id
            )

        # Calculate complexity score
        complexity = self._calculate_complexity(workflow_ga)

        return WorkflowAnalysis(
            workflow_id=workflow_id,
            step_count=len(steps),
            tool_ids=tool_ids,
            complexity_score=complexity,
            historical_success_rate=success_rate,
            historical_avg_runtime=avg_runtime,
            user_has_run_before=user_has_run
        )

    def _analyze_user(self, user_id: str) -> UserAnalysis:
        """Analyze user context and preferences."""
        if self.user_patterns:
            patterns = self.user_patterns.get_user_context(user_id)
            return UserAnalysis(
                user_id=user_id,
                total_workflows_run=patterns.get('total_workflows', 0),
                experience_level=patterns.get('experience_level', 'novice'),
                pilot_preference=patterns.get('pilot_preference'),
                recent_correction_rate=patterns.get('correction_rate', 0.1),
                domain_expertise=patterns.get('domain_expertise', [])
            )

        return UserAnalysis(
            user_id=user_id,
            total_workflows_run=0,
            experience_level='novice',
            pilot_preference=None,
            recent_correction_rate=0.1,
            domain_expertise=[]
        )

    def _estimate_runtime(
        self,
        workflow: WorkflowAnalysis,
        dataset: DatasetAnalysis
    ) -> int:
        """Estimate runtime in seconds."""
        if workflow.historical_avg_runtime:
            # Scale by sample count
            base = workflow.historical_avg_runtime
            # Simple linear scaling (can be improved with ML)
            return int(base * (dataset.sample_count / 10))

        if self.runtime_estimator:
            return self.runtime_estimator.estimate(
                workflow.tool_ids,
                dataset.sample_count
            )

        # Fallback: rough estimate based on steps and samples
        return workflow.step_count * dataset.sample_count * 30  # 30s per step per sample

    def _calculate_complexity(self, workflow_ga: Dict) -> float:
        """Calculate workflow complexity score 0-1."""
        steps = workflow_ga.get('steps', {})
        step_count = len(steps)

        if step_count == 0:
            return 0.0

        # Factors: step count, branching, tool types
        step_factor = min(step_count / 10, 1.0)

        # Check for complex tools
        complex_tools = {'hisat2', 'star', 'kallisto', 'salmon', 'deseq2', 'edger'}
        tools_used = {s.get('tool_id', '').lower() for s in steps.values()}
        complex_count = len(tools_used & complex_tools)
        tool_factor = min(complex_count / 3, 1.0)

        return (step_factor + tool_factor) / 2

    def _decide_strategy(
        self,
        dataset: DatasetAnalysis,
        workflow: WorkflowAnalysis,
        user: UserAnalysis,
        estimated_runtime: int
    ) -> ExecutionStrategy:
        """Apply decision rules to determine strategy."""

        # Accumulate evidence for pilot vs direct
        pilot_score = 0.0
        direct_score = 0.0
        reasons = []

        # === Rule 1: Dataset size ===
        if dataset.sample_count >= self.LARGE_DATASET_THRESHOLD:
            pilot_score += 0.3
            reasons.append(f"Large dataset ({dataset.sample_count} samples)")
        elif dataset.sample_count < 10:
            direct_score += 0.2
            reasons.append("Small dataset")

        # === Rule 2: New upload ===
        if dataset.is_new_upload:
            pilot_score += 0.15
            reasons.append("New dataset upload")

        # === Rule 3: Workflow complexity ===
        if workflow.step_count >= self.COMPLEX_WORKFLOW_THRESHOLD:
            pilot_score += 0.2
            reasons.append(f"Complex workflow ({workflow.step_count} steps)")

        # === Rule 4: Historical success rate ===
        if workflow.historical_success_rate < (1 - self.HIGH_FAILURE_RATE):
            pilot_score += 0.25
            reasons.append(f"Workflow has {int((1-workflow.historical_success_rate)*100)}% failure rate")

        # === Rule 5: User experience ===
        if user.total_workflows_run < self.NOVICE_WORKFLOW_COUNT:
            pilot_score += 0.15
            reasons.append("New user")
        elif user.total_workflows_run > 20:
            direct_score += 0.1
            reasons.append("Experienced user")

        # === Rule 6: User has run before ===
        if workflow.user_has_run_before:
            direct_score += 0.2
            reasons.append("User familiar with this workflow")

        # === Rule 7: User preference ===
        if user.pilot_preference is not None:
            if user.pilot_preference:
                pilot_score += 0.3
                reasons.append("User prefers pilot runs")
            else:
                direct_score += 0.3
                reasons.append("User prefers direct runs")

        # === Rule 8: Estimated runtime ===
        if estimated_runtime < self.MEDIUM_RUNTIME_THRESHOLD:
            direct_score += 0.2
            reasons.append(f"Quick run (~{estimated_runtime//60}min)")

        # === Determine execution mode ===
        total = pilot_score + direct_score
        if total > 0:
            pilot_confidence = pilot_score / total
        else:
            pilot_confidence = 0.5

        if pilot_confidence > 0.6:
            execution_mode = ExecutionMode.PILOT_FIRST
            confidence = pilot_confidence
        elif pilot_confidence < 0.4:
            execution_mode = ExecutionMode.DIRECT_RUN
            confidence = 1 - pilot_confidence
        else:
            execution_mode = ExecutionMode.ASK_USER
            confidence = 0.5

        # === Determine run mode ===
        if estimated_runtime > self.LONG_RUNTIME_THRESHOLD:
            run_mode = RunMode.BACKGROUND
        elif estimated_runtime > self.MEDIUM_RUNTIME_THRESHOLD:
            run_mode = RunMode.FOREGROUND  # Show progress
        else:
            run_mode = RunMode.FOREGROUND

        # If pilot, always background
        if execution_mode == ExecutionMode.PILOT_FIRST:
            run_mode = RunMode.BACKGROUND

        # Pilot configuration
        pilot_config = None
        if execution_mode == ExecutionMode.PILOT_FIRST:
            pilot_fraction = min(0.1, 50 / dataset.sample_count) if dataset.sample_count > 50 else 0.2
            pilot_config = {
                'pilot_fraction': pilot_fraction,
                'sampling_strategy': 'stratified',
                'min_pilot_samples': 3,
                'max_pilot_samples': 50
            }

        return ExecutionStrategy(
            execution_mode=execution_mode,
            run_mode=run_mode,
            confidence=confidence,
            reasoning="; ".join(reasons),
            pilot_config=pilot_config,
            estimated_runtime_seconds=estimated_runtime
        )

    def _generate_presentation(
        self,
        strategy: ExecutionStrategy,
        dataset: DatasetAnalysis,
        workflow: WorkflowAnalysis,
        user: UserAnalysis
    ) -> ExecutionStrategy:
        """Generate user-facing message and options."""

        runtime_display = self._format_runtime(strategy.estimated_runtime_seconds)

        if strategy.execution_mode == ExecutionMode.PILOT_FIRST:
            pilot_samples = int(dataset.sample_count * strategy.pilot_config['pilot_fraction'])
            pilot_time = self._format_runtime(strategy.estimated_runtime_seconds // 10)

            strategy.recommendation_message = f"""📊 **Recommendation**: Run a pilot test first

Your dataset has **{dataset.sample_count} samples**. I recommend testing on **{pilot_samples} samples** first to:
- Verify parameters work correctly
- Estimate full run time ({runtime_display})
- Catch any issues early

The pilot will take ~{pilot_time} and run in the background."""

            strategy.options = [
                {
                    'id': 'pilot',
                    'label': f'🧪 Start Pilot ({pilot_time})',
                    'description': f'Test on {pilot_samples} samples first',
                    'recommended': True
                },
                {
                    'id': 'full',
                    'label': f'▶️ Run Full ({runtime_display})',
                    'description': 'Skip pilot, run all samples',
                    'recommended': False
                },
                {
                    'id': 'chat',
                    'label': '💬 Ask Questions',
                    'description': 'Learn more before deciding',
                    'recommended': False
                }
            ]

        elif strategy.execution_mode == ExecutionMode.DIRECT_RUN:
            if strategy.run_mode == RunMode.BACKGROUND:
                strategy.recommendation_message = f"""▶️ **Ready to run** ({runtime_display} estimated)

This analysis will run in the **background**. You can:
- Continue chatting while it runs
- Start other projects
- I'll notify you when complete"""

                strategy.options = [
                    {
                        'id': 'background',
                        'label': f'🚀 Start Analysis',
                        'description': f'Runs in background ({runtime_display})',
                        'recommended': True
                    },
                    {
                        'id': 'pilot',
                        'label': '🧪 Run Pilot First',
                        'description': 'Test on subset before full run',
                        'recommended': False
                    }
                ]
            else:
                strategy.recommendation_message = f"""▶️ **Ready to run** (~{runtime_display})

This is a quick analysis. I'll show you progress as it runs."""

                strategy.options = [
                    {
                        'id': 'run',
                        'label': f'▶️ Start ({runtime_display})',
                        'description': 'Run now with live progress',
                        'recommended': True
                    }
                ]

        else:  # ASK_USER
            strategy.recommendation_message = f"""🤔 **How would you like to proceed?**

Dataset: {dataset.sample_count} samples
Estimated time: {runtime_display}

I'm not sure of the best approach. What would you prefer?"""

            strategy.options = [
                {
                    'id': 'pilot',
                    'label': '🧪 Pilot Test First',
                    'description': 'Test on 10% of samples',
                    'recommended': False
                },
                {
                    'id': 'full_bg',
                    'label': '🚀 Full Run (Background)',
                    'description': f'Run all samples, continue chatting',
                    'recommended': False
                },
                {
                    'id': 'full_fg',
                    'label': '▶️ Full Run (Wait)',
                    'description': 'Run all samples, wait for completion',
                    'recommended': False
                }
            ]

        return strategy

    def _format_runtime(self, seconds: int) -> str:
        """Format runtime as human-readable string."""
        if seconds < 60:
            return f"{seconds}s"
        elif seconds < 3600:
            return f"{seconds // 60}m"
        else:
            hours = seconds // 3600
            mins = (seconds % 3600) // 60
            return f"{hours}h {mins}m"
```

---

## Part 11: Background Task Manager

### 11.1 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      BACKGROUND TASK MANAGER                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                    TASK REGISTRY (Redis/DB)                           │ │
│   │                                                                        │ │
│   │   user_id:task_123:                                                   │ │
│   │   {                                                                    │ │
│   │     "task_type": "workflow",                                          │ │
│   │     "workflow_id": "abc123",                                          │ │
│   │     "invocation_id": "inv456",                                        │ │
│   │     "chat_session_id": "chat789",                                     │ │
│   │     "status": "running",                                              │ │
│   │     "progress": 45,                                                   │ │
│   │     "started_at": "2024-01-15T10:30:00Z",                             │ │
│   │     "estimated_completion": "2024-01-15T11:15:00Z",                   │ │
│   │     "notification_channels": ["chat", "email"]                        │ │
│   │   }                                                                    │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                    POLLING SERVICE                                     │ │
│   │                                                                        │ │
│   │   • Monitors active tasks across all users                            │ │
│   │   • Uses existing GalaxyStatePoller for workflow status               │ │
│   │   • Updates task registry on state changes                            │ │
│   │   • Triggers notifications on completion/failure                      │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                    NOTIFICATION DISPATCHER                             │ │
│   │                                                                        │ │
│   │   On task completion:                                                  │ │
│   │   1. Push to chat (WebSocket/SSE) if user online                      │ │
│   │   2. Send email via EmailService                                       │ │
│   │   3. Store in Galaxy notification system                              │ │
│   │   4. Update task registry                                              │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 11.2 Implementation

```python
# lib/galaxy/ai/execution/background_task_manager.py

"""
Background Task Manager

Tracks long-running tasks (workflows, pilot runs) across user sessions.
Provides notifications on completion via chat and email.
"""

import asyncio
import logging
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Any, Callable
from datetime import datetime, timedelta
from enum import Enum
import json

log = logging.getLogger(__name__)


class TaskType(Enum):
    WORKFLOW = "workflow"
    PILOT_RUN = "pilot_run"
    LITERATURE_SEARCH = "literature_search"


class TaskStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class BackgroundTask:
    """A background task being tracked."""
    task_id: str
    task_type: TaskType
    user_id: str

    # Task details
    workflow_id: Optional[str] = None
    invocation_id: Optional[str] = None
    chat_session_id: Optional[str] = None

    # Status
    status: TaskStatus = TaskStatus.PENDING
    progress: int = 0
    progress_message: str = ""

    # Timing
    created_at: datetime = field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    estimated_completion: Optional[datetime] = None

    # Results
    result_summary: Optional[Dict] = None
    error_message: Optional[str] = None

    # Notifications
    notification_channels: List[str] = field(default_factory=lambda: ["chat", "email"])
    notification_sent: bool = False

    def to_dict(self) -> Dict:
        return {
            'task_id': self.task_id,
            'task_type': self.task_type.value,
            'user_id': self.user_id,
            'workflow_id': self.workflow_id,
            'invocation_id': self.invocation_id,
            'chat_session_id': self.chat_session_id,
            'status': self.status.value,
            'progress': self.progress,
            'progress_message': self.progress_message,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'started_at': self.started_at.isoformat() if self.started_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'estimated_completion': self.estimated_completion.isoformat() if self.estimated_completion else None,
            'result_summary': self.result_summary,
            'error_message': self.error_message,
            'notification_channels': self.notification_channels,
            'notification_sent': self.notification_sent
        }


class BackgroundTaskManager:
    """
    Manages background tasks across user sessions.

    Responsibilities:
    - Track task lifecycle (create, start, update, complete)
    - Persist tasks to survive server restarts
    - Dispatch notifications on completion
    - Allow users to query their running tasks
    """

    def __init__(
        self,
        redis_client=None,
        galaxy_state_poller=None,
        notification_dispatcher=None,
        persistence_backend='memory'
    ):
        self.redis = redis_client
        self.galaxy_poller = galaxy_state_poller
        self.notification_dispatcher = notification_dispatcher

        # In-memory fallback if no Redis
        self._memory_tasks: Dict[str, BackgroundTask] = {}
        self._user_task_index: Dict[str, List[str]] = {}  # user_id -> [task_ids]

        # Callbacks for task events
        self._on_complete_callbacks: List[Callable] = []
        self._on_fail_callbacks: List[Callable] = []

        # Start background polling
        self._polling_task = None

    async def start(self):
        """Start the background polling loop."""
        if self._polling_task is None:
            self._polling_task = asyncio.create_task(self._polling_loop())
            log.info("BackgroundTaskManager started")

    async def stop(self):
        """Stop the background polling loop."""
        if self._polling_task:
            self._polling_task.cancel()
            self._polling_task = None
            log.info("BackgroundTaskManager stopped")

    # =========================================================================
    # Task Lifecycle
    # =========================================================================

    async def create_task(
        self,
        task_type: TaskType,
        user_id: str,
        workflow_id: str = None,
        chat_session_id: str = None,
        estimated_runtime_seconds: int = None,
        notification_channels: List[str] = None
    ) -> BackgroundTask:
        """Create and register a new background task."""
        import uuid
        task_id = f"task_{uuid.uuid4().hex[:12]}"

        estimated_completion = None
        if estimated_runtime_seconds:
            estimated_completion = datetime.utcnow() + timedelta(seconds=estimated_runtime_seconds)

        task = BackgroundTask(
            task_id=task_id,
            task_type=task_type,
            user_id=user_id,
            workflow_id=workflow_id,
            chat_session_id=chat_session_id,
            estimated_completion=estimated_completion,
            notification_channels=notification_channels or ["chat", "email"]
        )

        await self._save_task(task)
        await self._add_to_user_index(user_id, task_id)

        log.info(f"Created background task {task_id} for user {user_id}")
        return task

    async def start_task(
        self,
        task_id: str,
        invocation_id: str = None
    ) -> BackgroundTask:
        """Mark task as started."""
        task = await self._get_task(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        task.status = TaskStatus.RUNNING
        task.started_at = datetime.utcnow()
        if invocation_id:
            task.invocation_id = invocation_id

        await self._save_task(task)

        # Start polling Galaxy for workflow status
        if task.workflow_id and task.invocation_id and self.galaxy_poller:
            self.galaxy_poller.startPolling(task.invocation_id, task.workflow_id)

        log.info(f"Started task {task_id}, invocation={invocation_id}")
        return task

    async def update_progress(
        self,
        task_id: str,
        progress: int,
        message: str = None
    ):
        """Update task progress."""
        task = await self._get_task(task_id)
        if not task:
            return

        task.progress = progress
        if message:
            task.progress_message = message

        await self._save_task(task)

    async def complete_task(
        self,
        task_id: str,
        result_summary: Dict = None
    ) -> BackgroundTask:
        """Mark task as completed and dispatch notifications."""
        task = await self._get_task(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        task.status = TaskStatus.COMPLETED
        task.progress = 100
        task.completed_at = datetime.utcnow()
        task.result_summary = result_summary

        await self._save_task(task)

        # Dispatch notifications
        await self._dispatch_completion_notification(task)

        # Call callbacks
        for callback in self._on_complete_callbacks:
            try:
                await callback(task)
            except Exception as e:
                log.error(f"Completion callback error: {e}")

        log.info(f"Completed task {task_id}")
        return task

    async def fail_task(
        self,
        task_id: str,
        error_message: str
    ) -> BackgroundTask:
        """Mark task as failed and dispatch notifications."""
        task = await self._get_task(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        task.status = TaskStatus.FAILED
        task.completed_at = datetime.utcnow()
        task.error_message = error_message

        await self._save_task(task)

        # Dispatch notifications
        await self._dispatch_failure_notification(task)

        # Call callbacks
        for callback in self._on_fail_callbacks:
            try:
                await callback(task)
            except Exception as e:
                log.error(f"Failure callback error: {e}")

        log.info(f"Failed task {task_id}: {error_message}")
        return task

    # =========================================================================
    # Query Methods
    # =========================================================================

    async def get_user_tasks(
        self,
        user_id: str,
        status_filter: List[TaskStatus] = None,
        limit: int = 50
    ) -> List[BackgroundTask]:
        """Get all tasks for a user."""
        task_ids = await self._get_user_task_ids(user_id)
        tasks = []

        for task_id in task_ids[:limit]:
            task = await self._get_task(task_id)
            if task:
                if status_filter is None or task.status in status_filter:
                    tasks.append(task)

        # Sort by created_at descending
        tasks.sort(key=lambda t: t.created_at, reverse=True)
        return tasks

    async def get_running_tasks(self, user_id: str) -> List[BackgroundTask]:
        """Get currently running tasks for a user."""
        return await self.get_user_tasks(
            user_id,
            status_filter=[TaskStatus.PENDING, TaskStatus.RUNNING]
        )

    async def get_task_count(self, user_id: str) -> Dict[str, int]:
        """Get task counts by status for a user."""
        tasks = await self.get_user_tasks(user_id)
        counts = {status.value: 0 for status in TaskStatus}
        for task in tasks:
            counts[task.status.value] += 1
        return counts

    # =========================================================================
    # Notification Dispatch
    # =========================================================================

    async def _dispatch_completion_notification(self, task: BackgroundTask):
        """Send notifications for completed task."""
        if task.notification_sent:
            return

        if self.notification_dispatcher:
            # Chat notification (if user online)
            if "chat" in task.notification_channels:
                await self.notification_dispatcher.notify_chat(
                    user_id=task.user_id,
                    chat_session_id=task.chat_session_id,
                    notification_type="task_complete",
                    data={
                        'task_id': task.task_id,
                        'task_type': task.task_type.value,
                        'workflow_id': task.workflow_id,
                        'message': self._format_completion_message(task),
                        'result_summary': task.result_summary
                    }
                )

            # Email notification
            if "email" in task.notification_channels:
                await self.notification_dispatcher.notify_email(
                    user_id=task.user_id,
                    subject=f"BioMate: Your {task.task_type.value} is complete",
                    template="workflow_complete",
                    data={
                        'task_id': task.task_id,
                        'workflow_id': task.workflow_id,
                        'runtime': self._calculate_runtime(task),
                        'result_summary': task.result_summary
                    }
                )

        task.notification_sent = True
        await self._save_task(task)

    async def _dispatch_failure_notification(self, task: BackgroundTask):
        """Send notifications for failed task."""
        if task.notification_sent:
            return

        if self.notification_dispatcher:
            if "chat" in task.notification_channels:
                await self.notification_dispatcher.notify_chat(
                    user_id=task.user_id,
                    chat_session_id=task.chat_session_id,
                    notification_type="task_failed",
                    data={
                        'task_id': task.task_id,
                        'task_type': task.task_type.value,
                        'error_message': task.error_message,
                        'message': f"❌ Your {task.task_type.value} encountered an error: {task.error_message}"
                    }
                )

            if "email" in task.notification_channels:
                await self.notification_dispatcher.notify_email(
                    user_id=task.user_id,
                    subject=f"BioMate: Your {task.task_type.value} encountered an error",
                    template="workflow_failed",
                    data={
                        'task_id': task.task_id,
                        'error_message': task.error_message
                    }
                )

        task.notification_sent = True
        await self._save_task(task)

    def _format_completion_message(self, task: BackgroundTask) -> str:
        """Format completion notification message."""
        runtime = self._calculate_runtime(task)

        if task.task_type == TaskType.WORKFLOW:
            return f"""✅ **Workflow Complete!**

Your analysis finished in {runtime}.
{self._format_result_summary(task.result_summary)}

[📊 View Results] [💬 Ask Questions About Results]"""

        elif task.task_type == TaskType.PILOT_RUN:
            return f"""✅ **Pilot Run Complete!**

Pilot finished in {runtime}.
{self._format_result_summary(task.result_summary)}

[📊 View Pilot Results] [🚀 Proceed to Full Run]"""

        return f"✅ Task completed in {runtime}"

    def _format_result_summary(self, summary: Dict) -> str:
        """Format result summary for display."""
        if not summary:
            return ""

        lines = []
        if 'output_count' in summary:
            lines.append(f"• {summary['output_count']} output files generated")
        if 'quality_score' in summary:
            lines.append(f"• Quality score: {summary['quality_score']:.1%}")
        if 'estimated_full_runtime' in summary:
            lines.append(f"• Estimated full run: {summary['estimated_full_runtime']}")

        return "\n".join(lines)

    def _calculate_runtime(self, task: BackgroundTask) -> str:
        """Calculate human-readable runtime."""
        if not task.started_at or not task.completed_at:
            return "unknown"

        delta = task.completed_at - task.started_at
        seconds = int(delta.total_seconds())

        if seconds < 60:
            return f"{seconds}s"
        elif seconds < 3600:
            return f"{seconds // 60}m {seconds % 60}s"
        else:
            hours = seconds // 3600
            mins = (seconds % 3600) // 60
            return f"{hours}h {mins}m"

    # =========================================================================
    # Persistence (Redis or Memory)
    # =========================================================================

    async def _save_task(self, task: BackgroundTask):
        """Save task to storage."""
        if self.redis:
            key = f"biomate:task:{task.task_id}"
            await self.redis.setex(key, 86400 * 7, json.dumps(task.to_dict()))  # 7 day TTL
        else:
            self._memory_tasks[task.task_id] = task

    async def _get_task(self, task_id: str) -> Optional[BackgroundTask]:
        """Get task from storage."""
        if self.redis:
            key = f"biomate:task:{task_id}"
            data = await self.redis.get(key)
            if data:
                return self._dict_to_task(json.loads(data))
            return None
        else:
            return self._memory_tasks.get(task_id)

    async def _add_to_user_index(self, user_id: str, task_id: str):
        """Add task to user's task list."""
        if self.redis:
            key = f"biomate:user_tasks:{user_id}"
            await self.redis.lpush(key, task_id)
            await self.redis.ltrim(key, 0, 99)  # Keep last 100
        else:
            if user_id not in self._user_task_index:
                self._user_task_index[user_id] = []
            self._user_task_index[user_id].insert(0, task_id)
            self._user_task_index[user_id] = self._user_task_index[user_id][:100]

    async def _get_user_task_ids(self, user_id: str) -> List[str]:
        """Get task IDs for a user."""
        if self.redis:
            key = f"biomate:user_tasks:{user_id}"
            return await self.redis.lrange(key, 0, -1)
        else:
            return self._user_task_index.get(user_id, [])

    def _dict_to_task(self, data: Dict) -> BackgroundTask:
        """Convert dict to BackgroundTask."""
        return BackgroundTask(
            task_id=data['task_id'],
            task_type=TaskType(data['task_type']),
            user_id=data['user_id'],
            workflow_id=data.get('workflow_id'),
            invocation_id=data.get('invocation_id'),
            chat_session_id=data.get('chat_session_id'),
            status=TaskStatus(data['status']),
            progress=data.get('progress', 0),
            progress_message=data.get('progress_message', ''),
            created_at=datetime.fromisoformat(data['created_at']) if data.get('created_at') else None,
            started_at=datetime.fromisoformat(data['started_at']) if data.get('started_at') else None,
            completed_at=datetime.fromisoformat(data['completed_at']) if data.get('completed_at') else None,
            estimated_completion=datetime.fromisoformat(data['estimated_completion']) if data.get('estimated_completion') else None,
            result_summary=data.get('result_summary'),
            error_message=data.get('error_message'),
            notification_channels=data.get('notification_channels', ['chat', 'email']),
            notification_sent=data.get('notification_sent', False)
        )

    # =========================================================================
    # Polling Loop
    # =========================================================================

    async def _polling_loop(self):
        """Background loop to check task status."""
        while True:
            try:
                await asyncio.sleep(5)  # Poll every 5 seconds

                # In a real implementation, we'd:
                # 1. Get all running tasks
                # 2. Check Galaxy status for each
                # 3. Update task status accordingly
                # 4. Dispatch notifications as needed

                # For now, rely on GalaxyStatePoller callbacks

            except asyncio.CancelledError:
                break
            except Exception as e:
                log.error(f"Polling loop error: {e}")
                await asyncio.sleep(10)
```

---

## Part 12: Notification Dispatcher

### 12.1 Implementation

```python
# lib/galaxy/ai/execution/notification_dispatcher.py

"""
Notification Dispatcher

Sends notifications via multiple channels:
- Chat (WebSocket/SSE for real-time)
- Email (via EmailService)
- Galaxy notifications (stored in DB)
"""

import logging
from typing import Dict, Optional, Any
from dataclasses import dataclass

log = logging.getLogger(__name__)


@dataclass
class NotificationContent:
    """Content for a notification."""
    title: str
    message: str
    data: Dict[str, Any]
    priority: str = "normal"  # "low", "normal", "high"


class NotificationDispatcher:
    """
    Dispatches notifications across multiple channels.

    Channels:
    - chat: Real-time push via WebSocket/SSE
    - email: Email via EmailService
    - galaxy: Galaxy's built-in notification system
    """

    def __init__(
        self,
        websocket_manager=None,
        email_service=None,
        galaxy_notification_manager=None,
        user_repository=None
    ):
        self.websocket = websocket_manager
        self.email_service = email_service
        self.galaxy_notifications = galaxy_notification_manager
        self.users = user_repository

    async def notify_chat(
        self,
        user_id: str,
        chat_session_id: str,
        notification_type: str,
        data: Dict[str, Any]
    ):
        """
        Send real-time notification to user's chat.

        If user is online (has active WebSocket), push immediately.
        Otherwise, store for delivery when they return.
        """
        if self.websocket:
            try:
                is_online = await self.websocket.is_user_connected(user_id)

                if is_online:
                    await self.websocket.send_to_user(
                        user_id=user_id,
                        event_type="notification",
                        data={
                            'type': notification_type,
                            'chat_session_id': chat_session_id,
                            **data
                        }
                    )
                    log.info(f"Chat notification sent to online user {user_id}")
                else:
                    # Store for later delivery
                    await self._store_pending_notification(
                        user_id, notification_type, data
                    )
                    log.info(f"Chat notification stored for offline user {user_id}")

            except Exception as e:
                log.error(f"Chat notification failed: {e}")

    async def notify_email(
        self,
        user_id: str,
        subject: str,
        template: str,
        data: Dict[str, Any]
    ):
        """
        Send email notification to user.

        Uses EmailService with templates for workflow events.
        """
        if not self.email_service:
            log.warning("Email service not configured, skipping email notification")
            return

        try:
            # Get user email
            user = await self._get_user(user_id)
            if not user or not user.get('email'):
                log.warning(f"No email for user {user_id}")
                return

            # Generate email content from template
            html_body, text_body = self._render_email_template(template, data)

            # Send email
            success = self.email_service.send_custom_email(
                to_email=user['email'],
                subject=subject,
                html_body=html_body,
                text_body=text_body
            )

            if success:
                log.info(f"Email notification sent to {user['email']}")
            else:
                log.error(f"Email notification failed for {user['email']}")

        except Exception as e:
            log.error(f"Email notification error: {e}")

    async def notify_galaxy(
        self,
        user_id: str,
        notification_type: str,
        content: NotificationContent
    ):
        """
        Create Galaxy system notification.

        Stored in Galaxy's notification system and visible in UI.
        """
        if not self.galaxy_notifications:
            return

        try:
            await self.galaxy_notifications.create_notification(
                user_id=user_id,
                category=notification_type,
                content={
                    'title': content.title,
                    'message': content.message,
                    **content.data
                }
            )
            log.info(f"Galaxy notification created for user {user_id}")
        except Exception as e:
            log.error(f"Galaxy notification error: {e}")

    def _render_email_template(
        self,
        template: str,
        data: Dict
    ) -> tuple[str, str]:
        """Render email template to HTML and text."""

        if template == "workflow_complete":
            return self._render_workflow_complete_email(data)
        elif template == "workflow_failed":
            return self._render_workflow_failed_email(data)
        elif template == "pilot_complete":
            return self._render_pilot_complete_email(data)
        else:
            # Generic template
            return self._render_generic_email(data)

    def _render_workflow_complete_email(self, data: Dict) -> tuple[str, str]:
        """Render workflow completion email."""
        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: linear-gradient(135deg, #10b981 0%, #059669 100%);
                          color: white; padding: 30px; text-align: center; border-radius: 5px 5px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 5px 5px; }}
                .button {{ display: inline-block; padding: 12px 30px; background: #10b981;
                          color: white; text-decoration: none; border-radius: 5px;
                          font-weight: bold; margin: 20px 0; }}
                .stats {{ display: flex; gap: 20px; margin: 20px 0; }}
                .stat {{ flex: 1; background: white; padding: 15px; border-radius: 5px; text-align: center; }}
                .stat-value {{ font-size: 24px; font-weight: bold; color: #10b981; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>✅ Your Analysis is Complete!</h1>
                </div>
                <div class="content">
                    <p>Great news! Your workflow has finished running successfully.</p>

                    <div class="stats">
                        <div class="stat">
                            <div class="stat-value">{data.get('runtime', 'N/A')}</div>
                            <div>Runtime</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">{data.get('result_summary', {}).get('output_count', 'N/A')}</div>
                            <div>Output Files</div>
                        </div>
                    </div>

                    <p>Your results are ready for review in BioMate.</p>

                    <div style="text-align: center;">
                        <a href="https://biomate.ai/chat" class="button">View Results</a>
                    </div>

                    <p>You can also ask me questions about your results - I can help you
                    interpret findings and compare with published literature.</p>

                    <p>Happy analyzing!</p>
                    <p>The BioMate Team</p>
                </div>
            </div>
        </body>
        </html>
        """

        text = f"""
Your Analysis is Complete!

Great news! Your workflow has finished running successfully.

Runtime: {data.get('runtime', 'N/A')}
Output Files: {data.get('result_summary', {}).get('output_count', 'N/A')}

Your results are ready for review in BioMate: https://biomate.ai/chat

You can also ask me questions about your results - I can help you interpret
findings and compare with published literature.

Happy analyzing!
The BioMate Team
        """

        return html, text

    def _render_workflow_failed_email(self, data: Dict) -> tuple[str, str]:
        """Render workflow failure email."""
        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: #ef4444; color: white; padding: 30px; text-align: center; border-radius: 5px 5px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 5px 5px; }}
                .button {{ display: inline-block; padding: 12px 30px; background: #667eea;
                          color: white; text-decoration: none; border-radius: 5px; }}
                .error-box {{ background: #fee2e2; border: 1px solid #ef4444; padding: 15px; border-radius: 5px; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>⚠️ Workflow Encountered an Error</h1>
                </div>
                <div class="content">
                    <p>Unfortunately, your workflow encountered an error and couldn't complete.</p>

                    <div class="error-box">
                        <strong>Error:</strong> {data.get('error_message', 'Unknown error')}
                    </div>

                    <p>Don't worry - this happens sometimes. Here are some things you can try:</p>
                    <ul>
                        <li>Check your input data format</li>
                        <li>Review the parameters</li>
                        <li>Try running a pilot test first</li>
                        <li>Ask me for help in the chat</li>
                    </ul>

                    <div style="text-align: center;">
                        <a href="https://biomate.ai/chat" class="button">Get Help</a>
                    </div>

                    <p>The BioMate Team</p>
                </div>
            </div>
        </body>
        </html>
        """

        text = f"""
Workflow Encountered an Error

Unfortunately, your workflow encountered an error and couldn't complete.

Error: {data.get('error_message', 'Unknown error')}

Don't worry - this happens sometimes. Here are some things you can try:
- Check your input data format
- Review the parameters
- Try running a pilot test first
- Ask me for help in the chat

Get help: https://biomate.ai/chat

The BioMate Team
        """

        return html, text

    def _render_pilot_complete_email(self, data: Dict) -> tuple[str, str]:
        """Render pilot completion email."""
        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: #8b5cf6; color: white; padding: 30px; text-align: center; border-radius: 5px 5px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 5px 5px; }}
                .button {{ display: inline-block; padding: 12px 30px; background: #8b5cf6;
                          color: white; text-decoration: none; border-radius: 5px; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🧪 Pilot Run Complete!</h1>
                </div>
                <div class="content">
                    <p>Your pilot test has finished. Here's what we learned:</p>

                    <ul>
                        <li>Pilot runtime: {data.get('runtime', 'N/A')}</li>
                        <li>Estimated full run: {data.get('result_summary', {}).get('estimated_full_runtime', 'N/A')}</li>
                        <li>Quality checks: All passed</li>
                    </ul>

                    <p>Ready to proceed with the full analysis?</p>

                    <div style="text-align: center;">
                        <a href="https://biomate.ai/chat" class="button">Review & Start Full Run</a>
                    </div>

                    <p>The BioMate Team</p>
                </div>
            </div>
        </body>
        </html>
        """

        text = f"""
Pilot Run Complete!

Your pilot test has finished. Here's what we learned:

- Pilot runtime: {data.get('runtime', 'N/A')}
- Estimated full run: {data.get('result_summary', {}).get('estimated_full_runtime', 'N/A')}
- Quality checks: All passed

Ready to proceed with the full analysis?
Review & Start Full Run: https://biomate.ai/chat

The BioMate Team
        """

        return html, text

    def _render_generic_email(self, data: Dict) -> tuple[str, str]:
        """Render generic notification email."""
        message = data.get('message', 'You have a notification from BioMate.')

        html = f"""
        <html>
        <body>
            <h1>BioMate Notification</h1>
            <p>{message}</p>
            <p><a href="https://biomate.ai/chat">Open BioMate</a></p>
        </body>
        </html>
        """

        text = f"BioMate Notification\n\n{message}\n\nOpen BioMate: https://biomate.ai/chat"

        return html, text

    async def _get_user(self, user_id: str) -> Optional[Dict]:
        """Get user details."""
        if self.users:
            return await self.users.get_user(user_id)
        return None

    async def _store_pending_notification(
        self,
        user_id: str,
        notification_type: str,
        data: Dict
    ):
        """Store notification for later delivery."""
        # This would store in Redis/DB for delivery when user comes online
        pass
```

---

## Part 13: Multi-Chat/Project Support

### 13.1 User Experience Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MULTI-CHAT EXPERIENCE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    CHAT SIDEBAR                                      │   │
│   │                                                                      │   │
│   │   🔔 1 task running                                                 │   │
│   │   ─────────────────────                                              │   │
│   │                                                                      │   │
│   │   + New Chat                                                         │   │
│   │                                                                      │   │
│   │   📁 Project: BRCA1 Analysis                                        │   │
│   │      └─ 💬 RNA-seq workflow (🔄 running 45%)                        │   │
│   │      └─ 💬 DEG interpretation                                       │   │
│   │                                                                      │   │
│   │   📁 Project: Drug Discovery                                        │   │
│   │      └─ 💬 Docking setup                                            │   │
│   │      └─ 💬 ADMET predictions                                        │   │
│   │                                                                      │   │
│   │   📁 Recent Chats                                                   │   │
│   │      └─ 💬 How to use STAR aligner                                  │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   When task completes, notification appears in sidebar AND active chat:     │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │   🔔 ✅ RNA-seq workflow complete!                    [View Results] │   │
│   │      Runtime: 2h 15m | 12 output files                              │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 13.2 Frontend Implementation Outline

```typescript
// frontend/client/src/hooks/useBackgroundTasks.ts

import { useState, useEffect, useCallback } from 'react';

interface BackgroundTask {
  task_id: string;
  task_type: 'workflow' | 'pilot_run';
  status: 'pending' | 'running' | 'completed' | 'failed';
  progress: number;
  workflow_id?: string;
  chat_session_id?: string;
  estimated_completion?: string;
  result_summary?: Record<string, any>;
  error_message?: string;
}

interface UseBackgroundTasksOptions {
  pollInterval?: number;
  onTaskComplete?: (task: BackgroundTask) => void;
  onTaskFailed?: (task: BackgroundTask) => void;
}

export function useBackgroundTasks(options: UseBackgroundTasksOptions = {}) {
  const { pollInterval = 5000, onTaskComplete, onTaskFailed } = options;

  const [tasks, setTasks] = useState<BackgroundTask[]>([]);
  const [runningCount, setRunningCount] = useState(0);

  // Subscribe to real-time updates via WebSocket/SSE
  useEffect(() => {
    const eventSource = new EventSource('/api/tasks/stream');

    eventSource.addEventListener('task_update', (event) => {
      const update = JSON.parse(event.data);
      setTasks(prev => {
        const index = prev.findIndex(t => t.task_id === update.task_id);
        if (index >= 0) {
          const newTasks = [...prev];
          newTasks[index] = { ...newTasks[index], ...update };
          return newTasks;
        }
        return [...prev, update];
      });

      // Trigger callbacks
      if (update.status === 'completed' && onTaskComplete) {
        onTaskComplete(update);
      }
      if (update.status === 'failed' && onTaskFailed) {
        onTaskFailed(update);
      }
    });

    return () => eventSource.close();
  }, [onTaskComplete, onTaskFailed]);

  // Calculate running count
  useEffect(() => {
    setRunningCount(tasks.filter(t =>
      t.status === 'pending' || t.status === 'running'
    ).length);
  }, [tasks]);

  // Fetch initial tasks
  useEffect(() => {
    fetch('/api/tasks/running')
      .then(res => res.json())
      .then(data => setTasks(data.tasks));
  }, []);

  return {
    tasks,
    runningCount,
    runningTasks: tasks.filter(t => t.status === 'running'),
    completedTasks: tasks.filter(t => t.status === 'completed')
  };
}
```

```typescript
// frontend/client/src/components/task-notification-banner.tsx

import { useBackgroundTasks } from '@/hooks/useBackgroundTasks';
import { Bell, CheckCircle, AlertCircle, Loader2 } from 'lucide-react';

export function TaskNotificationBanner() {
  const { runningCount, tasks } = useBackgroundTasks({
    onTaskComplete: (task) => {
      // Show toast notification
      toast({
        title: "Task Complete!",
        description: `Your ${task.task_type} has finished.`,
        action: <Button size="sm">View Results</Button>
      });
    },
    onTaskFailed: (task) => {
      toast({
        title: "Task Failed",
        description: task.error_message,
        variant: "destructive"
      });
    }
  });

  if (runningCount === 0) return null;

  return (
    <div className="fixed top-4 right-4 z-50">
      <Card className="w-72 shadow-lg">
        <CardHeader className="py-2 px-3">
          <div className="flex items-center gap-2">
            <Bell className="h-4 w-4" />
            <span className="text-sm font-medium">
              {runningCount} task{runningCount > 1 ? 's' : ''} running
            </span>
          </div>
        </CardHeader>
        <CardContent className="py-2 px-3 space-y-2">
          {tasks.filter(t => t.status === 'running').slice(0, 3).map(task => (
            <div key={task.task_id} className="flex items-center gap-2">
              <Loader2 className="h-3 w-3 animate-spin text-blue-500" />
              <span className="text-xs truncate flex-1">
                {task.task_type === 'workflow' ? 'Workflow' : 'Pilot'}
              </span>
              <span className="text-xs text-muted-foreground">
                {task.progress}%
              </span>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
```

---

## Part 14: Test Harness (Pilot Run) Integration Points

### 14.1 When Test Harness is Triggered

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TEST HARNESS DECISION FLOW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   User submits workflow request                                             │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  STEP 1: AgentOrchestrator generates workflow                        │   │
│   │          (DomainRouter → Specialists → Assembler)                    │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  STEP 2: ExecutionStrategyAdvisor.analyze_and_recommend()            │   │
│   │                                                                      │   │
│   │  ════════════════════════════════════════════════════════════════   │   │
│   │  TEST HARNESS TRIGGERS (any of these → suggest pilot):              │   │
│   │  ════════════════════════════════════════════════════════════════   │   │
│   │                                                                      │   │
│   │  ┌─────────────────────────────────────────────────────────────┐    │   │
│   │  │ □ Dataset > 100 samples                        (+0.30 pilot) │    │   │
│   │  │ □ New dataset upload (first time)              (+0.15 pilot) │    │   │
│   │  │ □ Complex workflow (> 5 steps)                 (+0.20 pilot) │    │   │
│   │  │ □ Workflow has high failure rate (>20%)        (+0.25 pilot) │    │   │
│   │  │ □ New user (< 5 workflows run)                 (+0.15 pilot) │    │   │
│   │  │ □ User has never run this workflow before      (+0.15 pilot) │    │   │
│   │  │ □ User preference is "always pilot"            (+0.30 pilot) │    │   │
│   │  └─────────────────────────────────────────────────────────────┘    │   │
│   │                                                                      │   │
│   │  If pilot_score > 0.6 → RECOMMEND TEST HARNESS                      │   │
│   │  If pilot_score 0.4-0.6 → ASK USER                                  │   │
│   │  If pilot_score < 0.4 → DIRECT RUN                                  │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  STEP 3: Show recommendation to user in chat                         │   │
│   │                                                                      │   │
│   │  "📊 Recommendation: Run a pilot test first                         │   │
│   │   Your dataset has 500 samples. I recommend testing on 50 first..." │   │
│   │                                                                      │   │
│   │   [🧪 Start Pilot] [▶️ Run Full] [💬 Ask Questions]                 │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                      │
│       ▼                                                                      │
│   User clicks "Start Pilot"                                                 │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  STEP 4: BackgroundTaskManager.create_task(PILOT_RUN)                │   │
│   │          → ProgressiveTuning.start_pilot_run()                       │   │
│   │          → User can continue chatting                                │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 14.2 Where Test Harness Executes

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TEST HARNESS EXECUTION LOCATION                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   EXISTING COMPONENT: lib/galaxy/ai/progressive_tuning.py                   │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   class ProgressiveTuningService:                                           │
│       """                                                                    │
│       Handles pilot runs and parameter optimization.                        │
│       ALREADY EXISTS - we integrate with it, not replace it.                │
│       """                                                                    │
│                                                                              │
│       def start_pilot_run(                                                  │
│           self,                                                             │
│           workflow_id: str,                                                 │
│           total_samples: int,                                               │
│           config: TuningConfig                                              │
│       ) -> PilotRunResult:                                                  │
│           """                                                               │
│           1. Sample subset (stratified or random)                           │
│           2. Execute workflow on subset                                     │
│           3. Collect metrics (runtime, memory, quality)                     │
│           4. Return results for user review                                 │
│           """                                                               │
│                                                                              │
│       def estimate_full_run(                                                │
│           self,                                                             │
│           pilot_result: PilotRunResult,                                     │
│           total_samples: int                                                │
│       ) -> FullRunEstimate:                                                 │
│           """                                                               │
│           Extrapolate from pilot to estimate full run.                      │
│           """                                                               │
│                                                                              │
│       def get_parameter_recommendations(                                    │
│           self,                                                             │
│           pilot_result: PilotRunResult                                      │
│       ) -> List[ParameterRecommendation]:                                   │
│           """                                                               │
│           Suggest parameter adjustments based on pilot.                     │
│           """                                                               │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   NEW INTEGRATION POINT:                                                    │
│                                                                              │
│   BackgroundTaskManager                                                     │
│       │                                                                      │
│       ├── create_task(PILOT_RUN) ─────────────────────────────────────────► │
│       │                          │                                          │
│       │                          ▼                                          │
│       │              ProgressiveTuningService.start_pilot_run()             │
│       │                          │                                          │
│       │                          ▼                                          │
│       │              Galaxy workflow invocation (subset of data)            │
│       │                          │                                          │
│       │                          ▼                                          │
│       ├── update_progress(task_id, progress) ◄────────────────────────────  │
│       │                          │                                          │
│       │                          ▼                                          │
│       │              Pilot completes                                        │
│       │                          │                                          │
│       │                          ▼                                          │
│       ├── complete_task(task_id, result_summary) ◄────────────────────────  │
│       │       │                                                             │
│       │       ├── NotificationDispatcher.notify_chat()                      │
│       │       └── NotificationDispatcher.notify_email()                     │
│       │                                                                      │
│       └────────────────────────────────────────────────────────────────────► │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 14.3 Test Harness Configuration

```python
# Pilot run configuration (from ExecutionStrategyAdvisor)

@dataclass
class PilotConfig:
    """Configuration for test harness run."""

    # Sampling
    pilot_fraction: float = 0.1          # 10% of samples
    min_pilot_samples: int = 3           # At least 3 samples
    max_pilot_samples: int = 50          # No more than 50 samples
    sampling_strategy: str = "stratified" # or "random", "first_n"
    strata_column: Optional[str] = None  # For stratified sampling

    # Execution
    timeout_minutes: int = 30            # Max pilot duration
    notify_on_complete: bool = True      # Send notifications

    # Quality checks
    check_output_validity: bool = True   # Validate outputs
    check_resource_usage: bool = True    # Track memory/CPU

    # After pilot
    auto_suggest_params: bool = True     # Suggest parameter changes
    estimate_full_run: bool = True       # Extrapolate to full dataset
```

### 14.4 Test Harness Decision Examples

| Scenario | Advisor Decision | Reason |
|----------|------------------|--------|
| 500 samples, new workflow, new user | **PILOT FIRST** | High risk: large data + unknown workflow + inexperienced |
| 10 samples, user ran same workflow before | **DIRECT RUN** | Low risk: small data + familiar workflow |
| 200 samples, complex 8-step workflow | **PILOT FIRST** | Complex workflow benefits from validation |
| 50 samples, simple 2-step workflow | **DIRECT RUN** | Simple workflow, reasonable size |
| Any size, workflow has 30% failure rate | **PILOT FIRST** | High failure rate warrants testing |
| User preference set to "always pilot" | **PILOT FIRST** | Respect user preference |
| 100 samples, estimated runtime < 2 min | **DIRECT RUN** | Quick run, not worth pilot overhead |

### 14.5 Complete Pilot → Full Run Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  INTEGRATED PILOT → FULL RUN FLOW                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   User: "Analyze my 500-sample RNA-seq"                                     │
│                                                                              │
│   1. ExecutionStrategyAdvisor.analyze()                                     │
│      → Large dataset + new workflow → PILOT_FIRST + BACKGROUND              │
│                                                                              │
│   2. Show recommendation in chat:                                           │
│      "I recommend a pilot test on 50 samples first..."                      │
│      [🧪 Start Pilot] [▶️ Run Full] [💬 Ask Questions]                     │
│                                                                              │
│   3. User clicks "Start Pilot"                                              │
│      → BackgroundTaskManager.create_task(PILOT_RUN)                         │
│      → Progressive Tuning service runs pilot                                │
│      → User continues chatting ("What's the best p-value threshold?")       │
│                                                                              │
│   4. Pilot completes (4 min later)                                          │
│      → BackgroundTaskManager.complete_task()                                │
│      → NotificationDispatcher.notify_chat() - Banner appears                │
│      → NotificationDispatcher.notify_email() - Email sent                   │
│                                                                              │
│   5. Chat shows inline notification:                                        │
│      "✅ Pilot complete! Runtime: 4m | Full run estimate: 2h 15m            │
│       Recommendation: Increase --min-counts to 10                           │
│       [📊 View Results] [🚀 Start Full Run] [🔄 Adjust Settings]"          │
│                                                                              │
│   6. User clicks "Start Full Run"                                           │
│      → BackgroundTaskManager.create_task(WORKFLOW)                          │
│      → Full workflow starts in background                                   │
│      → User continues chatting or starts new project                        │
│                                                                              │
│   7. Full run completes (2h 15m later)                                      │
│      → Notification in chat + email                                         │
│      → Results ready for interpretation                                     │
│                                                                              │
│   8. User asks: "Compare my DEGs with BRCA1 literature"                     │
│      → ResearchAgent compares results with PubMed papers                    │
│      → Returns comparison with citations                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 15: Files to Create (Part B)

| File | Purpose |
|------|---------|
| `lib/galaxy/ai/execution/__init__.py` | Execution package |
| `lib/galaxy/ai/execution/strategy_advisor.py` | ExecutionStrategyAdvisor |
| `lib/galaxy/ai/execution/background_task_manager.py` | BackgroundTaskManager |
| `lib/galaxy/ai/execution/notification_dispatcher.py` | NotificationDispatcher |
| `frontend/client/src/hooks/useBackgroundTasks.ts` | Background task React hook |
| `frontend/client/src/components/task-notification-banner.tsx` | Task notification UI |
| `frontend/client/src/components/execution-strategy-dialog.tsx` | Strategy recommendation UI |

## Part 16: Files to Modify (Part B)

| File | Changes |
|------|---------|
| `lib/galaxy/ai/ai_assistant.py` | Add strategy advisor, task manager integration |
| `lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Add task management endpoints |
| `lib/galaxy/webapps/galaxy/services/email_service.py` | Add workflow email templates |
| `frontend/client/src/components/workflow-artifact.tsx` | Add strategy recommendation display |
| `frontend/client/src/components/chat-interface.tsx` | Add background task indicators |
| `frontend/server/routes.ts` | Add task streaming endpoint |

---

## Part 17: Database Schema Additions

```sql
-- Add to migrations/007_background_tasks.sql

-- Background tasks table
CREATE TABLE background_tasks (
    task_id TEXT PRIMARY KEY,
    task_type TEXT NOT NULL,  -- 'workflow', 'pilot_run', 'literature_search'
    user_id TEXT NOT NULL,

    -- References
    workflow_id TEXT,
    invocation_id TEXT,
    chat_session_id TEXT,

    -- Status
    status TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'running', 'completed', 'failed'
    progress INTEGER DEFAULT 0,
    progress_message TEXT,

    -- Timing
    created_at TEXT DEFAULT (datetime('now')),
    started_at TEXT,
    completed_at TEXT,
    estimated_completion TEXT,

    -- Results
    result_summary TEXT,  -- JSON
    error_message TEXT,

    -- Notifications
    notification_channels TEXT DEFAULT '["chat","email"]',  -- JSON array
    notification_sent INTEGER DEFAULT 0,

    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_tasks_user ON background_tasks(user_id);
CREATE INDEX idx_tasks_status ON background_tasks(status);
CREATE INDEX idx_tasks_created ON background_tasks(created_at);

-- Execution strategy history (for learning)
CREATE TABLE execution_strategy_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    workflow_id TEXT NOT NULL,

    -- Context at decision time
    dataset_sample_count INTEGER,
    workflow_step_count INTEGER,
    estimated_runtime_seconds INTEGER,

    -- Recommendation
    recommended_mode TEXT,  -- 'pilot_first', 'direct_run'
    recommended_run_mode TEXT,  -- 'foreground', 'background'
    confidence REAL,

    -- User choice
    user_choice TEXT,  -- What user actually chose

    -- Outcome
    task_id TEXT,
    actual_runtime_seconds INTEGER,
    success INTEGER,

    created_at TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (task_id) REFERENCES background_tasks(task_id)
);
```

---

## Part 18: Pilot Decision System - Complete Implementation

### 18.1 Database Schema for Pilot Scoring

```sql
-- Add to migrations/008_pilot_decision_support.sql

-- Track actual workflow EXECUTION outcomes (not generation)
-- This is different from workflow_generation_audit which tracks AI generation
CREATE TABLE workflow_execution_stats (
    stat_id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_id TEXT NOT NULL,          -- Galaxy workflow ID
    workflow_name TEXT,

    -- Execution counts
    total_executions INTEGER DEFAULT 0,
    successful_executions INTEGER DEFAULT 0,
    failed_executions INTEGER DEFAULT 0,

    -- Calculated fields (updated on each execution)
    failure_rate REAL DEFAULT 0.0,      -- failed / total
    avg_runtime_seconds INTEGER,
    avg_memory_mb INTEGER,

    -- Metadata
    first_execution TEXT,
    last_execution TEXT,
    last_updated TEXT DEFAULT (datetime('now')),

    UNIQUE(workflow_id)
);

CREATE INDEX idx_workflow_exec_stats ON workflow_execution_stats(workflow_id);

-- Track per-user workflow history
CREATE TABLE user_workflow_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    workflow_id TEXT NOT NULL,

    -- Counts
    times_run INTEGER DEFAULT 0,
    times_succeeded INTEGER DEFAULT 0,
    times_failed INTEGER DEFAULT 0,

    -- Last interaction
    last_run TEXT,
    last_parameters TEXT,  -- JSON of last used params

    UNIQUE(user_id, workflow_id)
);

CREATE INDEX idx_user_wf_history ON user_workflow_history(user_id, workflow_id);

-- User pilot preferences (extends user_patterns)
-- Pattern type: 'pilot_preference'
-- Pattern data: {"mode": "auto|always|never", "threshold": 0.6}
-- This uses existing user_patterns table, no new table needed
```

### 18.2 ExecutionStrategyAdvisor - Complete Implementation

```python
# lib/galaxy/ai/execution/strategy_advisor.py

from dataclasses import dataclass, field
from typing import Dict, Optional, List, Any
from enum import Enum
import logging
import sqlite3
import json

log = logging.getLogger(__name__)


class ExecutionMode(Enum):
    PILOT_FIRST = "pilot_first"
    DIRECT_RUN = "direct_run"
    ASK_USER = "ask_user"


class RunMode(Enum):
    FOREGROUND = "foreground"  # Wait in chat
    BACKGROUND = "background"  # Run async, notify when done


@dataclass
class PilotDecisionFactors:
    """All factors used in pilot decision with their scores."""

    # Dataset factors
    dataset_sample_count: int = 0
    is_large_dataset: bool = False        # > 100 samples
    is_new_dataset: bool = True           # First upload

    # Workflow factors
    workflow_step_count: int = 0
    is_complex_workflow: bool = False     # > 5 steps
    workflow_failure_rate: float = 0.0    # From execution_stats
    user_ran_before: bool = False         # User has run this workflow

    # User factors
    user_total_workflows: int = 0         # Total workflows user has run
    is_new_user: bool = True              # < 5 workflows
    user_pilot_preference: str = "auto"   # "auto" | "always" | "never"

    # Runtime estimate
    estimated_runtime_seconds: int = 0
    is_quick_run: bool = False            # < 2 minutes estimated


@dataclass
class PilotScore:
    """Breakdown of pilot decision score."""
    total_score: float = 0.0
    components: Dict[str, float] = field(default_factory=dict)
    factors: PilotDecisionFactors = field(default_factory=PilotDecisionFactors)

    def add(self, name: str, score: float):
        self.components[name] = score
        self.total_score += score


@dataclass
class ExecutionRecommendation:
    """Complete recommendation from advisor."""
    execution_mode: ExecutionMode
    run_mode: RunMode
    pilot_score: PilotScore

    # For pilot mode
    recommended_pilot_size: int = 0
    pilot_config: Dict[str, Any] = field(default_factory=dict)

    # Explanation for user
    reason: str = ""
    factors_summary: List[str] = field(default_factory=list)

    # Estimates
    pilot_estimated_runtime: str = ""
    full_estimated_runtime: str = ""


class ExecutionStrategyAdvisor:
    """
    Analyzes context and recommends pilot vs direct run.

    Scoring System:
    - Score > 0.6 → PILOT_FIRST
    - Score 0.4-0.6 → ASK_USER
    - Score < 0.4 → DIRECT_RUN

    User preference can override:
    - "always" → Always pilot (unless < 10 samples)
    - "never" → Never pilot
    - "auto" → Use scoring system
    """

    DEFAULT_DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"

    # Scoring weights (total max ~1.5 if all factors apply)
    WEIGHTS = {
        'large_dataset': 0.30,       # > 100 samples
        'new_dataset': 0.15,         # First upload
        'complex_workflow': 0.20,    # > 5 steps
        'high_failure_rate': 0.25,   # > 20% failure rate
        'new_user': 0.15,            # < 5 total workflows
        'never_ran_workflow': 0.15,  # User never ran this workflow
        'user_prefers_pilot': 0.30,  # Explicit "always" preference
    }

    # Thresholds
    PILOT_THRESHOLD = 0.6
    ASK_THRESHOLD = 0.4
    LARGE_DATASET_SIZE = 100
    COMPLEX_WORKFLOW_STEPS = 5
    HIGH_FAILURE_RATE = 0.20
    NEW_USER_THRESHOLD = 5
    QUICK_RUN_SECONDS = 120  # 2 minutes

    def __init__(self, db_path: str = None):
        self.db_path = db_path or self.DEFAULT_DB_PATH

    def _get_db(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    # =========================================================================
    # MAIN API
    # =========================================================================

    def analyze_and_recommend(
        self,
        user_id: str,
        workflow_id: str,
        workflow_steps: List[Dict],
        dataset_info: Dict[str, Any],
        estimated_runtime_seconds: int = None
    ) -> ExecutionRecommendation:
        """
        Analyze context and return execution recommendation.

        Args:
            user_id: User identifier
            workflow_id: Generated workflow ID
            workflow_steps: List of workflow steps
            dataset_info: {
                'sample_count': int,
                'is_new_upload': bool,
                'file_size_mb': float (optional)
            }
            estimated_runtime_seconds: Optional pre-calculated estimate

        Returns:
            ExecutionRecommendation with mode, score breakdown, and explanation
        """
        # 1. Gather all factors
        factors = self._gather_factors(
            user_id=user_id,
            workflow_id=workflow_id,
            workflow_steps=workflow_steps,
            dataset_info=dataset_info,
            estimated_runtime_seconds=estimated_runtime_seconds
        )

        # 2. Calculate pilot score
        score = self._calculate_pilot_score(factors)

        # 3. Determine execution mode
        execution_mode = self._determine_execution_mode(score, factors)

        # 4. Determine run mode (foreground/background)
        run_mode = self._determine_run_mode(factors, execution_mode)

        # 5. Build recommendation
        recommendation = self._build_recommendation(
            execution_mode=execution_mode,
            run_mode=run_mode,
            score=score,
            factors=factors,
            dataset_info=dataset_info
        )

        log.info(f"Execution recommendation for user {user_id}: "
                f"{execution_mode.value} ({run_mode.value}), score={score.total_score:.2f}")

        return recommendation

    # =========================================================================
    # FACTOR GATHERING
    # =========================================================================

    def _gather_factors(
        self,
        user_id: str,
        workflow_id: str,
        workflow_steps: List[Dict],
        dataset_info: Dict[str, Any],
        estimated_runtime_seconds: int = None
    ) -> PilotDecisionFactors:
        """Gather all decision factors from database and inputs."""

        factors = PilotDecisionFactors()

        # Dataset factors (from input)
        sample_count = dataset_info.get('sample_count', 0)
        factors.dataset_sample_count = sample_count
        factors.is_large_dataset = sample_count > self.LARGE_DATASET_SIZE
        factors.is_new_dataset = dataset_info.get('is_new_upload', True)

        # Workflow factors (from input + database)
        factors.workflow_step_count = len(workflow_steps)
        factors.is_complex_workflow = len(workflow_steps) > self.COMPLEX_WORKFLOW_STEPS

        # Get workflow execution stats from database
        workflow_stats = self._get_workflow_stats(workflow_id)
        factors.workflow_failure_rate = workflow_stats.get('failure_rate', 0.0)

        # Get user-workflow history
        user_wf_history = self._get_user_workflow_history(user_id, workflow_id)
        factors.user_ran_before = user_wf_history.get('times_run', 0) > 0

        # User factors
        user_stats = self._get_user_stats(user_id)
        factors.user_total_workflows = user_stats.get('total_workflows', 0)
        factors.is_new_user = factors.user_total_workflows < self.NEW_USER_THRESHOLD
        factors.user_pilot_preference = self._get_user_pilot_preference(user_id)

        # Runtime estimate
        if estimated_runtime_seconds:
            factors.estimated_runtime_seconds = estimated_runtime_seconds
            factors.is_quick_run = estimated_runtime_seconds < self.QUICK_RUN_SECONDS

        return factors

    def _get_workflow_stats(self, workflow_id: str) -> Dict[str, Any]:
        """Get workflow execution statistics."""
        try:
            conn = self._get_db()
            cursor = conn.execute("""
                SELECT failure_rate, total_executions, avg_runtime_seconds
                FROM workflow_execution_stats
                WHERE workflow_id = ?
            """, (workflow_id,))
            row = cursor.fetchone()
            conn.close()

            if row:
                return dict(row)
            return {'failure_rate': 0.0, 'total_executions': 0}  # Default: no history

        except Exception as e:
            log.error(f"Error getting workflow stats: {e}")
            return {'failure_rate': 0.0, 'total_executions': 0}

    def _get_user_workflow_history(self, user_id: str, workflow_id: str) -> Dict[str, Any]:
        """Get user's history with this specific workflow."""
        try:
            conn = self._get_db()
            cursor = conn.execute("""
                SELECT times_run, times_succeeded, times_failed
                FROM user_workflow_history
                WHERE user_id = ? AND workflow_id = ?
            """, (user_id, workflow_id))
            row = cursor.fetchone()
            conn.close()

            if row:
                return dict(row)
            return {'times_run': 0}  # Default: never run

        except Exception as e:
            log.error(f"Error getting user workflow history: {e}")
            return {'times_run': 0}

    def _get_user_stats(self, user_id: str) -> Dict[str, Any]:
        """Get user's overall statistics."""
        try:
            conn = self._get_db()
            cursor = conn.execute("""
                SELECT COUNT(*) as total_workflows
                FROM user_interactions
                WHERE user_id = ? AND interaction_type = 'workflow_execution'
            """, (user_id,))
            row = cursor.fetchone()
            conn.close()

            if row:
                return dict(row)
            return {'total_workflows': 0}

        except Exception as e:
            log.error(f"Error getting user stats: {e}")
            return {'total_workflows': 0}

    def _get_user_pilot_preference(self, user_id: str) -> str:
        """Get user's pilot preference from user_patterns."""
        try:
            conn = self._get_db()
            cursor = conn.execute("""
                SELECT pattern_data
                FROM user_patterns
                WHERE user_id = ? AND pattern_type = 'pilot_preference'
                ORDER BY confidence DESC
                LIMIT 1
            """, (user_id,))
            row = cursor.fetchone()
            conn.close()

            if row and row['pattern_data']:
                data = json.loads(row['pattern_data'])
                return data.get('mode', 'auto')
            return 'auto'  # Default

        except Exception as e:
            log.error(f"Error getting pilot preference: {e}")
            return 'auto'

    # =========================================================================
    # SCORING
    # =========================================================================

    def _calculate_pilot_score(self, factors: PilotDecisionFactors) -> PilotScore:
        """Calculate pilot score from factors."""

        score = PilotScore(factors=factors)

        # Dataset factors
        if factors.is_large_dataset:
            score.add('large_dataset', self.WEIGHTS['large_dataset'])

        if factors.is_new_dataset:
            score.add('new_dataset', self.WEIGHTS['new_dataset'])

        # Workflow factors
        if factors.is_complex_workflow:
            score.add('complex_workflow', self.WEIGHTS['complex_workflow'])

        if factors.workflow_failure_rate > self.HIGH_FAILURE_RATE:
            score.add('high_failure_rate', self.WEIGHTS['high_failure_rate'])

        if not factors.user_ran_before:
            score.add('never_ran_workflow', self.WEIGHTS['never_ran_workflow'])

        # User factors
        if factors.is_new_user:
            score.add('new_user', self.WEIGHTS['new_user'])

        if factors.user_pilot_preference == 'always':
            score.add('user_prefers_pilot', self.WEIGHTS['user_prefers_pilot'])

        # Negative factors (reduce score)
        if factors.is_quick_run:
            score.add('quick_run', -0.20)  # Discount for quick runs

        if factors.user_ran_before and factors.workflow_failure_rate < 0.05:
            score.add('reliable_familiar', -0.15)  # Familiar + reliable

        return score

    def _determine_execution_mode(
        self,
        score: PilotScore,
        factors: PilotDecisionFactors
    ) -> ExecutionMode:
        """Determine execution mode from score and preferences."""

        # User preference overrides (except edge cases)
        if factors.user_pilot_preference == 'always':
            if factors.dataset_sample_count < 10:
                return ExecutionMode.DIRECT_RUN  # Too small for pilot
            return ExecutionMode.PILOT_FIRST

        if factors.user_pilot_preference == 'never':
            return ExecutionMode.DIRECT_RUN

        # Score-based decision
        if score.total_score >= self.PILOT_THRESHOLD:
            return ExecutionMode.PILOT_FIRST
        elif score.total_score >= self.ASK_THRESHOLD:
            return ExecutionMode.ASK_USER
        else:
            return ExecutionMode.DIRECT_RUN

    def _determine_run_mode(
        self,
        factors: PilotDecisionFactors,
        execution_mode: ExecutionMode
    ) -> RunMode:
        """Determine foreground vs background execution."""

        # Pilot runs are typically quick, can be foreground
        if execution_mode == ExecutionMode.PILOT_FIRST:
            return RunMode.FOREGROUND  # Pilot is quick, wait for it

        # Full runs: background if > 2 min estimated
        if factors.estimated_runtime_seconds > self.QUICK_RUN_SECONDS:
            return RunMode.BACKGROUND

        return RunMode.FOREGROUND

    # =========================================================================
    # RECOMMENDATION BUILDING
    # =========================================================================

    def _build_recommendation(
        self,
        execution_mode: ExecutionMode,
        run_mode: RunMode,
        score: PilotScore,
        factors: PilotDecisionFactors,
        dataset_info: Dict[str, Any]
    ) -> ExecutionRecommendation:
        """Build complete recommendation with explanations."""

        # Calculate pilot size
        sample_count = dataset_info.get('sample_count', 0)
        pilot_size = self._calculate_pilot_size(sample_count)

        # Build explanation
        reason, factors_summary = self._build_explanation(execution_mode, score, factors)

        # Estimate runtimes
        pilot_runtime = self._format_runtime(factors.estimated_runtime_seconds * 0.1)
        full_runtime = self._format_runtime(factors.estimated_runtime_seconds)

        return ExecutionRecommendation(
            execution_mode=execution_mode,
            run_mode=run_mode,
            pilot_score=score,
            recommended_pilot_size=pilot_size,
            pilot_config={
                'pilot_fraction': 0.1,
                'min_samples': 3,
                'max_samples': 50,
                'sampling_strategy': 'stratified'
            },
            reason=reason,
            factors_summary=factors_summary,
            pilot_estimated_runtime=pilot_runtime,
            full_estimated_runtime=full_runtime
        )

    def _calculate_pilot_size(self, total_samples: int) -> int:
        """Calculate recommended pilot size."""
        pilot = int(total_samples * 0.1)
        return max(3, min(50, pilot))  # Between 3 and 50

    def _build_explanation(
        self,
        mode: ExecutionMode,
        score: PilotScore,
        factors: PilotDecisionFactors
    ) -> tuple:
        """Build human-readable explanation."""

        factors_summary = []

        if factors.is_large_dataset:
            factors_summary.append(f"Large dataset ({factors.dataset_sample_count} samples)")

        if factors.is_new_dataset:
            factors_summary.append("New dataset upload")

        if factors.is_complex_workflow:
            factors_summary.append(f"Complex workflow ({factors.workflow_step_count} steps)")

        if factors.workflow_failure_rate > self.HIGH_FAILURE_RATE:
            factors_summary.append(f"Workflow has {factors.workflow_failure_rate:.0%} failure rate")

        if factors.is_new_user:
            factors_summary.append("New to this type of analysis")

        if not factors.user_ran_before:
            factors_summary.append("First time running this workflow")

        if mode == ExecutionMode.PILOT_FIRST:
            reason = "A pilot test is recommended to validate parameters and estimate runtime."
        elif mode == ExecutionMode.ASK_USER:
            reason = "You may benefit from a pilot test, but it's optional."
        else:
            reason = "This workflow can run directly without a pilot test."

        return reason, factors_summary

    def _format_runtime(self, seconds: int) -> str:
        """Format runtime for display."""
        if not seconds:
            return "Unknown"
        if seconds < 60:
            return f"{seconds}s"
        elif seconds < 3600:
            return f"{seconds // 60}m {seconds % 60}s"
        else:
            hours = seconds // 3600
            mins = (seconds % 3600) // 60
            return f"{hours}h {mins}m"

    # =========================================================================
    # RECORDING OUTCOMES (for learning)
    # =========================================================================

    def record_execution_outcome(
        self,
        workflow_id: str,
        user_id: str,
        success: bool,
        runtime_seconds: int,
        memory_mb: int = None
    ):
        """Record workflow execution outcome for future scoring."""
        try:
            conn = self._get_db()

            # Update workflow_execution_stats
            conn.execute("""
                INSERT INTO workflow_execution_stats (workflow_id, total_executions,
                    successful_executions, failed_executions, first_execution, last_execution)
                VALUES (?, 1, ?, ?, datetime('now'), datetime('now'))
                ON CONFLICT(workflow_id) DO UPDATE SET
                    total_executions = total_executions + 1,
                    successful_executions = successful_executions + ?,
                    failed_executions = failed_executions + ?,
                    failure_rate = CAST(failed_executions + ? AS REAL) / (total_executions + 1),
                    avg_runtime_seconds = (COALESCE(avg_runtime_seconds, 0) * total_executions + ?) / (total_executions + 1),
                    last_execution = datetime('now'),
                    last_updated = datetime('now')
            """, (
                workflow_id,
                1 if success else 0,
                0 if success else 1,
                1 if success else 0,
                0 if success else 1,
                0 if success else 1,
                runtime_seconds
            ))

            # Update user_workflow_history
            conn.execute("""
                INSERT INTO user_workflow_history (user_id, workflow_id, times_run,
                    times_succeeded, times_failed, last_run)
                VALUES (?, ?, 1, ?, ?, datetime('now'))
                ON CONFLICT(user_id, workflow_id) DO UPDATE SET
                    times_run = times_run + 1,
                    times_succeeded = times_succeeded + ?,
                    times_failed = times_failed + ?,
                    last_run = datetime('now')
            """, (
                user_id, workflow_id,
                1 if success else 0,
                0 if success else 1,
                1 if success else 0,
                0 if success else 1
            ))

            conn.commit()
            conn.close()

            log.info(f"Recorded execution outcome: workflow={workflow_id}, "
                    f"user={user_id}, success={success}")

        except Exception as e:
            log.error(f"Error recording execution outcome: {e}")

    def set_user_pilot_preference(self, user_id: str, mode: str):
        """Set user's pilot preference."""
        if mode not in ('auto', 'always', 'never'):
            raise ValueError(f"Invalid pilot mode: {mode}")

        try:
            conn = self._get_db()

            pattern_data = json.dumps({'mode': mode})

            conn.execute("""
                INSERT INTO user_patterns (user_id, pattern_type, pattern_data,
                    confidence, evidence_count, first_observed, last_observed, last_updated)
                VALUES (?, 'pilot_preference', ?, 1.0, 1,
                    datetime('now'), datetime('now'), datetime('now'))
                ON CONFLICT(user_id, pattern_type) DO UPDATE SET
                    pattern_data = ?,
                    last_updated = datetime('now')
            """, (user_id, pattern_data, pattern_data))

            conn.commit()
            conn.close()

            log.info(f"Set pilot preference for user {user_id}: {mode}")

        except Exception as e:
            log.error(f"Error setting pilot preference: {e}")
```

### 18.3 Information Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PILOT DECISION INFORMATION FLOW                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                         DATA SOURCES                                     │   │
│   │                                                                          │   │
│   │   1. USER INPUT (at runtime)                                            │   │
│   │      └── dataset_info: {sample_count, is_new_upload, file_size_mb}     │   │
│   │                                                                          │   │
│   │   2. GENERATED WORKFLOW (from AgentOrchestrator)                        │   │
│   │      └── workflow_steps: List[Dict] with step count                     │   │
│   │                                                                          │   │
│   │   3. DATABASE: workflow_execution_stats                                  │   │
│   │      └── failure_rate, avg_runtime (populated after each execution)     │   │
│   │                                                                          │   │
│   │   4. DATABASE: user_workflow_history                                     │   │
│   │      └── times_run, times_succeeded (per user + workflow)               │   │
│   │                                                                          │   │
│   │   5. DATABASE: user_interactions                                         │   │
│   │      └── total workflow count (for new user detection)                  │   │
│   │                                                                          │   │
│   │   6. DATABASE: user_patterns (pattern_type='pilot_preference')          │   │
│   │      └── mode: "auto" | "always" | "never"                              │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                           │
│                                      ▼                                           │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                   ExecutionStrategyAdvisor                               │   │
│   │                                                                          │   │
│   │   _gather_factors()  ──►  PilotDecisionFactors                          │   │
│   │         │                                                                │   │
│   │         ▼                                                                │   │
│   │   _calculate_pilot_score()  ──►  PilotScore {                           │   │
│   │         │                          total_score: 0.75,                   │   │
│   │         │                          components: {                        │   │
│   │         │                            'large_dataset': 0.30,             │   │
│   │         │                            'new_user': 0.15,                  │   │
│   │         │                            'never_ran_workflow': 0.15,        │   │
│   │         │                            'complex_workflow': 0.20,          │   │
│   │         │                            'quick_run': -0.05                 │   │
│   │         │                          }                                    │   │
│   │         │                        }                                      │   │
│   │         ▼                                                                │   │
│   │   _determine_execution_mode()  ──►  PILOT_FIRST (score >= 0.6)         │   │
│   │         │                                                                │   │
│   │         ▼                                                                │   │
│   │   _build_recommendation()  ──►  ExecutionRecommendation                 │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                           │
│                                      ▼                                           │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                         FRONTEND DISPLAY                                 │   │
│   │                                                                          │   │
│   │   ExecutionRecommendation is sent to frontend via API response          │   │
│   │   Frontend renders <ExecutionStrategyDialog> component                  │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                           │
│                                      ▼                                           │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                        USER CHOICE                                       │   │
│   │                                                                          │   │
│   │   User clicks: [Start Pilot] or [Run Full] or [Adjust Settings]        │   │
│   │         │                                                                │   │
│   │         ▼                                                                │   │
│   │   Choice sent to backend  ──►  BackgroundTaskManager                    │   │
│   │         │                                                                │   │
│   │         ▼                                                                │   │
│   │   On completion: record_execution_outcome() updates stats               │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 18.4 Frontend Components

#### 18.4.1 ExecutionStrategyDialog Component

```tsx
// frontend/client/src/components/execution-strategy-dialog.tsx

import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import {
  BeakerIcon,
  PlayIcon,
  CogIcon,
  ClockIcon,
  ExclamationTriangleIcon,
  CheckCircleIcon
} from '@heroicons/react/24/outline';

interface ExecutionRecommendation {
  execution_mode: 'pilot_first' | 'direct_run' | 'ask_user';
  run_mode: 'foreground' | 'background';
  pilot_score: {
    total_score: number;
    components: Record<string, number>;
  };
  recommended_pilot_size: number;
  reason: string;
  factors_summary: string[];
  pilot_estimated_runtime: string;
  full_estimated_runtime: string;
}

interface Props {
  recommendation: ExecutionRecommendation;
  datasetSampleCount: number;
  onStartPilot: () => void;
  onRunFull: () => void;
  onAdjustSettings: () => void;
  onSetPreference: (mode: 'auto' | 'always' | 'never') => void;
}

export function ExecutionStrategyDialog({
  recommendation,
  datasetSampleCount,
  onStartPilot,
  onRunFull,
  onAdjustSettings,
  onSetPreference
}: Props) {
  const [showDetails, setShowDetails] = useState(false);

  const isPilotRecommended = recommendation.execution_mode === 'pilot_first';
  const isAskUser = recommendation.execution_mode === 'ask_user';

  // Score visualization (0-1 scale, 0.6 threshold)
  const scorePercent = Math.min(100, recommendation.pilot_score.total_score * 100);
  const scoreColor = scorePercent >= 60 ? 'bg-amber-500' :
                     scorePercent >= 40 ? 'bg-yellow-400' : 'bg-green-500';

  return (
    <Card className="border-2 border-blue-200 bg-blue-50/50">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-lg flex items-center gap-2">
            {isPilotRecommended ? (
              <>
                <BeakerIcon className="h-5 w-5 text-amber-600" />
                Pilot Test Recommended
              </>
            ) : (
              <>
                <CheckCircleIcon className="h-5 w-5 text-green-600" />
                Ready to Run
              </>
            )}
          </CardTitle>
          <Badge variant={isPilotRecommended ? "warning" : "success"}>
            Score: {(recommendation.pilot_score.total_score * 100).toFixed(0)}%
          </Badge>
        </div>
        <CardDescription>{recommendation.reason}</CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Factors Summary */}
        {recommendation.factors_summary.length > 0 && (
          <div className="space-y-1">
            <p className="text-sm font-medium text-gray-700">Why:</p>
            <ul className="text-sm text-gray-600 space-y-1">
              {recommendation.factors_summary.map((factor, i) => (
                <li key={i} className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 bg-blue-400 rounded-full" />
                  {factor}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* Runtime Estimates */}
        <div className="flex gap-4 text-sm">
          <div className="flex items-center gap-1.5">
            <ClockIcon className="h-4 w-4 text-gray-400" />
            <span className="text-gray-600">Pilot:</span>
            <span className="font-medium">{recommendation.pilot_estimated_runtime}</span>
          </div>
          <div className="flex items-center gap-1.5">
            <ClockIcon className="h-4 w-4 text-gray-400" />
            <span className="text-gray-600">Full:</span>
            <span className="font-medium">{recommendation.full_estimated_runtime}</span>
          </div>
        </div>

        {/* Pilot Size Info */}
        {isPilotRecommended && (
          <div className="bg-white rounded-lg p-3 border">
            <p className="text-sm">
              <span className="font-medium">Recommended pilot size:</span>{' '}
              {recommendation.recommended_pilot_size} of {datasetSampleCount} samples (
              {((recommendation.recommended_pilot_size / datasetSampleCount) * 100).toFixed(0)}%)
            </p>
          </div>
        )}

        {/* Score Breakdown (expandable) */}
        <button
          onClick={() => setShowDetails(!showDetails)}
          className="text-sm text-blue-600 hover:underline"
        >
          {showDetails ? 'Hide' : 'Show'} score breakdown
        </button>

        {showDetails && (
          <div className="bg-white rounded-lg p-3 border space-y-2">
            <div className="flex items-center gap-2">
              <span className="text-sm text-gray-600">Pilot Score:</span>
              <Progress value={scorePercent} className={`h-2 flex-1 ${scoreColor}`} />
              <span className="text-sm font-medium">{scorePercent.toFixed(0)}%</span>
            </div>
            <div className="text-xs text-gray-500 space-y-1">
              {Object.entries(recommendation.pilot_score.components).map(([key, value]) => (
                <div key={key} className="flex justify-between">
                  <span>{key.replace(/_/g, ' ')}:</span>
                  <span className={value >= 0 ? 'text-amber-600' : 'text-green-600'}>
                    {value >= 0 ? '+' : ''}{(value * 100).toFixed(0)}%
                  </span>
                </div>
              ))}
            </div>
            <p className="text-xs text-gray-400 mt-2">
              Threshold: 60% = pilot recommended, 40-60% = optional, &lt;40% = direct run
            </p>
          </div>
        )}

        {/* Action Buttons */}
        <div className="flex gap-2 pt-2">
          {isPilotRecommended || isAskUser ? (
            <>
              <Button
                onClick={onStartPilot}
                className="flex-1 bg-amber-500 hover:bg-amber-600"
              >
                <BeakerIcon className="h-4 w-4 mr-2" />
                Start Pilot ({recommendation.recommended_pilot_size} samples)
              </Button>
              <Button
                onClick={onRunFull}
                variant="outline"
                className="flex-1"
              >
                <PlayIcon className="h-4 w-4 mr-2" />
                Run Full
              </Button>
            </>
          ) : (
            <>
              <Button
                onClick={onRunFull}
                className="flex-1 bg-green-600 hover:bg-green-700"
              >
                <PlayIcon className="h-4 w-4 mr-2" />
                Run Full ({datasetSampleCount} samples)
              </Button>
              <Button
                onClick={onStartPilot}
                variant="outline"
              >
                <BeakerIcon className="h-4 w-4 mr-2" />
                Pilot First
              </Button>
            </>
          )}
          <Button onClick={onAdjustSettings} variant="ghost" size="icon">
            <CogIcon className="h-5 w-5" />
          </Button>
        </div>

        {/* Preference Setting */}
        <div className="flex items-center justify-between text-xs text-gray-500 pt-2 border-t">
          <span>Default behavior:</span>
          <div className="flex gap-2">
            <button
              onClick={() => onSetPreference('always')}
              className="hover:text-blue-600"
            >
              Always pilot
            </button>
            <span>|</span>
            <button
              onClick={() => onSetPreference('auto')}
              className="hover:text-blue-600 font-medium"
            >
              Auto
            </button>
            <span>|</span>
            <button
              onClick={() => onSetPreference('never')}
              className="hover:text-blue-600"
            >
              Never pilot
            </button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
```

#### 18.4.2 API Types

```typescript
// frontend/shared/schema.ts (additions)

export interface ExecutionRecommendation {
  execution_mode: 'pilot_first' | 'direct_run' | 'ask_user';
  run_mode: 'foreground' | 'background';
  pilot_score: {
    total_score: number;
    components: Record<string, number>;
    factors: PilotDecisionFactors;
  };
  recommended_pilot_size: number;
  pilot_config: {
    pilot_fraction: number;
    min_samples: number;
    max_samples: number;
    sampling_strategy: string;
  };
  reason: string;
  factors_summary: string[];
  pilot_estimated_runtime: string;
  full_estimated_runtime: string;
}

export interface PilotDecisionFactors {
  dataset_sample_count: number;
  is_large_dataset: boolean;
  is_new_dataset: boolean;
  workflow_step_count: number;
  is_complex_workflow: boolean;
  workflow_failure_rate: number;
  user_ran_before: boolean;
  user_total_workflows: number;
  is_new_user: boolean;
  user_pilot_preference: 'auto' | 'always' | 'never';
  estimated_runtime_seconds: number;
  is_quick_run: boolean;
}
```

#### 18.4.3 API Endpoint

```python
# lib/galaxy/webapps/galaxy/api/ai_assistant.py (additions)

@router.post("/api/ai/workflow/execution-strategy")
async def get_execution_strategy(
    request: ExecutionStrategyRequest,
    user: User = DependsOnUser
) -> ExecutionRecommendation:
    """
    Get execution strategy recommendation for a workflow.

    Called after workflow generation, before execution.
    """
    advisor = ExecutionStrategyAdvisor()

    recommendation = advisor.analyze_and_recommend(
        user_id=user.id,
        workflow_id=request.workflow_id,
        workflow_steps=request.workflow_steps,
        dataset_info={
            'sample_count': request.sample_count,
            'is_new_upload': request.is_new_upload
        },
        estimated_runtime_seconds=request.estimated_runtime_seconds
    )

    return recommendation.to_dict()


@router.post("/api/ai/user/pilot-preference")
async def set_pilot_preference(
    mode: Literal['auto', 'always', 'never'],
    user: User = DependsOnUser
):
    """Set user's pilot preference."""
    advisor = ExecutionStrategyAdvisor()
    advisor.set_user_pilot_preference(user.id, mode)
    return {"status": "ok", "mode": mode}
```

### 18.5 Integration with Workflow Artifact

```tsx
// Update frontend/client/src/components/workflow-artifact.tsx

// After workflow is generated and user clicks "Run":
const handleRunWorkflow = async () => {
  // 1. Get execution strategy recommendation
  const recommendation = await fetch('/api/ai/workflow/execution-strategy', {
    method: 'POST',
    body: JSON.stringify({
      workflow_id: workflow.id,
      workflow_steps: workflow.steps,
      sample_count: datasetInfo.sampleCount,
      is_new_upload: datasetInfo.isNewUpload,
      estimated_runtime_seconds: workflow.estimatedRuntime
    })
  }).then(r => r.json());

  // 2. Show ExecutionStrategyDialog
  setShowStrategyDialog(true);
  setRecommendation(recommendation);
};

// In render:
{showStrategyDialog && recommendation && (
  <ExecutionStrategyDialog
    recommendation={recommendation}
    datasetSampleCount={datasetInfo.sampleCount}
    onStartPilot={handleStartPilot}
    onRunFull={handleRunFull}
    onAdjustSettings={() => setShowSettings(true)}
    onSetPreference={handleSetPreference}
  />
)}
```

### 18.6 Defaults Summary

| Factor | Default Value | Source |
|--------|---------------|--------|
| `workflow_failure_rate` | **0.0** | No execution history |
| `user_ran_before` | **false** | No user-workflow history |
| `is_new_user` | **true** | < 5 total workflows |
| `user_pilot_preference` | **"auto"** | No preference set |
| `is_new_dataset` | **true** | From upload metadata |
| `estimated_runtime_seconds` | **0** | Requires explicit estimate |

### 18.7 Score Examples with Defaults

| Scenario | Factors | Score | Decision |
|----------|---------|-------|----------|
| New user, 500 samples, 6 steps | large(0.30) + new_ds(0.15) + complex(0.20) + new_user(0.15) + never_ran(0.15) | **0.95** | PILOT |
| New user, 50 samples, 3 steps | new_ds(0.15) + new_user(0.15) + never_ran(0.15) | **0.45** | ASK_USER |
| Experienced, 50 samples, same workflow | (no factors) | **0.00** | DIRECT |
| Any user, workflow has 25% failure | high_fail(0.25) + ... | **0.25+** | Depends |
| User set "always pilot", 200 samples | user_prefers(0.30) + large(0.30) + ... | **0.60+** | PILOT |

---

## Decision Required (Updated)

**Please review and approve:**

### Part A: AI Scientist Integration
1. [ ] Focus on Research/Literature Agent using claude-scientific-skills
2. [ ] Three use cases: questions, result comparison, conclusions
3. [ ] Integrate with existing multi-agent framework (additive, not replacing)

### Part B: Intelligent Execution & Background Tasks
4. [ ] ExecutionStrategyAdvisor for intelligent pilot vs full run decisions
5. [ ] BackgroundTaskManager for tracking tasks across sessions
6. [ ] NotificationDispatcher for chat + email notifications
7. [ ] Multi-chat support while workflows run in background
8. [ ] Integration with existing Progressive Tuning system

### Part C: Pilot Decision System (Part 18)
9. [ ] Database schema for `workflow_execution_stats` and `user_workflow_history`
10. [ ] ExecutionStrategyAdvisor with weighted scoring system
11. [ ] Frontend `ExecutionStrategyDialog` component
12. [ ] User preference storage (`auto` / `always` / `never`)
13. [ ] Outcome recording for continuous learning

---

## Part 19: Benchmark-Informed Tool Selection (NEW - 2025-12-30)

### 19.1 Problem Statement

The Benchmark Knowledge System is integrated into AIAssistant, but the **context flow is disconnected**:

```
Current State:
┌─────────────────────────────────────────────────────────────────────────┐
│ Frontend                                                                 │
│                                                                          │
│   User types: "Align my RNA-seq data"                                   │
│                       │                                                  │
│                       ▼                                                  │
│   POST /api/ai_assistant/generate_workflow                              │
│   Body: { request_text: "Align my RNA-seq data" }   ← NO CONTEXT!       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Backend                                                                  │
│                                                                          │
│   AIAssistant.get_benchmark_informed_tool_selection(                    │
│       task_description="align RNA-seq reads",                           │
│       context=???  ← WHERE DOES THIS COME FROM?                         │
│   )                                                                      │
│                                                                          │
│   If context={'memory_limited': True} → Recommends HISAT2 (4GB RAM)     │
│   If context={'speed_priority': True} → Recommends Subread (fastest)    │
│   If context=None → Recommends STAR (best overall)                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Problem**: The `context` parameter has no source. The frontend doesn't pass constraints, and the backend can't infer them.

### 19.2 Proposed Solution: Multi-Source Context Collection

Context can come from **4 sources**, merged in priority order:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CONTEXT SOURCES (Priority Order)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   1. EXPLICIT USER INPUT (Highest Priority)                             │
│      • User says "I have limited RAM" → memory_limited=True             │
│      • User says "needs to be fast" → speed_priority=True               │
│      • Extracted by LLM from natural language                           │
│                                                                          │
│   2. USER PROFILE / PREFERENCES                                          │
│      • Stored in user_preferences table                                 │
│      • Example: { default_memory_limit: "4GB", prefer_speed: true }     │
│      • Set once, applies to all workflows                               │
│                                                                          │
│   3. DATASET CHARACTERISTICS (Auto-detected)                             │
│      • Large BAM file (>10GB) → large_data=True                         │
│      • 1000+ samples → large_sample_count=True                          │
│      • Detected from uploaded_datasets metadata                         │
│                                                                          │
│   4. BENCHMARK DEFAULTS (Lowest Priority)                                │
│      • No context → Use overall best tool from benchmarks               │
│      • STAR for alignment, DeepVariant for SNV, DESeq2 for DE           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 19.3 Information Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ FRONTEND                                                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Chat Interface                                                       ││
│  │                                                                      ││
│  │ User: "Align my RNA-seq data, I only have 8GB RAM"                  ││
│  │                                                                      ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Request Builder (NEW)                                                ││
│  │                                                                      ││
│  │ {                                                                    ││
│  │   request_text: "Align my RNA-seq data, I only have 8GB RAM",       ││
│  │   uploaded_datasets: ["dataset_123"],                               ││
│  │   user_id: "user_456",                                              ││
│  │   session_context: {                                                ││
│  │     recent_files: [...],                                            ││
│  │     chat_history_summary: "..."                                     ││
│  │   }                                                                 ││
│  │ }                                                                    ││
│  │                                                                      ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
└─────────────────────────────────┼────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ BACKEND                                                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ ContextExtractor (NEW)                                               ││
│  │                                                                      ││
│  │ Input: request_text, user_id, uploaded_datasets                     ││
│  │                                                                      ││
│  │ Step 1: LLM extracts constraints from text                          ││
│  │   "8GB RAM" → { memory_limit_gb: 8, memory_limited: True }          ││
│  │                                                                      ││
│  │ Step 2: Load user preferences                                       ││
│  │   SELECT * FROM user_preferences WHERE user_id = ?                  ││
│  │   → { default_aligner: "HISAT2", prefer_speed: False }              ││
│  │                                                                      ││
│  │ Step 3: Analyze uploaded datasets                                   ││
│  │   Dataset 123: size=2.3GB, samples=12 → { large_data: False }       ││
│  │                                                                      ││
│  │ Step 4: Merge (explicit > profile > dataset > defaults)             ││
│  │   → { memory_limited: True, large_data: False }                     ││
│  │                                                                      ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ AIAssistant.get_benchmark_informed_tool_selection()                  ││
│  │                                                                      ││
│  │ task_description="align RNA-seq reads"                              ││
│  │ context={ memory_limited: True, large_data: False }                 ││
│  │                                                                      ││
│  │ → Queries BenchmarkKnowledgeDB                                      ││
│  │ → Finds decision rule: compute=limited_memory → HISAT2              ││
│  │ → Returns: {                                                        ││
│  │     recommended_tool: "HISAT2",                                     ││
│  │     galaxy_tool_id: "hisat2",                                       ││
│  │     evidence: "Only requires 4GB RAM vs 30GB for STAR",             ││
│  │     alternatives: ["STAR", "Subread"]                               ││
│  │   }                                                                 ││
│  │                                                                      ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Workflow Generation                                                  ││
│  │                                                                      ││
│  │ Uses HISAT2 instead of STAR, includes evidence in response          ││
│  │                                                                      ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 19.4 Context Schema

```python
@dataclass
class WorkflowContext:
    """Context for benchmark-informed tool selection."""

    # Compute constraints (from user text or profile)
    memory_limited: bool = False      # <16GB available
    memory_limit_gb: Optional[int] = None
    speed_priority: bool = False      # User wants fast results
    gpu_available: bool = False       # GPU resources available

    # Data characteristics (from uploaded datasets)
    large_data: bool = False          # >10GB total data
    large_sample_count: bool = False  # >100 samples
    data_type: Optional[str] = None   # "RNA-seq", "WGS", "scRNA-seq"

    # Task requirements (from query analysis)
    requires_splice_awareness: bool = False
    requires_long_read_support: bool = False
    clinical_grade_required: bool = False

    # Source tracking
    context_sources: List[str] = field(default_factory=list)  # ["user_text", "profile", "dataset"]
```

### 19.5 ContextExtractor Implementation

```python
class ContextExtractor:
    """
    Extracts workflow context from multiple sources.

    Priority: explicit_text > user_profile > dataset_analysis > defaults
    """

    def __init__(self, llm_client, user_service, dataset_service):
        self.llm_client = llm_client
        self.user_service = user_service
        self.dataset_service = dataset_service

    async def extract_context(
        self,
        request_text: str,
        user_id: Optional[str] = None,
        uploaded_datasets: Optional[List[str]] = None
    ) -> WorkflowContext:
        """Extract context from all sources and merge."""

        context = WorkflowContext()

        # 1. Extract from natural language (highest priority)
        text_context = await self._extract_from_text(request_text)
        self._merge_context(context, text_context, source="user_text")

        # 2. Load user preferences
        if user_id:
            profile_context = await self._load_user_profile(user_id)
            self._merge_context(context, profile_context, source="profile")

        # 3. Analyze datasets
        if uploaded_datasets:
            dataset_context = await self._analyze_datasets(uploaded_datasets)
            self._merge_context(context, dataset_context, source="dataset")

        return context

    async def _extract_from_text(self, text: str) -> Dict[str, Any]:
        """Use LLM to extract constraints from natural language."""
        prompt = f"""
        Extract computational constraints from this text. Return JSON:
        {{
            "memory_limited": boolean (mentions limited RAM/memory, <16GB),
            "memory_limit_gb": number or null,
            "speed_priority": boolean (mentions fast, quick, speed),
            "gpu_available": boolean (mentions GPU, CUDA),
            "clinical_grade_required": boolean (mentions clinical, diagnostic)
        }}

        Text: "{text}"
        """
        response = await self.llm_client.generate(prompt, json_mode=True)
        return json.loads(response)

    def _merge_context(
        self,
        target: WorkflowContext,
        source: Dict[str, Any],
        source_name: str
    ):
        """Merge source context into target (doesn't overwrite existing values)."""
        for key, value in source.items():
            if value is not None and getattr(target, key, None) is None:
                setattr(target, key, value)
        target.context_sources.append(source_name)
```

### 19.6 Database Schema Additions

```sql
-- User preferences for tool selection
CREATE TABLE user_tool_preferences (
    id INTEGER PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,

    -- Compute environment
    default_memory_limit_gb INTEGER,
    gpu_available BOOLEAN DEFAULT FALSE,
    prefer_speed BOOLEAN DEFAULT FALSE,

    -- Tool preferences
    preferred_aligner TEXT,           -- "STAR", "HISAT2", "auto"
    preferred_variant_caller TEXT,    -- "DeepVariant", "GATK", "auto"
    preferred_de_method TEXT,         -- "DESeq2", "edgeR", "auto"

    -- Integration preferences
    preferred_sc_integrator TEXT,     -- "scVI", "Harmony", "auto"

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Log context decisions for learning
CREATE TABLE context_decisions (
    id INTEGER PRIMARY KEY,
    user_id TEXT,
    request_id TEXT NOT NULL,

    -- What context was extracted
    context_json TEXT,                -- Full WorkflowContext as JSON
    context_sources TEXT,             -- ["user_text", "profile", "dataset"]

    -- What recommendation was made
    task_description TEXT,
    recommended_tool TEXT,
    alternative_tools TEXT,           -- JSON array
    evidence TEXT,
    confidence REAL,

    -- Outcome (for learning)
    user_accepted BOOLEAN,            -- Did user use the recommendation?
    user_override_tool TEXT,          -- What did user choose instead?

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 19.7 Frontend Changes Required

```typescript
// frontend/client/src/components/chat-interface.tsx

// Before (current):
body: JSON.stringify({ request_text: content })

// After (proposed):
body: JSON.stringify({
  request_text: content,
  uploaded_datasets: selectedDatasets.map(d => d.id),
  user_id: currentUser?.id,
  session_context: {
    recent_datasets: recentDatasets,
    chat_history_summary: summarizeHistory(messages)
  }
})
```

```typescript
// New component: ComputePreferencesDialog
// Shown on first workflow generation or from settings

interface ComputePreferences {
  memoryLimitGb: number | 'auto';
  gpuAvailable: boolean;
  preferSpeed: boolean;
  preferredAligner: 'STAR' | 'HISAT2' | 'auto';
}

const ComputePreferencesDialog = () => {
  // One-time setup for user's compute environment
  // Stored in user_tool_preferences table
}
```

### 19.8 Integration Points

| Component | Change | Priority |
|-----------|--------|----------|
| `chat-interface.tsx` | Pass `uploaded_datasets`, `user_id` in request | High |
| `galaxy-api-proxy.ts` | Forward additional fields to backend | High |
| `ai_assistant.py` | Add `ContextExtractor` to `generate_workflow_unified()` | High |
| Database | Add `user_tool_preferences`, `context_decisions` tables | Medium |
| Frontend | Add `ComputePreferencesDialog` component | Medium |
| LTM | Store context decisions for learning | Low |

### 19.9 Implementation Order

1. **Phase 1 (Quick Win)**: Infer context from user text only
   - Add LLM extraction of constraints from `request_text`
   - No frontend changes needed
   - Works immediately for "I have limited RAM" type queries

2. **Phase 2**: Add user preferences
   - Add `user_tool_preferences` table
   - Add settings page for compute environment
   - Load preferences in context extraction

3. **Phase 3**: Dataset analysis
   - Analyze uploaded datasets for size/characteristics
   - Auto-detect large data scenarios

4. **Phase 4**: Learning loop
   - Track context decisions and outcomes
   - Learn from user overrides
   - Improve extraction accuracy

---

## Part 20: Frontend-Backend Coherence Contract

### 20.1 Problem Statement

Without explicit contracts, these issues arise:
- **Type drift**: Python `snake_case` vs TypeScript `camelCase`
- **Enum mismatches**: Backend adds new value, frontend doesn't know
- **Default differences**: Frontend assumes 0, backend assumes null
- **Validation gaps**: Frontend allows what backend rejects
- **API shape changes**: Backend changes response, frontend breaks

### 20.2 Solution: Shared Schema as Single Source of Truth

```
frontend/shared/api-contracts/        ← TypeScript types + Zod validation
        │
        │  Define once, validate everywhere
        │
        ▼
backend/lib/galaxy/ai/schemas/        ← Pydantic models (MUST mirror TypeScript)
```

### 20.3 Shared Constants File

```typescript
// frontend/shared/api-contracts/constants.ts

/**
 * IMPORTANT: These values MUST match backend/lib/galaxy/ai/schemas/constants.py
 * Any change here requires a corresponding change in the backend.
 */

export const PILOT_THRESHOLDS = {
  RECOMMEND_PILOT: 0.6,
  ASK_USER: 0.4,
  LARGE_DATASET: 100,
  COMPLEX_WORKFLOW_STEPS: 5,
  HIGH_FAILURE_RATE: 0.20,
  NEW_USER_THRESHOLD: 5,
  QUICK_RUN_SECONDS: 120,
} as const;

export const SCORE_WEIGHTS = {
  large_dataset: 0.30,
  new_dataset: 0.15,
  complex_workflow: 0.20,
  high_failure_rate: 0.25,
  new_user: 0.15,
  never_ran_workflow: 0.15,
  user_prefers_pilot: 0.30,
  quick_run: -0.20,
  reliable_familiar: -0.15,
} as const;

export const EXECUTION_MODES = ['pilot_first', 'direct_run', 'ask_user'] as const;
export const RUN_MODES = ['foreground', 'background'] as const;
export const PILOT_PREFERENCES = ['auto', 'always', 'never'] as const;
```

```python
# backend/lib/galaxy/ai/schemas/constants.py

"""
IMPORTANT: These values MUST match frontend/shared/api-contracts/constants.ts
Any change here requires a corresponding change in the frontend.
"""

class PilotThresholds:
    RECOMMEND_PILOT = 0.6
    ASK_USER = 0.4
    LARGE_DATASET = 100
    COMPLEX_WORKFLOW_STEPS = 5
    HIGH_FAILURE_RATE = 0.20
    NEW_USER_THRESHOLD = 5
    QUICK_RUN_SECONDS = 120


class ScoreWeights:
    large_dataset = 0.30
    new_dataset = 0.15
    complex_workflow = 0.20
    high_failure_rate = 0.25
    new_user = 0.15
    never_ran_workflow = 0.15
    user_prefers_pilot = 0.30
    quick_run = -0.20
    reliable_familiar = -0.15
```

### 20.4 Zod Schema (Frontend Request/Response Validation)

```typescript
// frontend/shared/api-contracts/execution-strategy.ts

import { z } from 'zod';
import { EXECUTION_MODES, RUN_MODES, PILOT_PREFERENCES } from './constants';

// ============================================================================
// REQUEST (Frontend → Backend)
// ============================================================================

export const ExecutionStrategyRequestSchema = z.object({
  workflow_id: z.string().min(1),
  workflow_steps: z.array(z.object({
    step_id: z.number(),
    tool_id: z.string(),
    tool_name: z.string().optional(),
  })),
  sample_count: z.number().int().min(1),
  is_new_upload: z.boolean().default(true),
  estimated_runtime_seconds: z.number().int().min(0).optional(),
});

export type ExecutionStrategyRequest = z.infer<typeof ExecutionStrategyRequestSchema>;

// ============================================================================
// RESPONSE (Backend → Frontend)
// ============================================================================

export const PilotDecisionFactorsSchema = z.object({
  dataset_sample_count: z.number().int(),
  is_large_dataset: z.boolean(),
  is_new_dataset: z.boolean(),
  workflow_step_count: z.number().int(),
  is_complex_workflow: z.boolean(),
  workflow_failure_rate: z.number().min(0).max(1),
  user_ran_before: z.boolean(),
  user_total_workflows: z.number().int(),
  is_new_user: z.boolean(),
  user_pilot_preference: z.enum(PILOT_PREFERENCES),
  estimated_runtime_seconds: z.number().int(),
  is_quick_run: z.boolean(),
});

export const PilotScoreSchema = z.object({
  total_score: z.number().min(0).max(2),
  components: z.record(z.string(), z.number()),
  factors: PilotDecisionFactorsSchema,
});

export const ExecutionRecommendationSchema = z.object({
  execution_mode: z.enum(EXECUTION_MODES),
  run_mode: z.enum(RUN_MODES),
  pilot_score: PilotScoreSchema,
  recommended_pilot_size: z.number().int().min(0),
  pilot_config: z.object({
    pilot_fraction: z.number(),
    min_samples: z.number().int(),
    max_samples: z.number().int(),
    sampling_strategy: z.enum(['stratified', 'random', 'first_n']),
  }),
  reason: z.string(),
  factors_summary: z.array(z.string()),
  pilot_estimated_runtime: z.string(),
  full_estimated_runtime: z.string(),
});

export type ExecutionRecommendation = z.infer<typeof ExecutionRecommendationSchema>;
```

### 20.5 Pydantic Schema (Backend - Must Mirror TypeScript)

```python
# backend/lib/galaxy/ai/schemas/execution_strategy.py

from pydantic import BaseModel, Field
from typing import Dict, List, Optional, Literal


ExecutionMode = Literal['pilot_first', 'direct_run', 'ask_user']
RunMode = Literal['foreground', 'background']
PilotPreference = Literal['auto', 'always', 'never']
SamplingStrategy = Literal['stratified', 'random', 'first_n']


class WorkflowStepInfo(BaseModel):
    step_id: int
    tool_id: str
    tool_name: Optional[str] = None


class ExecutionStrategyRequest(BaseModel):
    """MUST match ExecutionStrategyRequestSchema in TypeScript"""
    workflow_id: str = Field(..., min_length=1)
    workflow_steps: List[WorkflowStepInfo]
    sample_count: int = Field(..., ge=1)
    is_new_upload: bool = Field(default=True)
    estimated_runtime_seconds: Optional[int] = Field(default=None, ge=0)


class PilotDecisionFactors(BaseModel):
    """MUST match PilotDecisionFactorsSchema in TypeScript"""
    dataset_sample_count: int
    is_large_dataset: bool
    is_new_dataset: bool
    workflow_step_count: int
    is_complex_workflow: bool
    workflow_failure_rate: float = Field(ge=0, le=1)
    user_ran_before: bool
    user_total_workflows: int
    is_new_user: bool
    user_pilot_preference: PilotPreference
    estimated_runtime_seconds: int
    is_quick_run: bool


class PilotScore(BaseModel):
    """MUST match PilotScoreSchema in TypeScript"""
    total_score: float = Field(ge=0, le=2)
    components: Dict[str, float]
    factors: PilotDecisionFactors


class PilotConfig(BaseModel):
    pilot_fraction: float = 0.1
    min_samples: int = 3
    max_samples: int = 50
    sampling_strategy: SamplingStrategy = 'stratified'


class ExecutionRecommendation(BaseModel):
    """MUST match ExecutionRecommendationSchema in TypeScript"""
    execution_mode: ExecutionMode
    run_mode: RunMode
    pilot_score: PilotScore
    recommended_pilot_size: int = Field(ge=0)
    pilot_config: PilotConfig
    reason: str
    factors_summary: List[str]
    pilot_estimated_runtime: str
    full_estimated_runtime: str
```

### 20.6 API Client with Validation

```typescript
// frontend/client/src/lib/api/execution-strategy.ts

import {
  ExecutionStrategyRequestSchema,
  ExecutionRecommendationSchema,
  type ExecutionStrategyRequest,
  type ExecutionRecommendation,
} from '@shared/api-contracts/execution-strategy';

export async function getExecutionStrategy(
  request: ExecutionStrategyRequest
): Promise<ExecutionRecommendation> {
  // 1. Validate request BEFORE sending
  const validatedRequest = ExecutionStrategyRequestSchema.parse(request);

  // 2. Send to backend
  const response = await fetch('/api/ai/workflow/execution-strategy', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(validatedRequest),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.detail || `API error: ${response.status}`);
  }

  // 3. Validate response AFTER receiving
  const data = await response.json();
  return ExecutionRecommendationSchema.parse(data);
}
```

### 20.7 Contract Compliance Tests

```python
# backend/lib/galaxy/ai/tests/test_api_contract.py

import pytest
from ..schemas.constants import PilotThresholds, ScoreWeights

# Values MUST match frontend/shared/api-contracts/constants.ts
FRONTEND_THRESHOLDS = {
    'RECOMMEND_PILOT': 0.6,
    'ASK_USER': 0.4,
    'LARGE_DATASET': 100,
}

FRONTEND_WEIGHTS = {
    'large_dataset': 0.30,
    'new_user': 0.15,
    'complex_workflow': 0.20,
}


class TestContractCompliance:
    def test_thresholds_match_frontend(self):
        assert PilotThresholds.RECOMMEND_PILOT == FRONTEND_THRESHOLDS['RECOMMEND_PILOT']
        assert PilotThresholds.ASK_USER == FRONTEND_THRESHOLDS['ASK_USER']
        assert PilotThresholds.LARGE_DATASET == FRONTEND_THRESHOLDS['LARGE_DATASET']

    def test_weights_match_frontend(self):
        assert ScoreWeights.large_dataset == FRONTEND_WEIGHTS['large_dataset']
        assert ScoreWeights.new_user == FRONTEND_WEIGHTS['new_user']
```

```typescript
// frontend/client/src/__tests__/api-contract.test.ts

import { describe, it, expect } from 'vitest';
import { PILOT_THRESHOLDS, SCORE_WEIGHTS } from '@shared/api-contracts/constants';
import { ExecutionRecommendationSchema } from '@shared/api-contracts/execution-strategy';

describe('API Contract', () => {
  it('thresholds have expected values', () => {
    expect(PILOT_THRESHOLDS.RECOMMEND_PILOT).toBe(0.6);
    expect(PILOT_THRESHOLDS.ASK_USER).toBe(0.4);
  });

  it('validates correct response', () => {
    const validResponse = {
      execution_mode: 'pilot_first',
      run_mode: 'foreground',
      pilot_score: { total_score: 0.75, components: {}, factors: {...} },
      recommended_pilot_size: 50,
      pilot_config: { pilot_fraction: 0.1, min_samples: 3, max_samples: 50, sampling_strategy: 'stratified' },
      reason: 'Test',
      factors_summary: [],
      pilot_estimated_runtime: '5m',
      full_estimated_runtime: '1h',
    };
    expect(() => ExecutionRecommendationSchema.parse(validResponse)).not.toThrow();
  });

  it('rejects invalid execution_mode', () => {
    const invalid = { execution_mode: 'invalid_mode' };
    expect(() => ExecutionRecommendationSchema.parse(invalid)).toThrow();
  });
});
```

### 20.8 Coherence Checklist

| Item | Frontend | Backend | Must Match |
|------|----------|---------|------------|
| Threshold: Recommend Pilot | `PILOT_THRESHOLDS.RECOMMEND_PILOT` | `PilotThresholds.RECOMMEND_PILOT` | `0.6` |
| Threshold: Ask User | `PILOT_THRESHOLDS.ASK_USER` | `PilotThresholds.ASK_USER` | `0.4` |
| Weight: Large Dataset | `SCORE_WEIGHTS.large_dataset` | `ScoreWeights.large_dataset` | `0.30` |
| Enum: execution_mode | `z.enum([...])` | `Literal[...]` | `pilot_first`, `direct_run`, `ask_user` |
| Default: is_new_upload | `.default(true)` | `= True` | `true` |

### 20.9 Files for Coherence

| File | Purpose |
|------|---------|
| `frontend/shared/api-contracts/constants.ts` | Shared constants |
| `frontend/shared/api-contracts/execution-strategy.ts` | Zod schemas + types |
| `backend/lib/galaxy/ai/schemas/constants.py` | Backend constants (mirror) |
| `backend/lib/galaxy/ai/schemas/execution_strategy.py` | Pydantic models (mirror) |
| `backend/lib/galaxy/ai/tests/test_api_contract.py` | Backend contract tests |
| `frontend/client/src/__tests__/api-contract.test.ts` | Frontend contract tests |

---

## Decision Required (Updated)

**Please review and approve:**

### Part A: AI Scientist Integration
1. [ ] Focus on Research/Literature Agent using claude-scientific-skills
2. [ ] Three use cases: questions, result comparison, conclusions
3. [ ] Integrate with existing multi-agent framework (additive, not replacing)

### Part B: Intelligent Execution & Background Tasks
4. [ ] ExecutionStrategyAdvisor for intelligent pilot vs full run decisions
5. [ ] BackgroundTaskManager for tracking tasks across sessions
6. [ ] NotificationDispatcher for chat + email notifications
7. [ ] Multi-chat support while workflows run in background
8. [ ] Integration with existing Progressive Tuning system

### Part C: Pilot Decision System (Part 18)
9. [ ] Database schema for `workflow_execution_stats` and `user_workflow_history`
10. [ ] ExecutionStrategyAdvisor with weighted scoring system
11. [ ] Frontend `ExecutionStrategyDialog` component
12. [ ] User preference storage (`auto` / `always` / `never`)
13. [ ] Outcome recording for continuous learning

### Part D: Benchmark-Informed Context (Part 19)
14. [ ] ContextExtractor for multi-source context collection
15. [ ] User tool preferences database table
16. [ ] LLM extraction of constraints from natural language

### Part E: Frontend-Backend Coherence (Part 20)
17. [ ] Shared constants in `frontend/shared/api-contracts/`
18. [ ] Pydantic models in `backend/lib/galaxy/ai/schemas/`
19. [ ] Zod validation schemas for request/response
20. [ ] Contract compliance tests (both frontend and backend)

---

*Document revised by Claude Code - 2025-12-30*
