# Hallucination Detection — Methodology, Limitations, and Path to Determinism

**Date:** 2026-04-27

---

## What "Hallucination" Means in Our Context

A hallucination in BioMate's outputs is a response that contains a **verifiably false or fabricated claim** at an important step. We distinguish three classes:

| Label | Definition | Example |
|-------|-----------|---------|
| `grounded` | Claim is supported by the task context, established biology, or verifiable databases | "BRCA2 is associated with hereditary breast cancer" — verifiable, correct |
| `hallucinated` | Claim is provably false or contains fabricated data (wrong OMIM ID, non-existent gene function, invented citation) | OMIM ID "999999" (out of valid range 100000–620000) for a real disease |
| `unverifiable` | Claim cannot be confirmed or refuted without external lookup not available to the judge | "Study X from 2019 showed..." — may be real, judge cannot verify |

**Hallucination rate = hallucinated / (grounded + hallucinated)** — unverifiable responses excluded from denominator.

---

## How We Currently Detect It (and Why SGI-Bench Was Unreliable)

The current implementation uses **Claude Haiku as an LLM-as-judge** (`hallucination_detector.py`). For each response, Haiku receives:
- The task context (question or task ID stub)
- The model's response
- The ground truth (for reference)
- A step-type-specific prompt

**Critical flaw in the SGI-Bench 25.5% number:**  
The audit called the judge with `question = "[Task ID: sgi_bench_life__xxx]"` — a bare task ID, not the actual question text. The judge had no question context to reason from. The 25.5% reflects "Haiku flagged these responses based on response text alone" — not verified hallucination. **This number should be treated as unreliable and not reported.**

### What makes a hallucination detection reliable vs unreliable:

| Condition | Reliability | Our current state |
|-----------|-------------|------------------|
| Judge has actual question text | Required | ✅ Done for biomni_eval1, labbench, bixbench |
| Judge has ground truth | Important | ✅ Done for all |
| Step type is verifiable without external lookup | High | ✅ ENSG format (regex), OMIM range (regex), MCQ letter |
| Step type requires external knowledge | Medium | ⚠️ gene functions, disease mechanisms |
| SGI-Bench scientific claims | Low without literature access | ❌ Judge has no paper access |

---

## How to Reduce Hallucinations in BioMate

### Root causes by task type:

**1. gene_identification (gwas_causal)**
- Cause: Model conflates similar-sounding genes or invents mechanisms
- Reduction: Add RAG from OpenTargets/UniProt to give model verified gene-disease associations before response generation. Measure: does having OT context reduce hallucination_rate?

**2. disease_identification (rare_disease)**
- Cause: Model invents OMIM IDs or disease names not in OMIM
- Reduction: Pre-filter response with OMIM API lookup. If stated OMIM ID doesn't resolve → force regeneration.
- This is already partially done via BioMate's tool use (OMIM lookup tool).

**3. mcq_rationale (CloningScenarios)**
- Cause: Model picks wrong answer letter AND constructs false biological rationale to justify it
- Reduction: After answering, run a second judge pass that checks the rationale against the correct answer. If rationale contradicts known biology, flag for regeneration.

**4. scientific_claim (SGI-Bench, BixBench)**
- Cause: Open-ended research questions invite invented citations and unverifiable claims
- Reduction: Require model to cite only sources in its context. BioMate already injects literature context via RAG — measuring whether RAG reduces hallucination rate is a key experiment.

---

## How to Make Hallucination Detection Deterministic

Current approach is probabilistic: Haiku judge may give different answers on different calls. Three paths to determinism:

### Path 1: Rule-based checks (deterministic, zero cost)
Already implemented for two step types:
```python
# ENSG format: ENSG + exactly 11 digits
if not re.search(r'ENSG\d{11}', response):
    return HallucinationResult(label="hallucinated", confidence=0.95, ...)

# OMIM ID range: valid range 100000–620000
omim_ids = re.findall(r'\b(\d{6})\b', response)
for oid in omim_ids:
    if not (100000 <= int(oid) <= 620000):
        return HallucinationResult(label="hallucinated", ...)
```
**Extend to:** gene symbol format validation (human genes: 2-8 uppercase letters + optional number), chromosome notation, p-value format, amino acid notation.

### Path 2: Database verification (deterministic if DB is available)
For specific step types, verify against authoritative DBs:
```python
# gene_identification: check HGNC database
def verify_gene(gene_name: str) -> bool:
    r = requests.get(f"https://rest.genenames.org/fetch/symbol/{gene_name}")
    return r.status_code == 200 and r.json().get("response", {}).get("numFound", 0) > 0

# disease_identification: check OMIM API
def verify_omim(omim_id: str) -> bool:
    r = requests.get(f"https://api.omim.org/api/entry?mimNumber={omim_id}&apiKey={OMIM_KEY}")
    return r.status_code == 200
```
This is **completely deterministic** and **much more reliable** than LLM judging. Requires API keys for OMIM, HGNC, Ensembl.

### Path 3: N-sample consistency (SelfCheckGPT approach)
Run the same query N=3 times at temperature > 0. If responses agree on the key claim → grounded (consistent = likely known). If they disagree → probable hallucination.
```
Consistency = agreement across N samples
Hallucination_score = 1 - consistency
```
Deterministic at the population level (consistent sampling distribution), probabilistic per-instance.

---

## Revised Hallucination Audit Plan

### Immediate fixes:
1. **Re-run SGI-Bench audit** with actual question text extracted from the original dataset
2. **Add database verification** for gene_identification and disease_identification (HGNC + OMIM API)
3. **Use rule-based checks first** before calling LLM judge — only fall back to Haiku for ambiguous cases

### Priority order for reliable numbers:
1. `disease_identification` (rare_disease): OMIM ID range check → deterministic ✅
2. `ensg_lookup` (patient_gene): ENSG format regex → deterministic ✅
3. `gene_identification` (gwas_causal): HGNC API verification → deterministic with API key
4. `mcq_rationale` (CloningScenarios): LLM judge with full question → reliable ✅
5. `scientific_claim` (SGI-Bench): needs literature access → currently unreliable ❌

### Expected hallucination rates after proper measurement:
Based on BioMate's task-level accuracy:
- BiomniEval1 rare_disease: accuracy 76.7% → hallucination rate should be ~15-25% (wrong answers often involve invented OMIM IDs)
- BiomniEval1 gwas_causal: accuracy 78% → hallucination rate ~10-15% (wrong gene + invented mechanism)
- LABBench CloningScenarios: accuracy 93.9% → hallucination rate ~5-10% (wrong MCQ letter with false rationale)

---

## Implementation Roadmap

### Phase 1 (today): Rule-based + database verification layer
```python
# In hallucination_detector.py, add before LLM judge call:
def _rule_based_check(response, step_type, ground_truth) -> Optional[HallucinationResult]:
    if step_type == "ensg_lookup":
        return _quick_ensg_check(response, ground_truth)  # already exists
    if step_type == "disease_identification":
        return _quick_omim_check(response)  # already exists
    if step_type == "gene_identification":
        return _hgnc_check(response)  # NEW: verify gene symbols against HGNC
    return None  # fall through to LLM judge
```

### Phase 2 (this week): N-sample consistency for scientific claims
For SGI-Bench and BixBench, run each query 3x and measure self-consistency.
Report: "Hallucination proxy = 1 - mean pairwise agreement on key claims"

### Phase 3 (next sprint): Human annotation ground truth
Label 50 responses per benchmark (expert biologist annotator). Use as calibration set for Haiku judge. Report: "Haiku judge F1 = X vs human labels on N=50 calibration set."

---

## Reporting Standard Going Forward

When reporting hallucination rates, always specify:
1. **Detection method**: rule-based | LLM-judge | DB-verification | human-annotated
2. **Judge model** (if LLM): Claude Haiku 4.5
3. **Context available**: full question ✅ / task ID stub ❌ / ground truth ✅
4. **Assessable fraction**: N out of M responses were assessable (unverifiable excluded)

Example correct reporting:
> "BioMate rare_disease hallucination rate: 18.3% [n=60, OMIM range check + Haiku judge with full question text; 12/60 unverifiable responses excluded; assessable n=48]"

Example incorrect reporting:
> "SGI-Bench hallucination rate: 25.5%" [no question text, no DB verification — DO NOT USE]
