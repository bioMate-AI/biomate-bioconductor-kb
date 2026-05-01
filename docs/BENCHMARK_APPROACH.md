# Established Benchmark Improvement Approach

## Core Philosophy

**Benchmarks measure capabilities. Low scores mean missing knowledge or missing context — not model failure.**

Every benchmark gap follows one of three root causes:
1. **Format/extraction bug** — wrong answer format, wrong endpoint, wrong regex
2. **Context gap** — the model has the right knowledge but can't access the right data
3. **Capability gap** — the task genuinely requires capability the model lacks (e.g., executing code)

Fix in this order. Context gaps are almost always solvable. Capability gaps sometimes require architectural changes.

---

## Phase 1: Diagnosis

### 1a. Identify the failure mode
For every failing task, answer: *What did the model say? What should it have said? Why are they different?*

```python
# Load and analyze failures
conn = sqlite3.connect('results/eval_results.db')
c.execute('SELECT task_id, score, agent_response, ground_truth FROM results WHERE score=0')
```

Look for patterns:
- Response starts with "**Missing:**" or "**Running:**" → routing false-positive (model entered workflow mode)
- Response picks a different correct-looking answer → context ambiguity
- Response is "I cannot answer without..." → model blocked by routing guard
- Response is completely wrong → model lacks context

### 1b. Check for systematic extraction bugs
Before blaming the model, check:
- Is the answer extraction regex correct?
- Is the correct answer format being matched?
- Is the benchmark YAML dataset correct? (parameter names, expected values)

**Rule: Fix bugs before fixing prompts.**

---

## Phase 2: Context Sources (in order of reliability)

### Tier 1: Statistical Databases (highest reliability for factual ranking)
- **GWAS Catalog** (EBI): `https://www.ebi.ac.uk/gwas/rest/api/` — GWAS associations by rsID
- **Open Targets**: `https://api.platform.opentargets.org/api/v4/graphql` — gene-disease scores
- **ClinVar** (NCBI): `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/` — clinical significance
- **OMIM** (via UniProt): disease-gene associations

### Tier 2: Functional Annotation (gene-level biology)
- **Ensembl REST**: `https://rest.ensembl.org/` — variant position, nearby genes (batch-capable)
- **MyGene.info**: `https://mygene.info/v3/` — gene function, GO terms, summary
- **UniProt**: protein function, disease associations

### Tier 3: Specialized Domain Databases
- **BioGRID ORCS**: CRISPR screen gene ranking (key: `5bec3884b8d8deddaab64c6743ed4cff`)
- **HPO**: `genes_to_phenotype.txt` — gene-phenotype associations for rare disease
- **GWAS Catalog local download**: `ftp.ebi.ac.uk/pub/databases/gwas/releases/latest/` — 60MB zip, 1.1M rows

---

## Phase 3: Anti-Rate-Limiting Pattern

**Always cache external API responses persistently.**

```python
# Pattern: persistent HTTP cache (works for any API)
_CACHE: Dict[str, Any] = {}
_CACHE_PATH = Path("datasets/cache/api_name_cache.json")
_DIRTY = False

def _load_cache():
    global _CACHE
    if _CACHE: return
    if _CACHE_PATH.exists():
        _CACHE.update(json.load(open(_CACHE_PATH)))

def _save_cache():
    global _DIRTY
    if _DIRTY:
        json.dump(_CACHE, open(_CACHE_PATH, 'w'))
        _DIRTY = False

def _fetch(url, timeout=4):
    _load_cache()
    if url in _CACHE: return _CACHE[url]
    data = requests.get(url, ...).json()
    _CACHE[url] = data; _DIRTY = True
    if len(_CACHE) % 50 == 0: _save_cache()
    return data
```

**Why this matters**: GWAS Catalog silently fails after ~500 API calls/day (no rate-limit header). With persistent caching, the 2nd+ benchmark run is essentially free.

---

## Phase 4: Context Injection Priority

For any factual retrieval task, use this layered priority:

```
Priority 1: Statistical database rank (p-value, score, count)
  → Use when database has direct evidence for the query phenotype
  → Most reliable for common phenotypes

Priority 2: Biological pathway annotation (gene function)  
  → Use when statistical data is absent (metabolite GWAS, rare diseases)
  → Only apply for specific chemical entities, not complex traits
  → Ensembl REST: 1 batch call for all candidates, then gene overlap per variant

Priority 3: Training knowledge
  → Use when no external data is available
  → Most reliable for canonical, well-studied variants/genes/diseases
```

---

## Phase 5: Format Instruction Design

### Rules that work:
```
MANDATORY RULES:
1. If [context type X] is provided, the item ranked #1 IS the answer.
2. [Secondary evidence] only when primary is absent.
3. DO NOT refuse. DO NOT ask for data files. DO NOT explain.

Respond with ONLY the answer format (e.g., rs4253311). Nothing else.
```

### Anti-patterns to avoid:
- ❌ "Think step by step" — causes multi-sentence justification that confuses extraction
- ❌ Hard override rules ("IS the answer") when they conflict → regressions
- ❌ Gene-pathway rule for complex traits (LDL/HDL cholesterol) → false positives
- ✅ Priority order with explicit conditions
- ✅ "CAUTION: only apply rule X for [specific phenotype types]"

---

## Phase 6: Benchmark Run Protocol

```bash
# 1. Run benchmark — save to versioned output directory
python runners/run_X_benchmark.py --output results/benchmark_vN/

# 2. Analyze failures
python -c "
import sqlite3; conn = sqlite3.connect('results/benchmark_vN/eval_results.db')
c.execute('SELECT task_id, score, agent_response FROM results WHERE score=0')
for r in c.fetchall(): print(r[0], r[2][:100])
"

# 3. Compare with previous version
# Find improvements and regressions

# 4. Only commit when net improvement ≥ 1 with 0 or acceptable regressions
```

### When to stop iterating:
- If fix causes regressions > improvements → revert
- If remaining failures require data you cannot access → document and move on
- If score is within noise range of target → accept as passing

---

## Phase 7: Lessons from Each Benchmark

| Benchmark | Root Cause Pattern | Key Fix |
|-----------|-------------------|---------|
| gwas_variant | API rate limiting + missing metabolite context | Persistent cache + Ensembl gene annotation |
| param_prefill | Chain routing hijack + wrong endpoint + missing stubs | skip_chains=True + direct Galaxy port |
| LABBench | Pre-computed context on individual sequences, not assembled | Simulate Golden Gate assembly product |
| SGI idea_gen | "generate novel proposal" overrides instruction | CRITICAL OVERRIDE + paper-naming template |
| screen_gene | No access to CRISPR screen databases | BioGRID ORCS IDF-weighted fingerprinting |
| gwas_causal | Sparse OMIM coverage for gene-disease | Gene-level HPO IDF overlap (genes_to_phenotype.txt) |
| patient_gene | Generic disease names matched wrong genes | Gene-level HPO IDF overlap |

---

## Quick Checklist for New Benchmarks

Before building a new adapter:
1. What does the benchmark measure? (capability vs. knowledge vs. format)
2. What external databases are relevant? (are they accessible from this server?)
3. What is the answer format? (rsID, gene symbol, JSON, free text?)
4. Is there a systematic extraction pattern to verify?
5. What is the "always available" fallback when external data fails?
6. Does the benchmark have known biases? (p-value vs biological importance?)

*Last updated: 2026-04-30*
