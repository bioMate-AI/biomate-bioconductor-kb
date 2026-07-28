# Internal Per-Client Model — Experiment 1: Metadata-Mapping Proposer

**Date:** 2026-07-27
**Status:** built + runs end-to-end (CPU, stdlib only); hallucinated-ID rate verified 0.
**Location:** `backend/biomni_workflows/ml_training_examples/metadata_proposer/`
**Depends on:** `docs/20260727_HARMONIZATION_SURVEY.md`,
`docs/20260727_RESOURCE_REGISTRY.md` §8–9,
`nextflow_nfcore/subworkflows/database/metadata_harmonizer/main.nf`,
`ml_training_examples/stratification_adapter/`.

---

## 1. Why this experiment, and why this shape

The harmonization survey (verified, adversarial) established two load-bearing facts:

- **Metadata / clinical-annotation mapping is the field's genuine UNSOLVED
  bottleneck** — not the technical batch-correction layer.
- **LLM-ALONE mapping is unsafe:** ~96% accurate in-dictionary, collapsing to
  **~17% out-of-dictionary** `[UNVERIFIED — specific 96%/17% figures not traced to
  a primary source]`, and it **hallucinates plausible-looking ontology
  IDs** (this hallucination failure is well-documented). Precision varies wildly by ontology.

The survey's prescription: metadata harmonization must be **ontology-grounded +
human-in-the-loop**, and the per-client model must be a **PROPOSER** — it proposes
grounded candidates for human confirmation and **ABSTAINS** rather than ever
emitting an ungrounded ID. This experiment is the first concrete build of that
proposer: a **constrained-decoding** design where the model's entire output space
is `{retrieved candidate IDs} ∪ {ABSTAIN}`, so a hallucinated ID is *structurally
impossible*, not merely discouraged.

This is the L1→L2 per-client play (Ludwig LoRA → vLLM multi-adapter) from the
strategy docs, applied to the metadata use case, reusing the **existing**
`ml_training` engine (the `stratification_adapter` pattern) with a grounding
guarantee bolted on.

---

## 2. What was built

Under `ml_training_examples/metadata_proposer/`:

| Component | File | Role |
|---|---|---|
| **Bootstrap builder** | `build_bootstrap.py` | Hand-encoded realistic seed: free-text→canonical pairs with **real EFO/Mondo/HPO/CL IDs**, plus explicit OOD negatives that must ABSTAIN. Emits `ontology_seed.csv`, `train.jsonl`, `eval.jsonl`, and LoRA `instructions_{train,eval}.jsonl`. |
| **Constrained decoder** | `constrained_decoder.py` | `Retriever` (deterministic grounded shortlist over the seed dictionary) + `Proposer` (SELECT-or-ABSTAIN ranker). CPU, no GPU, no network. `llm_select_from_candidates` = the LLM drop-in that parses `SELECT <n>`/`ABSTAIN` and maps back to a grounded ID. |
| **OOD evaluation** | `evaluate.py` | Reports in-dict accuracy, OOD abstention rate, hallucinated-ID rate; writes `eval_metrics.json`; exits non-zero if the invariant is violated. |
| **Ludwig config (GPU drop-in)** | `ludwig_llm_config.yaml` | `model_type: llm` LoRA config mirroring `stratification_adapter/`; trains on the instruction rows; the SELECT/ABSTAIN objective never emits a raw ID. |
| **README** | `README.md` | Design, run instructions, LLM upgrade path, next-data plan. |

### The seed
28 ontology terms with **real, stable IDs** — Mondo diseases (`MONDO:0008383`
rheumatoid arthritis, `MONDO:0007915` SLE, `MONDO:0005011` Crohn disease, …),
Cell Ontology cell types (`CL:0000624` CD4+ T cell, `CL:2000001` PBMC, …), HPO
phenotypes (`HP:0002960` Autoimmunity, `HP:0002829` Arthralgia, …). 63 messy
free-text in-dictionary inputs (`"RA"`, `"rheumatoid arth."`, `"CD4+ T cell"`,
`"peripheral blood mononuclear cells"`, plurals, casing, typos) and 18
out-of-dictionary negatives (clinical prose, assay codes, administrative labels,
novel endotype names) that have **no correct term in the seed** and must ABSTAIN.

---

## 3. The core invariant (why 0 hallucinated IDs is structural)

```
input ──► Retriever (deterministic match over ontology_seed.csv) ──► grounded shortlist  (or []  ⇒ OOD)
                                                                          │
                        Proposer:  SELECT top (if it clears the accept margin) ─┐  output ∈ {retrieved IDs} ∪ {ABSTAIN}
                                   else ABSTAIN                                 ─┘  ⇒ ungrounded ID impossible
```

Every candidate ID is copied verbatim from the ontology seed. The proposer can
only SELECT a candidate or ABSTAIN; on ABSTAIN it emits **no ID at all**. There is
no code path that constructs an ID string. When the LLM replaces the ranker, its
`SELECT <n>` is parsed and `<n>` is mapped back to a retrieved candidate — an
out-of-range or unparsable answer degrades to ABSTAIN. So the guarantee survives
the LLM upgrade.

---

## 4. Eval results (verified, this seed)

**Held-out eval split (24 rows: 19 in-dict, 5 OOD):**

| Metric | Value |
|---|---|
| In-dictionary accuracy | **100.0%** (19/19 correct SELECT of gold) |
| In-dict SELECT precision | 100.0% (19/19) |
| OOD abstention rate | **100.0%** (5/5) |
| OOD leakage (emitted an ID for an OOD row) | **0** |
| **Hallucinated-ID rate** | **0.0%** (0/19 emitted IDs off-ontology) |

**Full-dataset stress test (all 81 rows, harder abbreviations included):**

| Metric | Value |
|---|---|
| In-dictionary accuracy | **96.8%** (61/63) |
| OOD abstention rate | **100.0%** (18/18) |
| OOD leakage | **0** |
| **Hallucinated-ID rate** | **0.0%** (0/61 emitted IDs) |

The 2 full-dataset misses (`"rheum. arthritis"`, `"rheumatoid arth."`) **ABSTAIN
rather than mis-map** — the safe, human-review failure mode. This ~97% in-dict /
100% OOD-abstention / **0-hallucination** profile is exactly the survey-adjusted
target: it recovers the in-dictionary accuracy an LLM would give while eliminating
the 17%-OOD/hallucinated-ID failure that makes LLM-alone mapping unusable.

`evaluate.py` writes `eval_metrics.json` and returns non-zero if any hallucinated
ID or OOD leakage ever appears — so this invariant is enforced, not just observed.

---

## 5. How the LLM upgrade slots in (CPU baseline → per-client LoRA → vLLM)

The deterministic ranker is the **CPU baseline / oracle-of-record**. The per-client
model is a **drop-in for the decision step only**, keeping the grounding contract:

1. **Data already emitted.** `build_bootstrap.py` renders every row as
   `{instruction, output}` where the instruction is the value **plus its retrieved
   candidate list** and the output is `SELECT <n>` / `ABSTAIN` — never a raw ID.
   (This is where the LoRA can *beat* the baseline: the abbreviation cases the
   deterministic ranker abstains on are labeled `SELECT <n>` when the correct term
   was retrieved, so the adapter learns the client's shorthand while staying
   grounded.)
2. **Train (L2) — existing engine.** Fine-tune a LoRA through the **existing**
   `galaxy.ai.ml_training` `ludwig_llm` path (`ludwig_llm_config.yaml`, same module
   as `stratification_adapter`). One **isolated AWS Batch run per client**, on that
   client's private reviewed-mapping history only → **one LoRA weight file**,
   MLflow-tracked. QLoRA (`adapter: qlora`, `quantization_bits: 4`) routes to the
   GPU queue for a larger base.
3. **Serve — vLLM multi-adapter.** `infra/vllm` runs one shared frozen base and
   multiplexes many client LoRA adapters (`sync-adapters.sh`: S3→EFS + rolling ASG
   refresh). Each client gets a private, domain-adapted proposer **without a
   dedicated GPU**.
4. **Constrained at inference.** `constrained_decoder.llm_select_from_candidates`
   parses the adapter's answer; only a `SELECT <n>` pointing at a retrieved
   candidate is honored, mapped back to that candidate's real `term_id`. Everything
   else → ABSTAIN.

**Isolation / IP.** Structural: one run, one data source, one adapter; no shared
corpus across clients. IRB-locked data uses the L4 federated path (train
client-side, share only weight deltas). The regulated ranking/gate layer stays
transparent and un-trained; this adapter is **advisory** — it proposes, a curator
confirms. This is defensible precisely because it is built on data no competitor
holds: the client's own reviewed mappings.

### Relationship to the production Nextflow harmonizer
`metadata_harmonizer/main.nf` is the deterministic production grounding layer
(exact→synonym→token→fuzzy, ontology-grounded, human-in-the-loop, no ID invention).
This experiment is its **per-client learned upgrade**: same no-hallucination
contract, but the SELECT/ABSTAIN decision becomes a client-adapted LoRA instead of
a fixed threshold — raising recall on the client's messy vocabulary without
relaxing the guarantee. The `Retriever` reuses the `.nf` cascade's matching idea as
the constrained-decoding candidate generator.

---

## 6. What real bootstrap data to use next

The 28-term hand seed is a demonstration. To scale, replace the hand-encoded
`ONTOLOGY_SEED` + `IN_DICT` in `build_bootstrap.py` with:

1. **`text2term` over full EFO + Mondo (+ HPO + CL + UBERON)** (Registry §8) to
   build the real candidate dictionary and generate high-confidence
   `{free-text → term_id}` silver labels — `text2term` mappings above a confidence
   cutoff are the in-dictionary positives; the same ontologies feed the retriever.
2. **Real OOD negatives** from client free-text (clinical notes, assay/instrument
   codes, administrative and novel-endotype labels) that `text2term` maps *below*
   the cutoff → the ABSTAIN training signal.
3. **The client's reviewed history** (accepted SELECTs + confirmed ABSTAINs) from
   the L1 RAG + human-review loop → the L2 fine-tune corpus (the moat data).

`evaluate.py` is unchanged across all of these — it reports the same three metrics
and enforces hallucinated-ID = 0 against whatever seed/split is present.

---

## 7. Bottom line

Experiment 1 delivers the survey's prescription as running code: a grounded,
abstaining, constrained-decoding metadata proposer with **0 hallucinated IDs by
construction and verified empirically** (0/61 emitted IDs off-ontology), 96.8%
in-dict accuracy, and 100% OOD abstention on the seed. It reuses BioMate's existing
`ml_training` + vLLM engine (the `stratification_adapter` pattern), so the
per-client LoRA is a drop-in that raises accuracy on a client's vocabulary without
ever gaining the ability to invent an ontology ID. Next step is swapping the hand
seed for `text2term`-over-full-EFO/Mondo silver labels and wiring the client
reviewed-history corpus as the L2 training set.
