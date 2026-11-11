# Spec: entity-claim validation for grounded answers (2026-11-11)

## Problem
Grounded answers assert biomedical entities — variants, genes, compounds, structures —
that can be **fabricated or mis-extracted**. The LRRK2→Parkinson's answer led with three
non-existent pathogenic variants (`p.Cys2024Arg`, `p.Ala733Glu`, `p.Thr475Ala`), demoted
the established ones (`G2019S`, `R1441C/G/H`, `Y1699C`, `I2020T`), and conflated Mendelian
mutations with Asian population risk variants (`G2385R`, `R1628P`). Nothing validates the
asserted entities against an authoritative database before they reach the user, so a
confident fabrication ships — the failure mode that most damages credibility with a
domain clinician.

## Principle: validate the LLM's own claims against the authoritative source
- The goal is to validate **what the answer claimed**, against the authoritative DB for
  that fact type. **Validation — not extraction — is where ground truth enters.**
- **The LLM self-extracts its claims.** It is context-aware (it knows `G2019S` is a LRRK2
  variant and that it asserted `p.Cys2024Arg`) and emits each entity *with its type*. A
  separate NER (PubTator3/BERN2) would re-annotate the raw text and validate the *wrong*
  set, plus add a dependency; regex extraction is too ad-hoc (misses notation variants).
  So: no NER, no regex — the LLM lists exactly what it claimed.
- The external DB (ClinVar for variants, ChEMBL for bioactivity, PDB for structures …)
  supplies the ground truth that fails fabrications.

## Design (reuse-first — what exists vs. what's new)

### Step 1 — LLM self-extracts claimed entities  *(NEW: prompt + schema)*
Extend the synthesis prompt (`research_agent._build_synthesis_prompt` /
`_synthesize_response`) to emit a structured block beside the existing
`EVIDENCE: addresses|insufficient` line:
```
CLAIMS: [{"text":"G2019S","type":"variant","subject":"LRRK2"},
         {"text":"p.Cys2024Arg","type":"variant","subject":"LRRK2"}, …]
```
Types align with the registry (`gene / variant / compound / structure / disease /
pathway`). Parse with a `_split_claims` helper (parallel to `_split_evidence_verdict`),
fail-soft (no block → no validation), bounded (≤~20 checkable assertions; skip prose).

### Step 2 — Route each claim to its validation source  *(REUSE: `ENTITY_SOURCES`)*
`federated_query.ENTITY_SOURCES` **already is** the fact-type → authoritative-source map:
`variant → dbsnp, clinvar, gnomad` · `compound → chembl, pubchem, chebi` ·
`structure → pdb, alphafold` · `gene → ncbi_gene, ensembl, uniprot` ·
`disease → hpo, clinvar, clinicaltrials`. That is the "validation skill" — declarative,
registry-grounded, already present (and `evidence_source_router` encodes the same table
for retrieval). Pick the primary validation source for the type.

### Step 3 — Validate via existing handlers  *(REUSE)*
- variant/gene → `lookup_clinvar_gene(subject)` (research_agent.py:676) then check the
  claimed variant appears (ClinVar esearch by gene+variant; **measured 0.24 s**).
- compound → `query_database('chembl', …)`; structure → `query_database('pdb', …)`.
- Redis-cached, sub-second, non-fatal on network error.

### Step 4 — Label unconfirmed claims  *(REUSE: `citation_check` pattern)*
Apply `citation_check`'s status taxonomy to entities:
- `verified` — present in the authoritative source → no change.
- `not_found` — queried, absent → label **"reported-but-unconfirmed (not found in
  ClinVar)"**; never presented as established.
- `unverified` — could not check (network/registry error) → **"unverified (could not
  check)"**; never silently "verified".
Prefer a **validation footnote** listing each claim's status (+ ClinVar clinical
significance so a *risk factor* like `G2385R` is not shown as a Mendelian mutation) over
rewriting prose inline.

## Confidence interplay
`not_found` claims must **lower** `_grounding_confidence` (a confident fabrication is the
worst case): feed the `not_found` count in as a penalty so the fabricated-variant answer
reads "limited", not "reasonable".

## Scope boundaries (what this does NOT do)
- Not retrieval re-ranking / recency fix (separate: hybrid BM25+dense + temporal overlay).
- Not the evidence-hierarchy scaffold (separate: the "what is the evidence" tier template).
- Not general NER — only validates the LLM's own typed claims.

## Reuse inventory
| Piece | Status |
|---|---|
| fact-type → validation-source map | **EXISTS** — `federated_query.ENTITY_SOURCES` |
| ClinVar lookup | **EXISTS** — `lookup_clinvar_gene` |
| ChEMBL/PDB/etc. lookups | **EXIST** — `query_database` handlers |
| verified/unverified/not_found labeling | **EXISTS** — `citation_check` (extend to entities) |
| intent → source (retrieval) | **EXISTS** — `evidence_source_router` |
| **NEW** | `CLAIMS:` prompt+schema · `_split_claims` · the validation glue · the confidence penalty |

## Integration + flags
In `_synthesize_response`, after `_split_evidence_verdict` + citation grounding, before
`_ensure_evidence_boundary`. **Flag-gated + inert by default** (`BIOMATE_ENTITY_VALIDATION=1`),
non-fatal, cached — same pattern as the federated fan-out and target-ranking.

## Open questions
- Variant-notation normalization for the ClinVar query (HGVS `p.`/`c.` vs legacy
  `G2019S`) — ClinVar esearch is tolerant but may need two query forms.
- Carry ClinVar **clinical significance** in the label (pathogenic vs risk-factor vs
  benign), so population risk variants aren't rendered as penetrant mutations.
- Footnote vs inline caveat rendering (UX).

## Latency (speed checked)
ClinVar esearch **0.24 s**; PubTator3 (not needed) 0.24 s; cacheable; full NER avoided.
