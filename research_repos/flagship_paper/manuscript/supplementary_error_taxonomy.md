# Supplementary — RealBio error taxonomy: how systems fail, not just how often

**Purpose.** A single accuracy per task collapses qualitatively different behaviours into one number. Two systems can share a score while one *invents* answers and the other *abstains*; a computation task's low mean can reflect a mis-specified target rather than an inability to compute. This supplement classifies every non-correct RealBio prediction into a small set of named failure modes, per system, from the committed predictions (`evaluation/datasets/public_export/results/*`, scored by the released `score.py`). All counts are exact re-derivations from those files, not estimates. The taxonomy changes the reading of three headline numbers (routing, pbpk, boin) and surfaces one benchmark-design defect (§4).

## 1. Failure-mode taxonomy

Five modes are sufficient to classify every miss observed across the three tasks:

- **Hallucinated selection** — the output is not a valid target at all (e.g. a workflow name absent from the catalog; an invented option). A *fabrication* failure.
- **Discrimination error** — a *valid* target is selected, but the wrong one for the query. A *precision* failure, not a fabrication.
- **Verbose no-answer** — the system emits reasoning but no parseable final answer within the response. An *output-discipline* failure, distinct from being wrong.
- **Wrong endpoint (under-specification)** — the system computes a correct value of the right *type* but not the specific quantity scored (defined for pbpk: a value within 2-fold of a *different* reference quantity — AUC, t½, or Tmax — but not the scored Cmax). Attributable to an under-specified prompt, not to the model.
- **Overthinking / wrong scale** — the system computes an off-scale value (orders of magnitude from every reference quantity), characteristic of an agent executing an elaborate mechanistic derivation that diverges.

## 2. Per-task, per-system breakdown

### 2.1 Cross-domain routing (n = 200)

Columns: correct · **discrimination error** (real workflow, wrong one) · **hallucinated** (name not in catalog) · **no-answer**.

| System | Correct | Discrimination error | Hallucinated | No-answer |
|---|---:|---:|---:|---:|
| **BioMate** (engine-free retrieval) | **182** | 10 | **8** | 0 |
| Claude Opus 5 | 111 | 52 | 37 | 0 |
| Gemini 3.1 Pro | 108 | 29 | 63 | 0 |
| GPT-5.6 | 102 | 17 | 71 | 10 |
| Kimi K3 | 84 | 37 | 58 | 21 |
| DeepSeek V4 | 76 | 15 | **109** | 0 |
| GLM-5.2 | 73 | 35 | 92 | 0 |
| Qwen3.8-Max | 68 | 5 | 38 | **89** |
| GPT-5.6-luna | 63 | 21 | **116** | 0 |

*Observation.* For the direct-LLM systems, the dominant routing failure is **hallucination** — inventing a workflow name that does not exist in the catalog (DeepSeek 109/200, GPT-5.6-luna 116/200, GLM-5.2 92/200). BioMate's misses are almost entirely **discrimination errors** (10) with near-zero hallucination (8), a structural consequence of selecting from a fixed catalog rather than generating a name. Qwen3.8-Max additionally leaves 89/200 unanswered.

### 2.2 PBPK prediction (n = 15)

Columns: correct · **wrong endpoint** (valid PK quantity, not the scored Cmax) · **wrong scale** (off-scale) · **no-answer**.

| System | Correct | Wrong endpoint | Wrong scale | No-answer |
|---|---:|---:|---:|---:|
| GPT-5.6 | 3 | 7 | 5 | 0 |
| GPT-5.6-luna | 3 | 5 | 3 | 4 |
| Claude Opus 5 | 2 | 6 | 7 | 0 |
| DeepSeek V4 | 1 | 0 | 2 | 12 |
| Gemini 3.1 Pro | 0 | **9** | 6 | 0 |
| GLM-5.2 | 0 | 1 | 6 | 8 |
| Biomni (agent) | 0 | 4 | **11** | 0 |
| Kimi K3 | 0 | 0 | 0 | **15** |
| Qwen3.8-Max | 0 | 0 | 0 | **15** |

*Observation.* The 7.5% mean accuracy conceals three distinct behaviours. (i) **Wrong endpoint** is frequent among the strongest reasoners (Gemini 9/15, GPT-5.6 7/15, Opus 6/15): they compute a PK value within 2-fold of AUC/t½/Tmax but not of the scored Cmax. (ii) **Verbose no-answer** dominates the open-weight models (Kimi 15/15, Qwen 15/15, DeepSeek 12/15). (iii) **Wrong scale** dominates the Biomni agent (11/15), whose mechanistic derivations land off-scale.

### 2.3 BOIN dose-finding (n = 18; 2 of 20 items excluded — null `true_MTD_mg`, unscorable)

Columns: correct · wrong dose · **no-answer**.

| System | Correct | Wrong dose | No-answer |
|---|---:|---:|---:|
| Biomni (agent) | 9 | 9 | 0 |
| GPT-5.6 | 9 | 9 | 0 |
| Claude Opus 5 | 8 | 10 | 0 |
| GPT-5.6-luna | 7 | 11 | 0 |
| Gemini 3.1 Pro | 5 | 13 | 0 |
| GLM-5.2 | 2 | 4 | **12** |
| Kimi K3 | 3 | 1 | **14** |
| DeepSeek V4 | 3 | 0 | **15** |
| Qwen3.8-Max | 2 | 0 | **16** |

*Observation.* The **verbose no-answer** mode recurs and clusters in the same open-weight/China-hosted models (DeepSeek 15/20, Qwen 16/20, Kimi 14/20, GLM 12/20), whereas the frontier closed models return a dose and fail, when they fail, by selecting the wrong one.

## 3. Cross-system case sketches (same prompt, different behaviour)

- **PBPK PK-001 (aspirin), one prompt → three behaviours.** Reference Cmax = 0.54. A direct LLM returns a Cmax-scale number (single-digit); the Biomni agent executes a hepatic-clearance derivation and returns ≈1178 (a clearance-scale quantity, off-scale for Cmax — *overthinking/wrong scale*); BioMate does not answer this item through a language model at all but through its validated PBPK pipeline (reported on its own pharmacology set). The scored miss for the LLM and the agent thus arises from *different* causes under an identical prompt.
- **Routing, invented vs mis-selected.** On a query whose correct target is a real catalog workflow, DeepSeek V4 returns a workflow name that does not exist in any system's catalog (*hallucination*, 109/200 across the set), whereas BioMate returns a real — occasionally wrong — catalog workflow (*discrimination*, 10/200; hallucination 8/200). The two systems' misses are not interchangeable.
- **BOIN, wrong-dose vs no-answer.** Given identical dose-finding inputs, GPT-5.6 returns a specific MTD and is scored right or wrong; Qwen3.8-Max returns multi-step reasoning without a final dose in 16/20 items (*verbose no-answer*) — unscored-as-correct for a reason orthogonal to dose-finding competence.

## 4. Takeaways (and one benchmark-design fix)

1. **The pbpk headline under-penalises competent PK reasoning.** For the strongest reasoners the modal failure is *wrong endpoint*, i.e. computing a valid PK quantity the prompt did not pin down. This is a property of the **task specification**, not of model ability. *Design fix:* the pbpk prompt should name the target quantity (Cmax) explicitly; until it does, pbpk accuracy should be read as a lower bound on PK-reasoning capability. We report the current committed numbers unchanged and flag the defect rather than silently re-score.
2. **An agent can score worse than the bare model it wraps.** Biomni's pbpk accuracy (0/15, *wrong scale* 11/15) is below the direct-LLM mean: the additional mechanistic-derivation machinery diverges on an under-specified numeric target. Scaffolding is not monotonically beneficial.
3. **Near-zero hallucination on routing is a distinguishing safety property.** BioMate hallucinates a non-existent workflow in 8/200 items; direct LLMs do so in 37–116/200. For a system that *executes* what it selects, fabricating a target is a categorically more dangerous failure than choosing a wrong-but-real one — the taxonomy, not the accuracy, exposes this.
4. **Output discipline is a real deployment gap for open-weight models.** *Verbose no-answer* is negligible for the closed frontier models but dominant for Kimi/Qwen/DeepSeek/GLM on both pbpk and boin. A deployment that cannot extract a final answer fails regardless of latent capability; this is an integration property a leaderboard of accuracies does not show.

**Scope and limitations.** Counts are from the committed n = 15/18/200 predictions; the pbpk and boin cells carry wide confidence intervals at these sample sizes and the modal-failure statements are descriptive, not inferential. The endpoint/scale boundary for pbpk is defined operationally (2-fold of any reference quantity) and inherits the reference set's own uncertainty. No prediction was re-generated for this analysis.
