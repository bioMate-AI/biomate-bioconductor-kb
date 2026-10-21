# Pharma-Chemist Experience KB — audit + unified design

**Date:** 2026-10-21 · Scope: consolidate the scattered experiential-knowledge assets that encode medicinal-chemist / radiopharmacy experience (metal coordination, pharmacophore, SAR/liabilities, selectivity, FTO) into one **provenance-tiered Experience KB** that drives **tool parameters** and **evaluation criteria** — via the existing hybrid rule+LLM path and BioMate's existing storage. **Audit-first: the pieces exist; this unifies them, it does not rebuild them.**

---

## 1. How it's done now — AUDIT (what's already encoded, where, how used)

The experience layer is real but **scattered across `research/guangzhou_all_atom/cyclic_llm/` (research-side, cyclic-program-local)**. It already drives BOTH tool params and eval criteria. Inventory (all file paths real):

| Asset | File | Experience encoded | Sets tool params? | Sets eval criteria? | Provenance today |
|---|---|---|---|---|---|
| **Target KB** (20+ targets: avb6, pdl1, a4b7, a4b1, lfa1, c5, fcrn, baff, cd40, il2ra, tnfa, il17a/f, il23, il6r, cd20) | `cyclic_llm/target_kb/*.json` | mechanism (epitope/motif/metal/site), pharmacophore_hint, counter_targets, controls+measured affinity, FTO patent/genus, actives/non-actives, `cofactors`, receptor | **yes** (via `target_spec`) | **yes** (via `scorer_config`) | **partial** — affinity values, FTO patent (CA2998968A1), some refs; **no uniform tier** |
| **Generic engine** | `cyclic_llm/target_spec.py` | DATA→config: `cofactors` (metal = just this, 0..n CCDs), epitope→pose table, motif→scaffold mode, counter/controls | **YES** (cofold ligands, pose method, scaffold mode) | — | engine; notes its spec row "belongs in BioMate's workflow DB so the engine runs through the product" |
| **Pharmacophore gate** | `cyclic_llm/pharmacophore_knowledge.py` | per-target `required_motifs`/`required_residues`/`preferred_regex`/`conformational_lock` (e.g. αvβ6 RGD + RGDLxxL/I + dPro+NMe; pdl1 discontinuous→structure-gated) | **yes** (generation CONSTRAINT contract) | **YES** (hard gate: reject mechanism-dead, e.g. 0/12 RGD) | literature refs (Trivehexin, avebehexin, WL12/dmp10) |
| **Liability / SAR** | `cyclic_llm/knowledge_liability_flags.py` | CMC (deamidation N-G/N-S…, Asp-isomerisation D-G/D-P, Met/Cys/Trp oxidation), αvβ6 radioligand SAR (β6-selectivity needs extended RGDLxx[L/I]; **renal dose ↑ with net cationic charge**; dPro+NMe lock), PD-L1 aggregation/solubility | indirectly | **YES** (hard/soft flag → HOLD/re-rank **before** a GPU-hour of docking) | cites knowledge (textbook + A20FMDV2/Trivehexin); zero-compute, rule-exact |
| **Mechanism-matched scorer** | `cyclic_llm/scorer_config.py` | reads KB `mechanism` → physics scoring rules | **YES** (metal retained+parameterized in cofold/MM-GBSA) | **YES** (metal-free MIDAS run = mechanism-NON-COMPLIANT → ΔG **void**; pose by epitope; counter-targets for selectivity) | derived from KB mechanism |
| **Acceptance gate** | `cyclic_llm/acceptance_gate.py` (+ `acceptance_criteria.yaml`, "Candidate Design Requirements v1.0/1.1") | H1 RGD, H2 RGDL, H3 turn+N-methyl, H4 aromatic flanks (canon+ncAA), H5 single-Lys handle, H8 FTO-genus | — | **YES** (hard accept gates; ncAA-aware) | the acceptance-criteria doc |
| **Rule induction (SNG)** | `cyclic_llm/rule_induction.py` + `target_kb/{avb6,pdl1}_induced_rule.json` | LEARNED design spec (greedy discriminative conjunction over peptide predicates) from a target's actives/non-actives | — | **YES** (induced H gate) | learned-from-data (evidence = the actives) |
| **FTO / novelty** | `cyclic_llm/fto_score.py`, `drug_novelty_fto.py` | patent claim-genus membership + novelty Tanimoto to known compounds | — | **YES** (drop/flag patent-occupied genus) | patent cited (e.g. CA2998968A1) |
| **Metal force field** | `fep/forcefield/cada_mn.itp` (+ `cada_mn_vsite.itp`), `metal_mmgbsa_prep.py`, `fep/validate_cada_itp.py` | CaDA octahedral Mn²⁺ FF params | **YES** (FF for cofold/MM-GBSA/FEP) | — | **EXCELLENT — exemplar**: Duarte 2014 *JPCB* Table 1 verbatim, unit conversions shown inline, explicit "INPUT to validation, not a validated artifact" / audit-before-spend |
| **Provenance pattern to reuse** | `grounded-prototype/` + `docs/20261014_GROUNDED_STANDARDS_ASSISTANT.md` | evidence-TIERED answers with provenance + isolation + honest boundaries | — | — | the tiering model to adopt wholesale |

**Verdict on "how it's done now":** experience is encoded as **per-target DATA (`target_kb/*.json`) + deterministic rule modules**, consumed by the **design loop** (params via `target_spec`: cofactors/metal, pose, scaffold; constraints via `pharmacophore_knowledge`) and the **eval** (`scorer_config` metal-compliance, `pharmacophore`/`liability`/`acceptance` gates, `fto`). `cada_mn.itp` is the **provenance exemplar** (verbatim source + verify-before-spend). It genuinely works — αvβ6's metal/pharmacophore/selectivity/FTO all flow from data, not hard-code.

**The real gaps (what is NOT done):**
1. **No single entry schema** — the {constraint → params + eval} mapping is split across 5 modules, each reading the KB its own way.
2. **Inconsistent provenance** — `cada_mn.itp` is exemplary; most KB fields have no uniform evidence-tier (chemist-judgment vs literature vs induced vs regulatory).
3. **Not in the product** — it's cyclic-program-local, not in BioMate's workflow DB / search; `target_spec` itself flags that the spec row belongs there.
4. **Not chemist-editable / versioned** — it's Python dicts + loose JSON, not a living, authored, versioned store.
5. **Tool-enrichment gap** (memory: 10k+ Galaxy tools lack `scientific_context_v2`) — the KB does not yet feed tool param defaults platform-wide.

---

## 2. DESIGN — unified Pharma-Chemist Experience KB

### 2.1 Entry schema (one schema, superset of all the above)
```yaml
experience_entry:
  id: avb6.metal.cada_mn
  scope:
    modality: [cyclic_peptide, peptide]         # or small_molecule, …
    target_class: RGD-integrin-MIDAS            # class-level reuse
    applies_when: "cofactors has MN at MIDAS"   # predicate over the target spec (deterministic)
  kind: metal-coordination | pharmacophore | liability-SAR
       | modality-heuristic | fto-selectivity | gate-threshold
  statement: "Mn2+ at the integrin β-I MIDAS must be retained and octahedrally
              parameterized; a metal-free run is mechanism-void."
  provenance:
    source_type: chemist | paper | induced | regulatory
    ref: "Duarte 2014 JPCB 118:4351 Table 1"    # DOI/patent/chemist-id/induced-rule-id
    evidence_tier: T1-established | T2-literature | T3-chemist-judgment | T4-induced
  effects:
    tool_params:                                # drives the TOOLS
      - {tool: cofold,   param: ligands,   value: "cofactors:MN*n"}
      - {tool: mmgbsa,   param: forcefield, value: "fep/forcefield/cada_mn.itp"}
      - {tool: fep,      param: metal_model, value: "CaDA-Mn (vsite preferred)"}
    eval_criteria:                              # drives the EVAL / QC gates
      - {gate: metal_retained, condition: "MN present in complex", severity: hard}
      - {metric: ddG_admissible, condition: "controls cluster (A2)", severity: hard}
  status: active
  version: 1
  last_edited_by: "<chemist>"
```
Every row the audit found maps onto this: metal→`tool_params`; pharmacophore/liability/acceptance/FTO→`eval_criteria` (± generation `constraints`). The schema's novelty is the **explicit, auditable {statement → params + eval} link with a provenance tier** — nothing in §1 carries all three uniformly.

### 2.2 Wiring — hybrid rule + LLM, feeding BOTH loop and eval
- **Deterministic (rules first).** For a `DesignCampaign` on target T, `experience_kb.resolve(T)` returns all entries whose `applies_when` fires, and:
  - **→ tool params:** merges `effects.tool_params` into the run config. `target_spec` already does this for cofactors/pose/scaffold; the KB extends it to the **metal model/FF** and **liability-derived generation constraints**. (e.g. *αvβ6 ⇒ metal=CaDA-Mn, cofold ligands=[MN×3], pharmacophore=RGD required / RGDLxxL preferred, selectivity counter-screen=αvβ3/β5/β8/α5β1, net-cationic-charge penalty*.)
  - **→ eval criteria:** assembles the QC-gate set (pharmacophore hard gate + liability flags + acceptance H-gates + metal-compliance + FTO drop) as the campaign's accept/advisory gates. One KB resolve → both proposal constraints and QC.
- **LLM (fallback for fuzzy/novel).** For an under-specified or un-encoded target, RAG-retrieve the nearest KB entries (by target_class/modality) as context; the LLM proposes params/criteria; **validate every proposed value against the schema's allowed set** (the program's existing rules-first-LLM-fallback + guardrail pattern). Never silently pass an un-encoded target — mirror `pharmacophore_knowledge`'s refusal.

### 2.3 Extensibility (living, versioned, provenance-tracked — reuse existing infra)
- Store entries in BioMate's **existing** store, not a new DB: the `target_kb/` JSON convention promoted into the **workflow DB** (`backend/database/galaxy_ai_tools.db`) + the existing Unified/Vector search infra for RAG retrieval. A chemist adds/edits an entry via the same path a workflow is registered; versioned (`version`, `last_edited_by`, `status: active|deprecated`).
- **Provenance/isolation** reuses the Grounded Standards Assistant model: every entry carries an evidence tier; T3-chemist-judgment entries are flagged as such and never presented as established fact; deprecations are retained, not deleted.

---

## 3. CONSOLIDATION PLAN — first slice (wrap, don't rewrite)

1. **Schema + loader (new, small):** `experience_kb.py` — defines the entry schema and **adapters** that read the EXISTING assets as entries: `target_kb/*.json` (spec rows), `pharmacophore_knowledge.PHARMACOPHORE`, `knowledge_liability_flags` rule families, `acceptance_gate` H-gates, `fto_score` genus, `cada_mn.itp` metal params, `*_induced_rule.json`. Each wrapped with the provenance/tier envelope. **No rule logic rewritten** — the modules stay the executors; the KB is the registry + provenance layer over them.
2. **First migrated entries (concrete, αvβ6):**
   - `avb6.metal.cada_mn` — T1 (Duarte 2014) → tool_params (cofold MN×3, FF cada_mn.itp, FEP CaDA).
   - `avb6.pharmacophore.rgd` — T2 (Trivehexin/avebehexin) → eval hard gate (RGD required, RGDLxxL preferred) + generation constraint.
   - `avb6.sar.b6_selectivity` — T2 (A20FMDV2) → eval (extended-motif required else "pan-RGD, β6 unconfirmed") + counter-screen αvβ3/β5/β8/α5β1.
   - `avb6.sar.renal_cationic` — T2 → eval advisory (net-cationic-charge penalty; kidney dose-limiting).
   - `mechanism.metal_free_void` — T1 → eval hard (metal-free MIDAS ΔG void; from `scorer_config`).
   - `avb6.fto.ca2998968a1` — T1-patent → eval drop (occupied genus).
   - CMC universal (deamidation/isomerisation/oxidation) — T1 → eval soft flags (from `knowledge_liability_flags`).
3. **Wire `resolve(T)`** into (a) the `DesignCampaign` param assembly and (b) the eval gate assembly, replacing each consumer's bespoke KB read with the one resolver (back-compat: consumers can keep their APIs as thin views, exactly as `scorer_config` is already "a view over `target_spec`").
4. **Register in the workflow DB** so the loop + eval run it through the product; expose a minimal chemist add/edit entry.
5. **Tool-enrichment tie-in:** entries whose `effects.tool_params` touch a catalog tool populate that tool's `scientific_context_v2` default — the KB becomes the source of experience-grounded param defaults platform-wide (addresses the enrichment gap).

---

## 4. Honest: new vs existing
- **Already exists (≈70%):** the per-target DATA KB (20+ targets), the generic param engine (`target_spec`), the deterministic pharmacophore/liability/acceptance/FTO/metal rule modules, the mechanism→eval mapping, and an exemplar provenance pattern (`cada_mn.itp`). These already drive params and eval for the cyclic program.
- **Genuinely new (≈30%):** (a) the **unified entry schema** linking statement→params+eval in one record; (b) the **uniform provenance/evidence-tier** layer (generalizing `cada_mn.itp`'s rigor, reusing the Grounded Standards model); (c) **one resolver** both loop and eval call (vs 5 bespoke reads); (d) **product surfacing** — promoting it into the workflow DB + chemist-editable versioned store; (e) the **tool-enrichment** tie-in.
- **Not claimed:** this does not add new chemistry knowledge or validate any rule — it unifies, provenances, and surfaces what exists. The αvβ6 metal/pharmacophore rules remain only as good as their cited sources (and `cada_mn.itp` is still pending its grompp/NVT validation).
