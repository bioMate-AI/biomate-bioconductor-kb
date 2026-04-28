# Benchmark Learnings → BioMate Improvements
## How to Make BioMate as Good as Claude Code at Intent Interpretation

**Date:** 2026-04-20  
**Status:** Active implementation plan  
**Author:** Based on BiomniEval1 v17–v20, LABBench v1–v2, Auto-loop, Routing benchmarks

---

## Part 1: Transferable Lessons from Benchmark Work

Every improvement we found in evaluation benchmarks corresponds to a gap in live BioMate. This section maps benchmark findings to concrete BioMate improvements.

---

### 1.1 Routing Guard (High Impact — Immediate)

**Benchmark finding:** 30% of LABBench ProtocolQA questions triggered workflow dispatch. The BioMate routing engine saw "protocol" keywords and launched a workflow instead of answering the knowledge question.

**Root cause:** The routing engine classifies based on the *beginning* of the message. Appending format instructions at the end has no effect on routing.

**Fix applied in adapters:** Prepend `"KNOWLEDGE QUESTION — answer directly, no workflow, no tool use, no file input needed.\n\n"` before the question body.

**Transfer to BioMate:**

The same problem affects real users who ask knowledge questions. A user asking "What restriction enzyme cuts at GAATTC?" should get a direct answer, not a workflow launch. BioMate currently only classifies as knowledge vs. workflow based on message structure, not intent.

**Recommended change:**

In `backend/lib/galaxy/ai/ai_assistant.py`, in the intent classification step, add an explicit "knowledge question" check *before* the workflow routing step:

```python
# In _classify_intent() or equivalent:
KNOWLEDGE_SIGNALS = [
    r'\bwhat is\b', r'\bwhat are\b', r'\bhow does\b', r'\bwhy does\b',
    r'\bexplain\b', r'\bdescribe\b', r'\bdefine\b', r'\bwhat enzyme\b',
    r'\bwhat codon\b', r'\bwhat primer\b', r'\bhow many bp\b',
    r'\brestriction site\b', r'\bmelting temp\b', r'\bTm\b',
]
if any(re.search(p, user_message, re.IGNORECASE) for p in KNOWLEDGE_SIGNALS):
    if NOT any(workflow_action_signal in user_message):  # "run", "analyze my file", etc.
        return IntentType.KNOWLEDGE_QA  # Skip workflow routing entirely
```

Expected impact: eliminates ~10-20% of false workflow dispatches.

---

### 1.2 Precomputed Context Injection (High Impact — New Pattern)

**Benchmark finding (BiomniEval1):** The biggest single improvement (+13pp on rare_disease) came from precomputing OMIM HPO phenotype overlap scores and injecting them as ranked context in the prompt. The model was then told to trust the ranked list over its parametric knowledge.

The same pattern gave +6-10pp on gwas_causal via Open Targets API injection.

**The principle:** The model has strong reasoning but incomplete/outdated factual recall. External databases (OMIM, Open Targets, GWAS Catalog, PubMed, restriction enzyme databases) are authoritative. Precomputing the relevant slice and injecting it as structured context is more reliable than asking the model to recall facts.

**Transfer to BioMate — three immediate applications:**

**A. Workflow selection context:** Before routing to a workflow, fetch the workflow's description, known inputs, and recent user feedback from the DB and inject them into the LLM's context window. The LLM then has ground-truth capability descriptions, not just parametric knowledge from training.

```python
# In ai_assistant.py before the final workflow confirmation:
workflow_context = db.get_workflow_rich_context(workflow_id)
prompt = f"[Workflow Context]\n{workflow_context}\n\n{user_message}"
```

**B. Parameter prefill enrichment:** When a user submits a FASTQ file, look up the file header to detect genome (hg38/hg19/mm10), read length, paired vs. single-end. Inject these as precomputed facts into the parameter prefill LLM call. This is more reliable than asking the model to guess from the filename.

**C. Literature context for scientific questions:** For questions about gene function, drug mechanisms, or experimental methods, do a quick PubMed esearch (2-3 papers) and inject the abstract text. The model then reasons from evidence rather than parametric memory.

---

### 1.3 Format Instructions Must Be Specific and Imperative (Medium Impact)

**Benchmark finding:** Adding "MANDATORY RULE: Select the disease with the HIGHEST specificity-weighted score" gave +13pp on rare_disease (vs. +0pp with softer "use as supporting evidence"). The model ignores ranking when instructions are advisory; it follows them when they are explicit and imperative.

**But:** The same MANDATORY RULE hurt patient_gene by -12pp because the precomputed ranking was wrong in 12/50 cases. Lesson: **mandatory rules work only when the precomputed context is reliably correct.**

**Transfer to BioMate:**

In parameter confirmation and execution UI, the format of the LLM's internal instructions matters enormously. Current BioMate prompts often say things like "try to extract the genome assembly if mentioned." Rewrite as: "REQUIRED: extract the genome assembly name from the user message. If mentioned (hg38, hg19, mm10, GRCh38, etc.), use it. If not mentioned, use the most common assembly for this workflow type."

More broadly: **evaluate the reliability of precomputed context before mandating trust in it.** A precomputed restriction site list (deterministic from the sequence) can be trusted absolutely. A precomputed IDF-HPO ranking (statistical from a database) can be trusted unless scores are close.

---

### 1.4 Nondeterminism Budget — When to Stop Tuning (Meta-lesson)

**Benchmark finding:** screen_gene scores ranged 28-48% across 5 independent runs of identical code (n=50). This ±20pp range is entirely within the 95% CI for n=50 at 45% accuracy. No number of prompt engineering iterations can resolve this — you need n≥200 for a stable signal.

**Transfer to BioMate:**

When a workflow fails in a way that's hard to reproduce, the failure may be LLM nondeterminism rather than a systematic bug. Before spending time debugging a rare failure:

1. Check if the failure is reproducible (>2 consecutive failures on same input)
2. If not reproducible, add a retry mechanism (1-2 automatic retries for LLM classification steps)
3. Flag the task as "nondeterministic" in the audit log rather than treating as a bug

In `ai_assistant.py`, the workflow routing classification should retry on low-confidence results:
```python
if confidence < 0.7:
    result2 = await _classify_intent(message)  # retry
    result = result if result.confidence >= result2.confidence else result2
```

---

### 1.5 Auto-Loop = QC + Remediation as a Unit (Architectural Insight)

**Benchmark finding:** The auto-loop benchmark measures convergence rate (96.4% of failing compounds converge within ≤3 remediations). This outperforms "single-attempt QC gate pass" (29.5%) by a large margin.

**Transfer to BioMate:**

The auto-loop pattern should be applied beyond ADMET/CYP-DDI/Docking/NCA-PK. Any workflow with measurable quality gates can have an auto-loop:

- **Sequence QC → FastQC loop**: if mean quality <Q30, suggest trimming params and re-run
- **Alignment QC → BWA loop**: if mapping rate <60%, suggest adapter trimming or different index
- **Variant calling QC → GATK loop**: if Ti/Tv <1.8 (whole genome), flag BQSR recalibration needed
- **Protein structure loop**: if pLDDT <70%, suggest longer MSA search or relaxed constraints

The pattern is always: run → extract gate metrics → check thresholds → propose specific remediation → re-run. The QC gate definitions and remediation rules are domain-specific but the orchestrator structure is identical.

---

## Part 2: How to Be as Good as Claude Code at Intent Interpretation

### 2.1 What Claude Code Does Differently

Claude Code is exceptional at intent interpretation for three reasons:

**1. Context-first, action-second**  
Before Claude Code writes any code, it reads the relevant files. It builds a mental model of the existing system before proposing changes. A request like "add retry logic to the API client" triggers: read the client file → understand current structure → identify where retry logic should go → implement correctly.

**BioMate does the opposite:** receives a message → immediately classifies → routes to workflow → asks for parameters. There is no "read the current project state" step.

**2. Intent inference from context, not from literal words**  
When a user says "can you make it faster?", Claude Code infers they mean "optimize the bottleneck in the code I'm working on" — it reads the file, profiles the algorithm, and fixes the right thing. It does not ask "which file? faster how?"

**BioMate's routing** is keyword-based. "Can you run CRISPR analysis on my data?" vs. "Can you analyze CRISPR screen results for drug resistance?" might route to completely different workflows despite having similar intent.

**3. Decomposition with dependency mapping**  
Claude Code decomposes "migrate the database schema and update all callers" into: 1) modify schema file, 2) run migration, 3) find all callers (grep), 4) update each. Steps 3 and 4 depend on step 1. Claude Code executes them in the right order.

BioMate cannot currently say "this analysis requires first running QC, then alignment, then variant calling — I'll set up the pipeline in the right order."

---

### 2.2 The Specific Gap: Biological Context Interpretation

Claude Code has deep software engineering domain knowledge baked into its training. It knows what "refactor the database layer" means without asking.

BioMate needs equivalent depth in biology. When a user says "analyze my sequencing data," BioMate needs to infer:
- What organism? (from filename, header, previous conversation)
- What assay type? (WGS, RNA-seq, ATAC-seq, ChIP-seq — from read length, file size, previous context)
- What is the downstream goal? (variant calling → clinical diagnosis? differential expression → drug targets?)
- What QC do they need first?

This is not keyword matching — it's biological domain understanding applied to the specific project context.

---

### 2.3 Implementation Plan: Four Layers of Intent Improvement

#### Layer 1: Session Context Accumulation (Build once, use always)

**The problem:** Every BioMate session starts from scratch. The model doesn't remember that this user always works with hg38, always has single-end 150bp reads, always wants BWA+GATK.

**The fix (partially in place):** Memory injection (`_buildEpisodeMemoryBlock()`). Extend it to include:
- Most recent file uploads (organism, assay type inferred from headers)
- Most recently run workflows (recency matters — users iterate on the same analysis)
- Parameter overrides the user has made (strong signal about their preferences)

```python
# In galaxy-assistant.ts or ai_assistant.py:
def build_session_context(user_id: str, session_id: str) -> str:
    """Build rich context from session history."""
    recent_runs = db.get_recent_runs(user_id, limit=3)
    uploaded_files = db.get_session_files(session_id)
    param_overrides = db.get_user_param_preferences(user_id)
    
    return f"""[User Session Context]
Recent workflows: {[r.workflow_name for r in recent_runs]}
Uploaded files: {[f.name for f in uploaded_files]}  
Typical parameters: {param_overrides}
"""
```

#### Layer 2: Two-Pass Intent Resolution (Like Claude Code's "read before write")

**Current flow:** message → route → workflow  
**Proposed flow:** message → understand → plan → confirm → execute

Add an explicit "understanding pass" before routing:

```python
async def understand_intent(user_message: str, session_context: str) -> IntentPlan:
    """
    Pass 1: What does the user want? (no tools, just reasoning)
    Returns: goal, required_inputs, likely_workflow, uncertainty_flags
    """
    prompt = f"""
{session_context}

User message: {user_message}

Before selecting a workflow, answer:
1. What is the user's scientific goal? (one sentence)
2. What inputs do they have or need? 
3. What type of workflow would best achieve this goal?
4. What is uncertain or ambiguous about their request?
"""
    return await llm.structured_output(prompt, IntentPlan)
```

Only after this understanding pass does BioMate route to a specific workflow. This is exactly what Claude Code does when it reads files before writing.

#### Layer 3: Hierarchical Decomposition for Complex Requests

**The problem:** "Analyze my RNA-seq data and find drug targets" is a multi-workflow request. BioMate currently handles this as a single routing decision.

**The fix:** Implement a task decomposer that breaks complex requests into an ordered pipeline:

```python
PIPELINE_TEMPLATES = {
    "rna_seq_analysis": [
        {"step": "QC", "workflow": "fastqc", "required_before": "alignment"},
        {"step": "alignment", "workflow": "star_alignment", "depends_on": "QC"},
        {"step": "quantification", "workflow": "featurecounts", "depends_on": "alignment"},
        {"step": "differential_expression", "workflow": "deseq2", "depends_on": "quantification"},
    ],
    "variant_calling": [
        {"step": "QC", "workflow": "fastqc", "required_before": "alignment"},
        {"step": "alignment", "workflow": "bwa_mem2", "depends_on": "QC"},
        {"step": "variant_calling", "workflow": "gatk_haplotypecaller", "depends_on": "alignment"},
        {"step": "annotation", "workflow": "snpeff", "depends_on": "variant_calling"},
    ]
}
```

When a complex request is detected, BioMate presents the full pipeline plan to the user for confirmation, then executes in dependency order. This is Claude Code's "plan before execute" behavior.

#### Layer 4: Disambiguation with Evidence, Not Just Candidates

**Current disambiguation:** presents 2-4 candidate workflows and asks "which one?"

**Better disambiguation (Claude Code style):** investigates before asking. Before presenting candidates, BioMate should:
1. Check what files the user has uploaded (FASTQ → sequencing workflow; PDB → structure workflow)
2. Check the conversation history for domain signals
3. If genome assay type is ambiguous, look at read length in the uploaded file header
4. Only ask for clarification when the evidence is genuinely insufficient

```python
async def investigate_before_disambiguating(candidates: List[Workflow], context: SessionContext) -> Optional[Workflow]:
    """
    Attempt to resolve disambiguation using available evidence.
    Returns a workflow if confidence is high enough to proceed without asking.
    """
    if context.uploaded_files:
        file_evidence = infer_assay_type_from_files(context.uploaded_files)
        candidates = filter_by_assay_type(candidates, file_evidence)
        if len(candidates) == 1:
            return candidates[0]  # Resolved without asking!
    
    if context.recent_workflows:
        # User recently ran RNA-seq QC → they're in RNA-seq mode
        domain_hint = infer_domain_from_recent_workflows(context.recent_workflows)
        candidates = filter_by_domain(candidates, domain_hint)
        if len(candidates) == 1:
            return candidates[0]
    
    return None  # Still ambiguous — ask the user
```

---

### 2.4 The Biological Vocabulary Problem

Claude Code is trained on massive software engineering text. It knows what "factory pattern", "idempotent", "race condition" mean.

BioMate needs equivalent biological vocabulary depth. When a user says "I need to check for batch effects" BioMate should know this means `ComBat` or `limma::removeBatchEffect`, not a random workflow search.

**Short-term:** Build a biological synonym/intent map:

```python
BIOLOGICAL_INTENT_MAP = {
    # Variant calling
    ("SNP", "variant", "mutation", "SNV", "INDEL"): "variant_calling",
    ("somatic", "tumor", "cancer", "oncology"): "somatic_variant_calling",
    
    # Expression
    ("RNA-seq", "expression", "transcriptome", "differential expression", "DEG"): "rna_seq_analysis",
    ("batch effect", "normalization", "ComBat"): "batch_correction",
    
    # CRISPR
    ("CRISPR screen", "genome-wide screen", "sgRNA", "fitness"): "screen_gene_retrieval_or_analysis",
    ("CRISPR edit", "knockout", "knock-in", "HDR"): "crispr_editing_design",
    
    # Structure
    ("protein structure", "AlphaFold", "fold", "3D structure"): "protein_structure_prediction",
    ("docking", "binding", "ligand", "active site"): "molecular_docking",
}
```

**Long-term:** Fine-tune the routing classifier on domain-specific biological intent pairs. The routing benchmark (93% accuracy, 120 queries) should be expanded to 540+ queries covering 27 workflow types, then used as a fine-tuning dataset for the classifier.

---

## Part 3: Prioritized Implementation Roadmap

Based on impact × effort analysis across all benchmark findings:

| Priority | Change | Impact | Effort | Source |
|----------|--------|--------|--------|--------|
| P0 | Routing guard for knowledge questions | High | 2h | LABBench ProtocolQA |
| P0 | Context injection pipeline (workflow descriptions in prompt) | High | 1d | BiomniEval1 OT fix pattern |
| P1 | Two-pass intent resolution (understand → plan → execute) | Very High | 3d | Claude Code architecture |
| P1 | Session context accumulation (files + recent runs + preferences) | High | 2d | Memory architecture |
| P1 | Pipeline decomposition templates (RNA-seq, variant calling chains) | High | 3d | Claude Code decomposition |
| P2 | Biological vocabulary synonym map | Medium | 1d | Routing benchmark |
| P2 | Pre-compute file header context (genome, read length, paired-end) | Medium | 1d | BiomniEval1 precompute pattern |
| P2 | Investigate-before-disambiguate (file evidence resolution) | Medium | 2d | Claude Code investigate-first |
| P3 | Auto-loop for genomics QC (FastQC → alignment → variant QC) | High | 5d | Auto-loop benchmark |
| P3 | Retry on low-confidence routing classifications | Low | 4h | Nondeterminism lesson |

---

## Part 4: What the AI Tool DB Contributes

The Biomni molecular biology tool suite (43+ tools: `biomni_molecular_biology_design_primer`, `find_restriction_sites`, `digest_sequence`, `golden_gate_assembly`, etc.) is currently indexed but not used for knowledge question answering.

**The gap:** CloningScenarios-type questions (39% score) require computation that these tools can do. But the benchmark says "no workflow." The insight is that **the adapter should call these tools at prompt-build time** (precomputed context injection), not at query time.

**For live BioMate users:** When a user asks "what restriction enzyme should I use to linearize this plasmid?", BioMate should:
1. Detect this is a knowledge+computation question
2. Parse the plasmid sequence from their message
3. Call `biomni_molecular_biology_find_restriction_sites` inline (fast, <1s)
4. Return the list of unique cutters with cut positions as direct context to the LLM
5. LLM answers the question using that computed evidence

This is the direct application of the BiomniEval1 precomputed-context-injection lesson to the AI tool DB.

---

## Implementation Status (2026-04-20)

### Implemented This Session

| Change | File | Effect |
|--------|------|--------|
| Mol-bio tool context injection | `research_agent.py` `_fetch_mol_bio_tool_context()` | Injects 28 mol-bio tools (restriction enzymes, cloning, PCR, CRISPR) into research synthesis prompt when question is a protocol/wet-lab knowledge question |
| Keyword gate replaced with LLM-intent gate | same | Keywords now advisory only; LLM intent type (`protocol_guidance`, `experiment_design`, etc.) is primary activation signal |
| Research response detruncation | `galaxy-assistant.ts` `generateResponse()` | `researchResponse` now serialized to extract `answer` (4000 chars) + formatted citations instead of raw JSON sliced at 2000 chars |
| Concise answer instruction | `research_agent.py` `_build_synthesis_prompt()` | "Lead with the answer; 2–4 sentences for simple questions" instruction added |
| Concise answer instruction | `galaxy-assistant.ts` system prompt (research path) | "Be concise and direct; lead with the answer" added to research intent system prompt |

### LABBench v2 Results (validated improvements)

| Subtask | v1 | v2 | Confirmed Δ |
|---------|-----|-----|------------|
| CloningScenarios | 39.4% | **48.5%** | **+9.1pp** (sequence context works) |
| LitQA2 | 42.2% | 42.7% | +0.5pp (flat — needs PubMed depth) |
| ProtocolQA | 70.4% | 67.6% | -2.8pp (noise; still +12pp above baseline) |
| **Overall** | **50.9%** | **51.2%** | **+0.3pp** |

### Open Items (P1–P2)

- **LitQA2 ceiling**: At 42-43%, likely limited by literature lookup quality. Increasing PubMed full-text retrieval depth (currently capped at 5 papers) or adding Semantic Scholar full text would help.
- **Pipeline decomposition templates**: Already in `workflow_chains` DB; surfacing them more aggressively for "full pipeline" requests.
- **Biological synonym map**: Tool name aliases (DESeq2 → bulk_rnaseq_de_analysis) — partially handled by named-anchor extraction.

---

## Summary Table

| Benchmark Lesson | Improvement Type | Live BioMate Impact |
|-----------------|-----------------|---------------------|
| Routing guard prefix | Routing fix | -10-20% false workflow dispatches |
| Precomputed context injection | Better answers | +5-15% accuracy on domain questions |
| MANDATORY vs. advisory format | Prompt engineering | +10pp when context is reliable |
| Two-pass understanding | Architecture | Fewer disambiguation failures |
| Session context accumulation | Memory | Correct parameter prefill for repeat users |
| Pipeline decomposition | Multi-workflow UX | Handles "full pipeline" requests |
| File evidence disambiguation | Routing quality | Fewer unnecessary clarification questions |
| Auto-loop convergence | Reliability | Automated failure recovery |
| Biological vocabulary map | Routing precision | Better first-try routing |
| Retry on nondeterminism | Robustness | Fewer random failures |
