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

---

## First slice — BUILT (2026-10-21)

`research/guangzhou_all_atom/cyclic_llm/experience_kb.py` + `test_experience_kb.py` (5/5 pass, CPU, python3.14).

**Schema (implemented):** `KBEntry{ id · kind(metal|pharmacophore|sar|cmc|fto|eval_rule|pose) · statement ·
scope{modality,target_class,applies_when} · provenance{source_type, ref, evidence_tier T1–T4} ·
effects{tool_params{…}, eval_criteria[{criterion, mode(hard|advisory), checker}]} · version · status }`,
with `.validate()` (tier-in-ladder, eval-mode-in-{hard,advisory}).

**Adapters WRAP (not re-author) the existing assets:** `target_spec.load_spec` / `scorer_config.config_for`
(metal/cofactor, pose, receptor, counter-targets → params; metal-free-MIDAS ⇒ void → eval);
`pharmacophore_knowledge` (gate + generation_constraint); `knowledge_liability_flags.flag_candidate`
(β6-selectivity, lock, renal-charge, CMC universals — the live checker stays that fn); `fto_score.in_claim`
+ raw KB `fto` genus; `fep/forcefield/cada_mn.itp` (Duarte-2014, tier T1 — **still pending grompp/NVT validation**).

**`resolve(target)` = the single source** merging fired entries → `{tool_params, eval_criteria, provenance}`.
Verified `resolve("avb6")`:
- TOOL PARAMS: `metal_model=CaDA-MN`, `metal_ff_file=fep/forcefield/cada_mn.itp`, `cofactors=[MN×3 @β6 MIDAS]`,
  `pose_method=cofold+mmgbsa`, `receptor_asset=avb6_ourstructure_v1.cif`, `counter_targets=[avb8,avb3,avb5,a5b1]`,
  `generation_constraint={RGD + RGDLxxL/I + D-Pro/N-methyl lock}`.
- EVAL GATE-SET: `metal_retained_in_run`(hard), `pharmacophore_gate[avb6]`(hard), `sar:rgd-selectivity-element`(hard),
  `sar:conformational-lock`(hard), `sar:renal-cationic-charge`(advisory), `cmc_liabilities`(advisory),
  `fto_genus_clearance`(advisory) — each with checker + provenance tier.
- Contrast `resolve("pdl1")`: ppi-groove, no metal param, no void rule, pharmacophore advisory (structure-gated).

**Wired vs TODO (honest):**
- WIRED: one store drives BOTH params and the eval gate-set; backward-compat preserved (existing modules unchanged,
  still import/run); schema-validated; provenance-tiered.
- TODO (next slices): (1) route `loop_batch` / the DesignCampaign param+eval assembly through `resolve()` so the
  existing param-setting and gate assembly become *thin views* (deferred — rewiring the live loop carries test risk,
  out of first-slice scope); (2) product surfacing — register in the workflow DB + feed tool `scientific_context_v2`
  defaults (gitignored 328 MB DB + shared → document the hook, not force-write it here); (3) LLM-RAG fallback for
  novel/unknown targets (deterministic rules only in this slice).

---

## Verified-provenance requirement (citation-integrity) — 2026-10-21

The user asked whether the knowledge is **authoritative, with evidence sources**. Citation-integrity means we
VERIFY, never assume. The schema therefore makes `provenance.verified ∈ {True, False, "unverifiable", "n/a"}`
**MANDATORY** (`.validate()` enforces it) and `resolve()` surfaces `verified` + `evidence_tier` on every firing
entry, so a consumer/chemist sees an induced/unverified heuristic as exactly that — never as established fact.
Each seeded source was checked by web lookup on 2026-10-21; `provenance.verification_note` records what was checked.

### Verified provenance ledger — seeded entries

| Entry | Claim | Cited source | Verified | Tier |
|---|---|---|---|---|
| avb6:metal | CaDA octahedral Mn²⁺ cationic-dummy FF for the β6-MIDAS cofactor | Duarte et al., *J. Phys. Chem. B* 2014, 118(16):4351-4362 | **YES** (paper real, refines octahedral Mn²⁺ params) — caveats: .itp pending grompp/NVT; physiologic MIDAS=Mg²⁺, Mn=activating cation | T1 |
| avb6:pharmacophore | RGD required; Asp→MIDAS metal; D-Pro/N-methyl lock | Trivehexin c[YRGDLAYp(NMe)K], avebehexin c(FRGDLAFp(NMe)K) (EJNMM 2021); RGD-MIDAS integrin biology | **YES** (both compounds + mechanism confirmed) | T1 |
| avb6:sar-conformational-lock | D-Pro + N-methyl lock in validated actives | Trivehexin/avebehexin (EJNMM 2021) | **YES** (lock present in verified actives; "else uncontrolled" is inference → T2) | T2 |
| avb6:sar-renal-charge | net-cationic ⇒ higher kidney (dose-limiting) uptake via megalin/cubilin | EJNMM s00259-009-1239-1 / -010-1685-9 (megalin/cubilin; Lys/Arg co-infusion) | **YES** (established radiopharmacology) | T1 |
| cmc:universal | Asn-deamidation NG/NS, Asp-isomerisation DG/DS, Met/Trp oxidation | standard biopharm CMC refs (e.g. PMID 30526254) | **YES** (standard, well-documented) | T1 |
| avb6:metal-free-void | metal-free MIDAS run ⇒ MM-GBSA ΔG void | applies the verified RGD-Asp→MIDAS-metal requirement | **YES** (program admissibility rule applying a verified fact) | T2 |
| avb6:sar-b6-selectivity | RGD-L element confers β6-selectivity; no-RGDL → pan-integrin | knowledge_liability_flags; Trivehexin selectivity (avb8 131×/avb3 57×/a5b1 468×) | **NO** — compound selectivity IS published, but the RGDL-as-*determinant* causal claim is an SAR **inference** (no cited mutational/negative-control study) | T2 |
| avb6:fto-genus | FTO: patent CA2998968A1 genus Cyclo-(Arg-X1-Asp-...) | target_kb/avb6.json | **UNVERIFIABLE** — specific patent id/genus not independently confirmed (the αvβ6-cyclic-RGD patent space IS real, e.g. US20230173113) | T2 |
| avb6:pose / pdl1:pose | pose method by epitope | target_spec POSE_BY_EPITOPE | **n/a** (program method-config, not a literature claim) | T3 |
| pdl1:pharmacophore | PD-L1 structure-gated (no SLiM); WL12/BMS/dmp10 classes | pharmacophore_knowledge refs | **UNVERIFIABLE** — refs name known PD-L1 macrocycle classes but not checked this session; advisory only | T3 |

**Blunt summary:** authoritative-with-real-evidence = metal/CaDA-Mn, RGD pharmacophore, conformational-lock,
renal-cationic, CMC liabilities, metal-free-void (6). Flagged NOT-authoritative = β6-selectivity causal SAR
(inferred), FTO patent id (unverifiable), PD-L1 pharmacophore refs (unchecked). No citation was invented; every
"verified=False/unverifiable" is reported as such and tiered so it can never be consumed as established fact.

---

## Product wiring — status (2026-10-21)

The first slice is now wired into the loop and surfaced to the product via a registration hook.

**WIRED (code, tested — `test_experience_kb.py` 8/8):**
1. **Loop → `resolve()` (single source).** `loop_batch.run_round(target)` calls `experience_kb.resolve(target)`
   and returns `kb_params` (metal model/cofactors, pose, counter-targets, generation constraint) +
   `kb_gate_set` (the eval criteria, each carrying `mode`/`tier`/`verified`) + `kb_provenance`. A consistency
   guard asserts the KB's cofactors match `target_spec` (so `resolve()` is the single source, not a divergent
   path). Legacy `target_spec`/`score`/`acceptance_gate` remain the underlying providers (backward-compat
   confirmed: all modules still import/run).
2. **LLM-RAG fallback for novel targets (opt-in seam).** `resolve(target, rag=True)` on a target NOT in the KB
   retrieves similar entries as context and calls the `_llm_rag_call()` seam (live-LLM interface; default
   returns None → provisional). Anything proposed is tier **T4 / verified=False / status="provisional"** — never
   authoritative. Default `resolve()` stays deterministic (existing behavior unchanged).
3. **DB registration hook** — `register_experience_kb.py`: resolves the 16 canonical KB targets, builds a
   provenance-tiered `scientific_context_v2` block, and attaches it to the physics tools (cofold/MM-GBSA/
   OpenFE-RBFE/GROMACS/Boltz) in `tools.scientific_context_v2`. **Dry-run by default; never force-writes the
   ~324 MB gitignored DB.** Read path for the product: `kb_defaults_for(target)` (wraps `resolve()`).

**DEV-APPLY TODO (product-blocked, not code):**
- Run `register_experience_kb.py --apply --db <dev galaxy_ai_tools.db>` **on dev** (canonical DB lives on
  dev/S3; the local file is a copy), then let the normal DB sync carry it. Not done here — writing the shared
  DB from a local copy is exactly what the sync discipline forbids.
- Wire the composer / `nextflow_executor` param-prefill to call `kb_defaults_for(target)` at the point a target
  is identified (the read path exists; the call-site hook is a one-line placement in the product).
- Replace the `_llm_rag_call()` stub with a live LLM call for genuine novel-target proposals (seam + schema
  validation + T4 tiering already in place).

---

## 4. REBUILD — general ingestion KB + hard evidence invariant (2026-10-21)

The first slice (§1–3) wrapped **the current project's literal rules** (αvβ6/PD-L1 per-target adapters). That
was too ad hoc. The KB is now **GENERAL and domain-organized**, and INGESTS established rule-sets per domain
instead of hand-curating entries. The αvβ6 / PD-L1 program is a **resolved instance** over those domains.

### 4.1 The general KB — `cyclic_llm/medchem_kb.py` (ingestion + provenance layer)

| Domain | Ingested from (real source) | Yield | Admitted / candidate |
|---|---|---|---|
| **1 Liability / SAR** | **RDKit `FilterCatalog`** — PAINS A/B/C, BRENK, NIH, ZINC, ChEMBL alert sets (BMS, Dundee, Glaxo, Inpharmatica, LINT, MLSMR, SureChEMBL). Each alert carries its shipped `FilterSet`+`Reference`+`Scope`, mapped to a canonical paper (Baell & Holloway 2010; Brenk 2008; Jadhav 2010; Irwin & Shoichet 2005; Hann 1999; Pearce 2006; Gaulton 2017). | **13 rule-sets / 1,585 alerts** (nothing hand-written) | 10 rule-sets verified / 3 unverifiable (Inpharmatica, LINT, SureChEMBL — still applied, flagged) |
| **2 Metal coordination** | Published geometry surveys (Harding *Acta Cryst D* 2006; MetalPDB, Putignano *NAR* 2018; CheckMyMetal, Zheng *Acta Cryst D* 2017) + FF-param papers (Li & Merz *Chem Rev* 2017; MCPB.py 2016; 12-6-4 2015; Duarte CaDA *JPCB* 2014). Not cheaply downloadable → the **published tables are encoded with citations** (never invented). | **7 ions** (MG/MN/ZN/CA/FE/CU/NI) × geometry/CN/residue-prefs/FF-options | geometry 7/7 verified (T1); FF options per-param (CaDA verified; 12-6-4/MCPB locators unverifiable) |
| **3 Physchem / ADMET** | Standard rule definitions: Lipinski Ro5 (1997), Veber (2002), Doak–Kihlberg bRo5 (2014), chameleon/IMHB permeability (Rezai 2006; Over *Nat Chem Biol* 2016) + external predictors to call (SwissADME, ADMETlab). | **5 rules** | 5/5 verified |
| **4 Pharmacophore by class** | **No single clean DB → curated from reviews WITH citations** (integrin-MIDAS: Xiong *Science* 2002 + Dong *NSMB* 2014; PPI-groove: Clackson & Wells 1995 + Walensky 2014; protease/kinase/GPCR). **FLAGGED as the partially-curated domain.** | **5 classes** | 2 verified (integrin-MIDAS, ppi-groove) / 3 unverifiable (protease/kinase/gpcr — locators not confirmed) |
| **5 Modality heuristics** | Cyclization (Driggers *Nat Rev Drug Discov* 2008), N-methylation permeability tradeoff (Biron 2008; Kessler), stapling (Walensky 2014), D-amino / backbone. | **4 heuristics** | 1 verified (stapling) / 3 unverifiable (exact locators) |
| **+ Data sources** | Affinity = ChEMBL (Mendez *NAR* 2019) + BindingDB (Gilson *NAR* 2016) via `binding_affinity_v1`; permeability = CycPeptMPDB (Li *JCIM* 2023). | 2 pointers | 2/2 verified |

A **live screener** `medchem_kb.screen_liabilities(smiles)` runs the ingested catalogs over any SMILES and
returns matched alerts **with per-alert provenance** (alert name + rule-set + canonical paper).

### 4.2 Hard evidence invariant (enforced in `experience_kb.KBEntry.validate()`)

Every piece of knowledge must have real evidence — enforced in code, not by convention:

1. **Knowledge requires a real source.** A `metal|pharmacophore|sar|cmc|fto|eval_rule|physchem|modality|liability`
   entry with an empty/missing `provenance.ref` **FAILS `validate()`** and is never admitted.
2. **Unverified → quarantined.** A knowledge entry cited but not confirmed (`verified ∈ {False, "unverifiable"}`)
   validates but gets `status="candidate"`: it is kept in a separate `candidates` list and **never returned by
   `resolve()` as authoritative**. The served KB is therefore 100% evidence-supported.
3. **Knowledge vs config.** Engine/program defaults (pose method, receptor asset, cofactor site/count) are
   `kind="config"`, `tier="n/a"` — not knowledge claims, exempt from the evidence requirement, always served.
4. **Provenance carried on ingest.** Each RDKit alert carries its catalog+paper; each metal row its survey; each
   param its FF paper — automatically into `provenance.ref`.

### 4.3 The project is a resolved instance

`resolve("avb6")` now DERIVES from the general domains + the `target_kb/avb6.json` instance:
- **12 admitted** (all `verified=True`): config ×2, metal ×1 (general MN octahedral/CaDA rule), pharmacophore ×1
  (general integrin-MIDAS principle), liability ×1 (ingested 1,585-alert screener), physchem ×2 (bRo5 + chameleon),
  cmc ×1, sar ×3, eval_rule ×1 (metal-free-void).
- **4 quarantined candidates** (not served): the FTO patent genus (unverifiable patent id) + 3 modality heuristics
  (exact locators unconfirmed).
- **b6-selectivity UPGRADED to verified** — `avb6:sar-b6-selectivity` now cites **Dong, Hudson, Lu & Springer,
  *Nat Struct Mol Biol* 2014;21:1091 (PDB 4UM8/4UM9)**: the RGDLxxL/I motif engaging the β6/β8 SDL pocket is the
  structurally-established selectivity determinant (was a program inference flag; now authoritative, served hard gate).

`resolve("pdl1")` → 7 admitted (ppi-groove class principle, structural-alert screen, Ro5/Veber/predictors, CMC) +
1 quarantined (FTO). No metal (no cofactor), pharmacophore gate advisory (structure-gated) — all backward-compatible.

### 4.4 Honest coverage

- **Ingested-complete:** Liability (1,585 alerts, RDKit), Physchem (standard definitions), Metal geometry (published
  surveys). These are not hand-written; they carry real, shippable provenance.
- **Partially-curated (flagged):** Pharmacophore-by-class — no single clean DB exists, so 5 classes are curated from
  reviews with citations; only integrin-MIDAS + ppi-groove are confidently verified and served.
- **Quarantined (not served, pending verification):** 3 ChEMBL liability sub-sets (Inpharmatica/LINT/SureChEMBL
  primary locators), 3 pharmacophore classes (protease/kinase/gpcr locators), 3 modality heuristics (exact pages),
  the αvβ6 FTO patent id. These are real, applied where safe (liability screening still runs all 1,585), but never
  presented by `resolve()` as authoritative knowledge until their source is confirmed.
- **Gap:** quantitative ADMET/affinity/permeability come from external predictors + datasets (SwissADME/ADMETlab,
  binding_affinity_v1, CycPeptMPDB) that the KB *points at* with provenance — it does not re-host those models.

Files: `cyclic_llm/medchem_kb.py` (general KB), `cyclic_llm/experience_kb.py` (wrap + invariant + resolver),
`cyclic_llm/test_experience_kb.py` (10/10, incl. evidence-invariant + RDKit-ingestion tests).
