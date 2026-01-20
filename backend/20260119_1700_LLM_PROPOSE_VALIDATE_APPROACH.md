# LLM-Propose-Then-Validate Workflow Architecture

**Date:** 2026-01-19 17:00
**Status:** Design Proposal

---

## Core Concept

Instead of:
```
Search Tools → LLM picks from search results
```

Use:
```
LLM proposes workflow (using domain knowledge) → Validate against Index + Knowledge → Refine if needed
```

This leverages LLM's broad domain knowledge while ensuring:
1. Tools actually exist in Galaxy
2. Tool choices follow best practices from benchmark knowledge

---

## Current vs Proposed Flow

### Current Flow (Search-First)
```
User Intent
    │
    ▼
┌─────────────────────────────────────────┐
│ 1. Tool Search (5-stage)                │
│    - LLM query analysis                 │
│    - Vector search                      │
│    - FTS5 search                        │
│    - Returns: 30 tool candidates        │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 2. LLM Workflow Design                  │
│    - CONSTRAINED to 30 tools            │
│    - May miss optimal tools not in top  │
│    - Limited by search quality          │
└─────────────────────────────────────────┘
    │
    ▼
Output Workflow
```

**Problem:** LLM is constrained by search results. If search misses a good tool, LLM can't use it.

### Proposed Flow (Propose-Validate)
```
User Intent
    │
    ▼
┌─────────────────────────────────────────┐
│ 1. LLM Proposes Workflow                │
│    - Uses full domain knowledge         │
│    - Proposes ideal tools by name       │
│    - No constraint on tool selection    │
│    Output: {tool_name, purpose, params} │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 2. Tool Index Validation                │
│    For each proposed tool:              │
│    - Search in galaxy_ai_tools.db       │
│    - Find exact match or closest match  │
│    - Mark as: FOUND / SUBSTITUTE / MISSING│
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 3. Knowledge Validation                 │
│    For each tool:                       │
│    - Check benchmark_knowledge.db       │
│    - Verify: best for this task?        │
│    - Get: decision rules, warnings      │
│    - Add: citations, best practices     │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 4. Refinement (if needed)               │
│    If tools MISSING or SUBOPTIMAL:      │
│    - LLM revises with validation info   │
│    - "STAR not found, HISAT2 available" │
│    - "For short reads, Bowtie2 better"  │
└─────────────────────────────────────────┘
    │
    ▼
Output Validated Workflow
```

---

## Validation Components

### 1. Tool Index Validator

```python
class ToolIndexValidator:
    """Validates proposed tools against Galaxy tool index."""

    def __init__(self, db_path: str):
        self.db_path = db_path

    def validate_tool(self, proposed_tool: str) -> ToolValidation:
        """
        Check if tool exists in Galaxy.

        Returns:
            ToolValidation with:
            - status: FOUND | SUBSTITUTE | MISSING
            - galaxy_tool_id: actual tool ID if found
            - substitutes: list of similar tools if not exact match
            - confidence: match confidence score
        """
        # 1. Exact match
        exact = self._exact_match(proposed_tool)
        if exact:
            return ToolValidation(
                status="FOUND",
                galaxy_tool_id=exact.tool_id,
                confidence=1.0
            )

        # 2. Fuzzy match (similar names)
        fuzzy = self._fuzzy_match(proposed_tool)
        if fuzzy:
            return ToolValidation(
                status="SUBSTITUTE",
                galaxy_tool_id=fuzzy.tool_id,
                original_proposed=proposed_tool,
                substitutes=[fuzzy],
                confidence=fuzzy.score
            )

        # 3. Semantic match (similar purpose)
        semantic = self._semantic_match(proposed_tool)
        if semantic:
            return ToolValidation(
                status="SUBSTITUTE",
                substitutes=semantic,
                confidence=semantic[0].score
            )

        return ToolValidation(status="MISSING")
```

### 2. Knowledge Validator

```python
class KnowledgeValidator:
    """Validates tool choices against benchmark knowledge."""

    def __init__(self, benchmark_db: BenchmarkKnowledgeDB, tool_knowledge: ToolKnowledgeProvider):
        self.benchmarks = benchmark_db
        self.tool_knowledge = tool_knowledge

    def validate_tool_choice(
        self,
        tool_id: str,
        task_context: str,
        data_characteristics: Dict
    ) -> KnowledgeValidation:
        """
        Check if tool choice follows best practices.

        Returns:
            KnowledgeValidation with:
            - is_recommended: bool
            - decision_rules: applicable rules from benchmarks
            - warnings: any concerns about this choice
            - alternatives: better tools for this context
            - citations: supporting evidence
        """
        # 1. Get decision rules for this tool category
        rules = self.benchmarks.get_decision_rules(tool_id)

        # 2. Check data characteristics against rules
        applicable_rules = []
        warnings = []
        for rule in rules:
            if self._rule_applies(rule, data_characteristics):
                applicable_rules.append(rule)
                if tool_id not in rule.recommended_tools:
                    warnings.append(f"For {rule.condition}, consider: {rule.recommended_tools}")

        # 3. Get benchmark results for this tool
        results = self.benchmarks.get_tool_results(tool_id)

        # 4. Get best practices from tool knowledge
        knowledge = self.tool_knowledge.get_tool_knowledge(tool_id)

        return KnowledgeValidation(
            is_recommended=len(warnings) == 0,
            decision_rules=applicable_rules,
            warnings=warnings,
            benchmark_results=results,
            best_practices=knowledge.best_practices if knowledge else [],
            citations=knowledge.citation if knowledge else None
        )
```

### 3. Workflow Validator (Orchestrator)

```python
class WorkflowProposalValidator:
    """Validates entire proposed workflow."""

    def __init__(self):
        self.tool_validator = ToolIndexValidator()
        self.knowledge_validator = KnowledgeValidator()

    def validate_workflow(
        self,
        proposed_workflow: Dict,
        user_context: Dict
    ) -> WorkflowValidation:
        """
        Validate entire proposed workflow.

        Args:
            proposed_workflow: LLM-proposed workflow with tool names
            user_context: data characteristics, constraints

        Returns:
            WorkflowValidation with validation results for each step
        """
        step_validations = []
        all_tools_available = True
        needs_refinement = False

        for step in proposed_workflow['steps']:
            # Validate tool exists
            tool_validation = self.tool_validator.validate_tool(
                step['proposed_tool']
            )

            if tool_validation.status == "MISSING":
                all_tools_available = False
                needs_refinement = True
            elif tool_validation.status == "SUBSTITUTE":
                needs_refinement = True  # May need LLM confirmation

            # Validate against knowledge
            knowledge_validation = self.knowledge_validator.validate_tool_choice(
                tool_validation.galaxy_tool_id,
                step['purpose'],
                user_context
            )

            if knowledge_validation.warnings:
                needs_refinement = True

            step_validations.append({
                'step': step['step'],
                'proposed_tool': step['proposed_tool'],
                'tool_validation': tool_validation,
                'knowledge_validation': knowledge_validation
            })

        return WorkflowValidation(
            steps=step_validations,
            all_tools_available=all_tools_available,
            needs_refinement=needs_refinement,
            refinement_suggestions=self._generate_suggestions(step_validations)
        )
```

---

## LLM Prompts

### Initial Proposal Prompt

```
You are an expert bioinformatics workflow designer.

Based on your knowledge of bioinformatics tools and best practices,
propose a workflow for the following task:

USER REQUEST: {user_intent}

DATA CHARACTERISTICS:
{data_info}

Propose a workflow using the BEST tools you know for this task.
Use standard tool names (e.g., "STAR", "Salmon", "DESeq2").

For each step, provide:
1. Tool name (standard name)
2. Purpose (what this step does)
3. Key parameters (important settings)
4. Why this tool (brief justification)

Return as JSON:
{
  "workflow_name": "...",
  "steps": [
    {
      "step": 1,
      "tool_name": "STAR",
      "purpose": "Splice-aware alignment of RNA-seq reads",
      "key_parameters": {"outSAMtype": "BAM SortedByCoordinate"},
      "justification": "Best for splice-aware alignment, handles novel junctions"
    }
  ]
}
```

### Refinement Prompt (If Validation Fails)

```
Your proposed workflow needs refinement based on our system validation:

ORIGINAL PROPOSAL:
{original_workflow}

VALIDATION RESULTS:
{validation_results}

ISSUES:
1. Tool "STAR" is not available. Available alternatives: HISAT2, Bowtie2
2. For short reads (<50bp), benchmark shows Bowtie2 outperforms HISAT2 (see: PMID:12345)
3. "featureCounts" is available as "subread_featurecounts" in our system

Please revise your workflow:
- Replace unavailable tools with suggested alternatives
- Consider the benchmark evidence for better choices
- Use the exact tool IDs provided for available tools

Return revised JSON workflow.
```

---

## Benefits

### 1. Leverages LLM Domain Knowledge
- LLM knows about tools not in search results
- Can propose optimal pipelines from literature
- Not limited by search algorithm quality

### 2. Ensures Tool Availability
- Every tool validated against index
- Substitutions suggested for missing tools
- No hallucinated tools in final workflow

### 3. Knowledge-Grounded Decisions
- Benchmark data validates tool choices
- Decision rules catch suboptimal selections
- Citations provide evidence for choices

### 4. Transparent Refinement
- User sees what was proposed vs validated
- Clear explanation of substitutions
- Evidence for alternative recommendations

---

## Implementation Plan

### Phase 1: Core Validators
1. [ ] Implement `ToolIndexValidator`
   - Exact match
   - Fuzzy match (Levenshtein distance)
   - Semantic match (embedding similarity)

2. [ ] Implement `KnowledgeValidator`
   - Decision rule lookup
   - Benchmark result query
   - Best practice retrieval

### Phase 2: Workflow Validator
3. [ ] Implement `WorkflowProposalValidator`
   - Orchestrate step-by-step validation
   - Generate refinement suggestions
   - Track validation confidence

### Phase 3: LLM Integration
4. [ ] Create propose prompt template
5. [ ] Create refinement prompt template
6. [ ] Implement propose-validate-refine loop

### Phase 4: Integration
7. [ ] Add to `GalaxyWorkflowGenerator`
8. [ ] Add to `ai_assistant.py` routing
9. [ ] Update API responses with validation info

---

## Comparison: Old vs New

| Aspect | Search-First (Old) | Propose-Validate (New) |
|--------|-------------------|------------------------|
| LLM freedom | Constrained to 30 tools | Full domain knowledge |
| Tool availability | Guaranteed (from search) | Validated post-proposal |
| Knowledge use | Not validated | Benchmark-validated |
| Refinement | None | Iterative with evidence |
| Transparency | Black box | Validation trace |
| Speed | Faster (no validation) | Slightly slower |
| Quality | Limited by search | Higher with validation |

---

## Next Steps

1. Implement `ToolIndexValidator` with fuzzy matching
2. Implement `KnowledgeValidator` with benchmark lookup
3. Test with sample workflows
4. Integrate into workflow generation pipeline
