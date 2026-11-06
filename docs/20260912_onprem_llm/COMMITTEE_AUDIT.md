# Committee Audit of the Data Pipeline — code, preprocessing, data quality

**2026-09-18.** Multi-LLM committee (gpt-5.6 OpenAI + gemini-3.8-flash Google + Claude) audited the
on-prem-LLM data pipeline. Every dramatic claim was verified against the raw data before acting.

## Method caveat (important)
The audit brief fed the committee **truncated data samples** (sliced to `[:400]` chars). Both models
(reasonably) flagged the truncation as P0 dataset corruption. Several of their headline findings were
therefore **artifacts of the brief, not the data** — verified false:

| Committee claim | Verification | Verdict |
|---|---|---|
| "gold `spillr`/target not in candidate list" | gold-in-candidates = **0 missing / 4,798 rag rows** | ❌ artifact (brief truncated the candidate list) |
| "`glmsparsenet` egregious mislabel for mass-spec" | full request already has the protein matrix; wants co-expression + survival feature selection → sparse-Cox fits better than the quantification pipeline | ❌ label defensible |
| "no Request span / truncated everywhere" | brief's `[:400]` slice | ❌ artifact |

Lesson: never audit on truncated samples. A cleaner re-run with full records would give a fairer
committee verdict; the confirmed findings below were verified directly regardless.

## Confirmed real findings (acted on)
1. **Request truncation — REAL.** ~26% of routing/param queries (sourced from real study text) were
   clipped mid-sentence (`…haematopoietic precursors in t`). Not from paraphrase — from source-query
   capping. → `validate_sft.py` trims to the last sentence boundary (1,992) or drops the unrecoverable
   (1,900). Root fix (upstream): regenerate those queries from full study text without the char cap.
2. **Param schema-validation gap — REAL, broader than the 170 fractional-ints** (both models' top
   finding). Beyond `nPerm=0.01`: FDR/p-value scale (`fdr=5` vs `0.05`), genome enum informality
   (`hg38`→`GRCh38`), and **conditional/mutually-exclusive params** (`single-end` + `--read2` crashes
   the runner). → `validate_sft.py` now: drops int-named params with fractional values (248 keys),
   `/100` on probability params >1, normalizes genome enums. **Still open:** conditional/mutually-
   exclusive validation (needs the per-workflow schema; add a schema-driven guardrail to the generators).
3. **Code (gpt-5.6): `split_request` docstring vs impl** (`suffix` always `""`) — docstring corrected
   (our formats put structured blocks *before* the request, so `suffix=""` is correct); char-based
   length gate acknowledged; **a pre-training validation gate now exists** (`validate_sft.py`).
4. **"Grounded ≠ correct label"** — valid caution; spot-checks show labels are mostly sound, but they
   are not audited at scale. Follow-up: an LLM-judge pass over a sample of routing labels.

## Open items (my own + committee), not yet done
- **Retriever holdout leakage**: recall@1 0.23→0.77 used a **random** query split → same workflow can
  appear in train and test. Re-measure on a **family/temporal** holdout for an honest number.
- **Paraphrase faithfulness filter**: the "bury in irrelevant context" persona can drown the intent
  (rare). Add a cheap entailment check (does the reworded request still imply the gold?) and drop failures.
- **Upstream truncation fix**: uncap the study-text query source so future regens aren't clipped.
- **Conditional-param schema guardrail** in the generators (not just post-hoc cleaning).

## Result
`validate_sft.py`: **17,265 → 15,254** validated examples. Confirmed defects resolved
(int-fraction params 170→0, truncation handled, genome normalized, rag gold-in-candidates enforced).
This is now the canonical SFT set; the raw enriched set is retained for provenance.
