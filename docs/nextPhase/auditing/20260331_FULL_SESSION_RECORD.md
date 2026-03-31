# 2026-03-31 Full Session Record

Branch: `integration/next-phase`
Commit: `872ed3c56`
Tests: 174 unit tests passing, 0 TypeScript errors

---

## Overview of Everything Done This Session

This session had two separate workstreams that were completed end to end:

1. **Domain Registry Consolidation** — created a single source of truth for domain
   categories that were previously duplicated and inconsistent across 7 files
2. **Four LLM assistant improvements** (S1, S2, S5, S6) from the audit priority table

---

## Part 1: Domain Registry Consolidation

### The Problem

Domain categories (the list of research domains BioMate understands) were defined
independently in at least 7 different places, each with slightly different content:

| File | What it defined | Problems |
|------|----------------|---------|
| `domain_router.py` | `DOMAIN_KEYWORDS` (15 domains) | Different domain names than taxonomy |
| `domain_specialist.py` | `DOMAIN_PROMPTS` (9 domains only) | Missing 6 domains |
| `domain_taxonomy.py` | `DOMAIN_TAXONOMY` (8 domains) | Used hyphen `single-cell` not `single_cell` |
| `domain_workflow_patterns.py` | `AnalysisDomain` enum (8 members) | Missing `cryo_em`, `lab_automation`, etc. |
| `galaxy-assistant.ts` | `VALID_DOMAINS` inline list | Different from Python side |
| `ai_assistant.py` | inline string list in system prompt | No import, just hardcoded |
| `galaxy-assistant.ts` | analyzeIntent prompt list | Yet another copy |

A domain added to the DB workflows directory (e.g. `bioimaging`) would not appear in
the router, the specialist, the taxonomy, or the TypeScript side. Every new domain
required 7 separate manual edits.

### What Was Built

**`backend/lib/galaxy/ai/domain_registry.py`** (new, 464 lines) — the single canonical source:

```python
CANONICAL_DOMAINS: List[str] = [
    "genomics", "transcriptomics", "single_cell", "epigenomics",
    "proteomics", "metabolomics", "metagenomics", "structural_biology",
    "drug_discovery", "cryo_em", "systems_biology", "synthetic_biology",
    "bioimaging", "lab_automation",
]

ROUTING_ONLY_DOMAINS: List[str] = [
    "immunology", "cancer_biology", "molecular_biology", "biochemistry",
    "genetics", "microbiology", "cell_biology", "biophysics", "bioengineering",
    "glycoengineering", "pathology", "physiology", "database", "literature",
    "variant_calling", "multi_omics",
]

DOMAIN_LABELS: Dict[str, str]          # UI display names
DOMAIN_TOPICS: Dict[str, List[str]]    # Topics per domain (used for profile building)
DOMAIN_KEYWORDS: Dict[str, Set[str]]   # Keywords used by domain_router.py
DOMAIN_TO_GALAXY_CATEGORY: Dict[str, List[str]]  # Galaxy tool categories per domain
DOMAIN_SPECIALIST_PROMPTS: Dict[str, str]         # LLM prompts per domain specialist
SUBDOMAIN_TO_CANONICAL: Dict[str, str]            # rna_seq→transcriptomics, etc.
get_topics_for_domains(domains) -> List[str]      # helper used by taxonomy
```

The distinction between `CANONICAL_DOMAINS` (14) and `ROUTING_ONLY_DOMAINS` (16) is
important: canonical domains appear in the user profile UI; routing-only domains exist
in the workflow filesystem but are not shown as user preferences.

### Files Updated to Import From Registry

**`backend/lib/galaxy/ai/domain_taxonomy.py`** — rewritten as a thin wrapper:
```python
from .domain_registry import (
    CANONICAL_DOMAINS,
    DOMAIN_LABELS,
    DOMAIN_TOPICS as DOMAIN_TAXONOMY,
    get_topics_for_domains as _get_topics,
)
```
It no longer defines its own domain list.

**`backend/lib/galaxy/ai/agents/domain_router.py`** — removed its own `DOMAIN_KEYWORDS`
(15 entries) and `DOMAIN_TO_CATEGORY` (15 entries), replaced with:
```python
from ..domain_registry import DOMAIN_KEYWORDS as _REGISTRY_KEYWORDS, \
                              DOMAIN_TO_GALAXY_CATEGORY as _REGISTRY_CATEGORIES
```

**`backend/lib/galaxy/ai/agents/domain_specialist.py`** — removed its own `DOMAIN_PROMPTS`
dict (only 9 entries, missing 6 domains), replaced with:
```python
from ..domain_registry import DOMAIN_SPECIALIST_PROMPTS as _REGISTRY_PROMPTS
DOMAIN_PROMPTS: Dict[str, str] = _REGISTRY_PROMPTS
```

**`backend/lib/galaxy/ai/domain_workflow_patterns.py`** — `AnalysisDomain` enum expanded
from 8 members to 16 (all 14 canonical + DATA_QUERY + GENERAL):
```python
class AnalysisDomain(Enum):
    GENOMICS = "genomics"
    TRANSCRIPTOMICS = "transcriptomics"
    SINGLE_CELL = "single_cell"
    EPIGENOMICS = "epigenomics"
    PROTEOMICS = "proteomics"
    METABOLOMICS = "metabolomics"
    METAGENOMICS = "metagenomics"
    STRUCTURAL_BIOLOGY = "structural_biology"
    DRUG_DISCOVERY = "drug_discovery"
    CRYO_EM = "cryo_em"
    SYSTEMS_BIOLOGY = "systems_biology"
    SYNTHETIC_BIOLOGY = "synthetic_biology"
    BIOIMAGING = "bioimaging"
    LAB_AUTOMATION = "lab_automation"
    DATA_QUERY = "data_query"
    GENERAL = "general"
```

**`frontend/server/domain-registry.ts`** (new) — TypeScript mirror of the Python registry,
so the frontend doesn't maintain its own separate list:
```typescript
export const CANONICAL_DOMAINS = [
  'genomics', 'transcriptomics', 'single_cell', 'epigenomics',
  'proteomics', 'metabolomics', 'metagenomics', 'structural_biology',
  'drug_discovery', 'cryo_em', 'systems_biology', 'synthetic_biology',
  'bioimaging', 'lab_automation',
] as const;

export type CanonicalDomain = typeof CANONICAL_DOMAINS[number];
export const DOMAIN_LABELS: Record<CanonicalDomain, string>
export const TECHNICAL_SUBDOMAINS = [...] as const;   // finer granularity for LLM intent
export type TechnicalSubdomain = typeof TECHNICAL_SUBDOMAINS[number];
export const SUBDOMAIN_TO_CANONICAL: Record<TechnicalSubdomain, CanonicalDomain>
export const PREFERRED_DOMAINS_PROMPT_LIST = CANONICAL_DOMAINS.join(', ')
```

**`frontend/server/galaxy-assistant.ts`** — removed inline domain lists, now imports:
```typescript
import {
  CANONICAL_DOMAINS, TECHNICAL_SUBDOMAINS, SUBDOMAIN_TO_CANONICAL,
  PREFERRED_DOMAINS_PROMPT_LIST, type CanonicalDomain, type TechnicalSubdomain,
} from './domain-registry';
```

### Naming Convention Enforced

- Always underscore: `single_cell` not `single-cell`, `drug_discovery` not `pharmacology`
- All canonical domain strings are lowercase
- The CLAUDE.md comment in `domain-registry.ts` says: "CANONICAL SOURCE: domain_registry.py
  (Python). When adding a new domain, update domain_registry.py first, then mirror here."

---

## Part 2: LLM Assistant Improvements

These four changes address specific weaknesses identified in the LLM usage audit document
(`docs/nextPhase/20260330_LLM_USAGE_AUDIT.md`).

---

### S5 — CLARIFICATION_FALLBACKS Completeness Test

**File changed:** `frontend/server/galaxy-assistant.ts`, `frontend/server/analyze-intent-uqu.test.ts`

**The problem:**

The `CLARIFICATION_FALLBACKS` dictionary — 15 static question strings, one for each
workflow "fork point" (places where a vague user query could map to two fundamentally
different pipelines) — was defined *inside* `processMessage()`. Being a local variable,
it was impossible to import in tests. No assertion verified that every fork point
defined in the system prompt had a corresponding fallback entry.

If a developer added a new fork point to the system prompt (e.g. `imaging_modality`) but
forgot to add a matching fallback string, the gate would silently produce no clarification
question — the workflow would proceed without asking the required disambiguating question.

**What was done:**

1. Moved `CLARIFICATION_FALLBACKS` from inside `processMessage()` to **module level**.
2. Added `export` so it can be imported in tests.
3. Removed the duplicate inline definition.
4. Added 16 new test assertions in `analyze-intent-uqu.test.ts`:
   - One test per fork-point type from the system prompt's "Known fork points" section.
   - One test that the set has no *extra* stale keys.
   - Tests fail immediately when a fork point is added to the system prompt without a matching fallback.

**The 15 fork points covered:**

| Fork point key | What it disambiguates |
|---------------|----------------------|
| `variant_type` | Germline vs somatic variant calling |
| `assembly_type` | De novo vs reference-guided assembly |
| `rnaseq_type` | Bulk RNA-seq vs single-cell RNA-seq |
| `scrna_type` | Standard scRNA atlas vs perturbation screen |
| `peak_calling_type` | ChIP-seq vs ATAC-seq |
| `chip_target` | Transcription factor vs histone modification |
| `rnaseq_focus` | mRNA/DE vs small RNA/miRNA |
| `flow_cytometry_type` | Immunophenotyping vs sorting vs clustering |
| `proteomics_type` | DDA (MaxQuant) vs DIA (DIA-NN) |
| `cryoem_type` | Single-particle analysis vs cryo-ET |
| `cryoem_sample` | Globular particle vs filamentous assembly |
| `somatic_paired` | Matched tumor-normal vs tumor-only |
| `metagenomics_type` | 16S amplicon vs shotgun metagenomics |
| `docking_type` | Blind docking vs site-directed docking |
| `admet_scope` | Asks for molecule + which safety endpoints |

**Test count:** 43 → 59

---

### S1 — `_clarificationGate()` Extraction

**File changed:** `frontend/server/galaxy-assistant.ts`

**The problem:**

The ambiguity check that triggers a clarifying question was ~30 lines of inline code
inside `processMessage()`, surrounded by tool search setup, SMILES fast-path logic,
and workflow generation code. Any future refactor touching the surrounding code could
accidentally skip the gate. It was also not independently testable.

**What was done:**

Extracted to a named private method:
```typescript
private async _clarificationGate(
  intent: any,
  actions: any,
  message: string,
  recommendedTools: ToolRecommendation[],
  recommendedDatasets: DatasetRecommendation[]
): Promise<GalaxyAssistantResponse | null>
```

- Returns `null` → no gate fires, caller continues to workflow generation.
- Returns a full `GalaxyAssistantResponse` → gate fired, caller returns early.

The call site in `processMessage()` is now 4 lines:
```typescript
const clarificationResponse = await this._clarificationGate(
  intent, actions, message, recommendedTools, recommendedDatasets
);
if (clarificationResponse) return clarificationResponse;
```

The gate is now a discrete, named operation. Its contract (`null` = pass, response =
stop) is enforced by the type system. It uses module-level `CLARIFICATION_FALLBACKS`
(testable via S5).

---

### S2 — Confidence-Gated Session Memory Injection

**File changed:** `frontend/server/galaxy-assistant.ts`

**The problem:**

`SessionMemory.key_decisions` and `open_questions` were `string[]`. The Haiku model
that maintains session memory infers items at varying confidence levels — some are
explicit user statements ("I have paired-end reads"), others are reasonable inferences
("the user probably wants GRCh38 since they mentioned human"), others are guesses.

All items were injected into the system prompt with equal weight. Low-confidence
inferences pollute the LLM context and can create false premises ("You decided to use
GRCh38" when the user never said that).

**What was done:**

1. Added new interface:
```typescript
export interface SessionMemoryItem {
  text: string;
  /** Haiku-assigned confidence 0–1. Items below 0.7 are suppressed from injection. */
  confidence: number;
}
```

2. Changed `SessionMemory`:
```typescript
// Before:
key_decisions: string[];
open_questions: string[];

// After:
key_decisions: SessionMemoryItem[];
open_questions: SessionMemoryItem[];
```

3. Updated the `UPDATE_PROMPT` system prompt that instructs Haiku on what to output.
   Previously it asked for string arrays. Now it asks for object arrays with confidence:
```
- key_decisions: list of technical decisions made (max 8 items), each as
  {"text": "...", "confidence": 0.0-1.0}
  confidence: 0.9=explicit user statement, 0.7=strong inference, <0.7=speculation
- open_questions: unresolved questions, each as {"text": "...", "confidence": 0.0-1.0}
  confidence: how likely this question will affect the next step
```

4. Updated `_buildSessionMemoryBlock()` to filter before injecting:
```typescript
const highConfDecisions = mem.key_decisions.filter(d => d.confidence >= 0.7);
if (highConfDecisions.length > 0)
  parts.push(`Key decisions: ${highConfDecisions.map(d => d.text).join('; ')}`);
```

5. Added backward-compatibility: if Haiku returns a plain string (old format sessions),
   it is coerced to `{ text: s, confidence: 0.7 }` so existing sessions keep working.

**Why 0.7 threshold:**
- `≥ 0.9` = the user said it explicitly → always inject
- `0.7–0.9` = reasonable technical inference → inject
- `< 0.7` = speculation → stored in memory but NOT injected into the system prompt;
  the Haiku can still surface it as an open question next turn

Items below 0.7 are never deleted — they remain in the memory object. They just do not
appear in the `<session_memory>` block. This means if the user later confirms a speculation,
Haiku can upgrade its confidence on the next update cycle.

---

### S6 — Domain Catalog Injection (Generalized)

**File changed:** `frontend/server/galaxy-assistant.ts`

**The original (wrong) implementation:**

The first cut injected a hardcoded `<drug_discovery_catalog>` block gated on
`isDrugDevelopmentQuery` — a keyword regex checked against the *message text*:

```typescript
const isDrugDevelopmentQuery = /(drug|admet|herg|dili|toxicity|docking|...)/i.test(lowerMessage);
```

**Why that was wrong:**

1. **Wrong signal.** `isDrugDevelopmentQuery` fires on message keywords. It does not
   use `preferredDomains`, which is the proper signal derived from:
   - The user's saved domain profile (set in account settings)
   - The intent classifier's `preferred_domains` output for this query
   A drug-discovery user asking a genomics question gets no catalog. A random user
   asking "what is clinical significance?" gets the catalog injected.

2. **Not extensible.** Adding catalogs for other domains (cryo-EM, lab automation…)
   would require another hardcoded `if (isXxxQuery)` block. No shared pattern.

**The correct implementation:**

`DOMAIN_CATALOGS` — a `Partial<Record<string, string>>` map at module level, exported:
```typescript
export const DOMAIN_CATALOGS: Partial<Record<string, string>> = {
  drug_discovery: `Available BioMate drug discovery workflows:
- alphafold_db_search: ...
- structure_prediction_docking: ...
- amber_pmemd_md: ...
...`,
  // Other domains added here as their workflow sets grow
};
```

`buildDomainCatalogBlock(preferredDomains: string[]): string` — exported helper:
```typescript
export function buildDomainCatalogBlock(preferredDomains: string[]): string {
  const entries = preferredDomains
    .map(d => DOMAIN_CATALOGS[d])
    .filter((c): c is string => !!c);
  if (entries.length === 0) return '';
  return `<domain_catalog>\n${entries.join('\n\n')}\n</domain_catalog>\n`;
}
```

`generateResponse()` extended with `preferredDomains: string[] = []` parameter.
Both call sites updated to pass `decomposition.preferredDomains`.
The catalog block in the system prompt is now:
```typescript
${buildDomainCatalogBlock(preferredDomains)}Style guide:
```

**Why only `drug_discovery` has an entry today:**

The catalog is specifically about BioMate-specific workflows that the LLM *cannot*
infer from general knowledge. For genomics, the LLM knows GATK, BWA, DESeq2 — but it
does NOT know that BioMate has `wgs_germline_gatk`, `crispr_screen_mageck`, or the
specific pipeline configurations available. This means the current `drug_discovery`-only
state is still an incomplete implementation — the catalog should be populated for all
domains. The correct next step is to enumerate BioMate's registered workflows per domain
and add catalog entries accordingly.

The rule for when to add an entry: when BioMate has ≥4 registered workflows for a domain.
Current candidates once their workflow sets are documented:
- `cryo_em` — CryoSPARC SPA, helical, subtomogram already built
- `genomics` — wgs_germline_gatk, crispr_screen_mageck, chipseq, scRNA workflows
- `lab_automation` — PyLabRobot liquid handling workflows

---

## Test Results

| Test file | Tests | Status |
|-----------|-------|--------|
| `analyze-intent-uqu.test.ts` | 59 | ✅ all pass |
| `personalization-drug-discovery.test.ts` | 115 | ✅ all pass |
| TypeScript `tsc --noEmit` | — | ✅ 0 errors |

Pre-existing failures in `workflow-notification-service.test.ts` (2 tests) are unrelated
to this session — they were failing before any changes were made.

---

## File Change Summary

| File | Type | What Changed |
|------|------|-------------|
| `backend/lib/galaxy/ai/domain_registry.py` | **NEW** | Single source of truth for all 14 canonical domains |
| `backend/lib/galaxy/ai/domain_taxonomy.py` | modified | Rewritten as thin re-export wrapper |
| `backend/lib/galaxy/ai/agents/domain_router.py` | modified | Removed 30-line DOMAIN_KEYWORDS dict; imports from registry |
| `backend/lib/galaxy/ai/agents/domain_specialist.py` | modified | Removed 9-entry DOMAIN_PROMPTS dict; imports from registry |
| `backend/lib/galaxy/ai/domain_workflow_patterns.py` | modified | AnalysisDomain enum 8→16 members |
| `frontend/server/domain-registry.ts` | **NEW** | TypeScript mirror of canonical domains |
| `frontend/server/galaxy-assistant.ts` | modified | S1 + S2 + S5 + S6 (see above); imports from domain-registry.ts |
| `frontend/server/analyze-intent-uqu.test.ts` | **NEW** | 59 unit tests for intent parsing + S5 completeness |
| `frontend/server/personalization-drug-discovery.test.ts` | **NEW** | 115 unit tests for drug discovery personalization |
| `docs/nextPhase/20260330_LLM_USAGE_AUDIT.md` | **NEW** | Full LLM call site audit with gap analysis |
| `docs/nextPhase/auditing/20260331_SESSION_IMPLEMENTATION_S1_S2_S5_S6.md` | **NEW** | Implementation details for this session's changes |
| `docs/nextPhase/auditing/20260331_DRUG_DISCOVERY_PERSONALIZATION_USE_CASES.md` | **NEW** | 8 use case logs for drug discovery personalization |

---

## What Is Still Not Done (Next Session)

The work above completed S1, S2, S5, S6. The remaining items from the audit:

| Item | What it is |
|------|-----------|
| **S3** | Thread `DomainSpecialistPool` results (Python backend) into `generateResponse()` system prompt — the specialist already runs in parallel but its output is never forwarded to the final response generator |
| **S4** | Step-by-step approval gate for sequential pipelines in `PipelineListView` |
| **Populate DOMAIN_CATALOGS** | Add catalog entries for `genomics`, `cryo_em`, `lab_automation` based on the actual registered workflows in the filesystem |
| **Input dataset visualization** | Preview uploaded/referenced datasets before workflow execution |
| **Large file pagination** | Server-side cursor pagination for CSV/TSV files >500 rows |
