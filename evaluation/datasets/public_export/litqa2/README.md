# LitQA2 — literature-retrieval task (RealBio task #9)

Measures the capability our workflow/knowledge tasks don't: **retrieve a specific finding
from the full-text literature and answer without confabulating.** LitQA2 questions have
answers attested *once* in 2021–24 papers and **not** answerable from abstracts or
parametric memory — so a model that can't retrieve must either abstain or guess.

## Systems under test
- **C0 — Bare LLM** (`run_baseline.py litqa2 --model ...`): answers the MCQ from parametric
  knowledge, no retrieval. The floor.
- **BioMate** (`run_biomate.py`): full retrieval pipeline (`research_query` on dev).
- **PaperQA2** (`run_paperqa2.py`): the SOTA open baseline (FutureHouse, Apache-2.0), the
  system LitQA2 was designed to report. `pip install paper-qa>=5`.

## Two conditions (report both — never conflate; see 20260805_REALBIO_EVALUATION_PROTOCOL.md)
| Condition | Setup | Isolates |
|---|---|---|
| **equal-info** | every system given the SAME candidate paper set (the LitQA2 gold sources) | synthesis/grounding quality |
| **live** | each retrieves live with its own stack (BioMate: PubMed+EPMC+S2+OpenAlex; PaperQA2: S2/Crossref/OpenAlex/Unpaywall) | the shipped pipeline |

**Caveat:** PaperQA2 was tuned on LitQA2 (home-field). Report LitQA2 **and** a neutral
held-out set (`held_out/` — NCBI-verified evidence-review queries incl. the PEX one) where
neither system is tuned. That's where the comparison is honest.

## Two scoring axes (score.py `score_litqa2` + citation_veracity.py)
1. **Accuracy** — MCQ exact-match vs `ideal`, with Wilson 95% CI. Report **precision**
   (correct / answered) and **coverage** (answered / total) separately — abstaining via
   "Insufficient information" is not wrong, and the anti-confab guard should raise coverage-
   quality by abstaining instead of fabricating.
2. **Citation veracity** (`confabulation_rate`) — every emitted PMID/DOI resolved against
   NCBI/Crossref; `mismatched`+`unresolvable` = fabricated. This is the axis the confabulation
   fix moves (PEX: 1.0 → 0.0). Accuracy can't see it; this can.

## Run
```
# 1. data
python3 load_litqa2.py              # -> litqa2/data.jsonl (+ held_out/ from our verified set)
# 2. systems (each writes results/<system>/litqa2.jsonl in the shared prediction format)
python3 ../run_baseline.py litqa2 --model gpt-5.6            # C0 bare
python3 run_biomate.py   --base https://dev-public.biomate.ai
python3 run_paperqa2.py  --papers ./corpus                   # equal-info; omit for live
# 3. score (both axes)
python3 ../score.py litqa2 results/<system>/litqa2.jsonl
python3 citation_veracity.py results/<system>/litqa2.jsonl
```

## Prediction format (shared across all systems)
```
{"id": "...", "prediction": {"answer": "<chosen option text>"},
 "citations": [{"title": "...", "pmid": "...", "doi": "..."}]}
```
`answer` is scored for accuracy; `citations` for veracity. A system that abstains sets
`answer` to the "Insufficient information to answer the question" option.
