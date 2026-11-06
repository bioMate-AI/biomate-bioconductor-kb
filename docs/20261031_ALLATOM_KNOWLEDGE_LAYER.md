# All-atom hybrid LLM: literature-sourced knowledge layer (workstream K) — 2026-10-29

Code and data: `research/guangzhou_all_atom/cyclic_llm/allatom_paper/knowledge/`. Verified set: `knowledge_kb_v1.json` (sha256 `29368807…6951`, `knowledge_kb_v1.sha256`; tiers corrected 2026-10-29, see section 8; the earlier hash `b6c89885…42b7` is superseded). Contract: plan section 2 (`Constraint.soft_logits`, retrieval-context text), design section 3-4.

## 1. What this is
A structured, provenance-tracked knowledge layer with four entry kinds: **rule** (directional or window statement), **fundamental** (mechanism or structure-property principle), **caution** (limits, data-bias and counter-evidence), **card** (campaign / benchmark ledger entry: what was designed, outcome, failure modes, lessons). Every entry carries a verbatim quote (<= 30 words) from a source that was opened, a DOI or file path, a tier, an access date and a confidence.

Integrity mechanism (the part that distinguishes it from notes recalled from memory): full texts are fetched on EC2 from Europe PMC (open-access XML), arXiv (PDF text) or the repo (internal documents), normalised, and stored with a sha256; `build_kb.py` then checks every quote (and every extra quote on cards) as an exact substring of that stored text. **107 of 107 entries verified; 0 unverified; 0 schema problems.** An entry whose quote does not verify is excluded from weights by construction (tested). Candidate sentences were read from the raw fetched text, not from web-tool summaries.

## 2. Content and coverage
| | count |
|---|---|
| entries | 107 (rule 44, fundamental 24, caution 11, card 28) |
| tier (after the section-8 audit) | T1 own result / method of the source 60, T2 review summary / restatement / background 36, T-internal 11 (T3: 0) |
| sources opened | 45 external (41 Europe PMC OA articles, 4 arXiv preprints) + 5 internal documents |
| outcome class | permeability 55, stability 10, solubility 2, other 40 |
| weight-eligible | 32 (28 permeability, 1 stability, 1 solubility, 2 other); by tier T1 14, T2 18 |

Topic coverage (an entry can count in several topics): cyclization / ring / bridging 34; size, bRo5 and oral guidelines 24; N-methylation 13; intramolecular H-bond / chameleonicity 12; lipophilicity / solubility / aggregation 12; stability (proteolysis, serum, deamidation) 12; stereochemistry / D-residues 10; campaign cards 28 (17 external, 11 internal).

**Campaign ledger (main new deliverable).** External cards: RFpeptides, AfCycDesign, BindCraft (proteins), BindCraft for peptides, PepINVENT, HighFold-MeD, PepGLAD, PepTune, PepMLM, CP-Composer, CycDiff-DPO, random cyclic-peptide library screening (Keap1-Nrf2), CycloSEL, two Cyclin A/B macrocycle campaigns (permeability SAR; oral bioavailability), approved / clinical macrocycles, romidepsin. Internal cards (our own record, with file paths): zero-shot affinity ceiling, permeability wall, generator DockQ gap, synthetic-only loop, rules as filter-not-generator, multi-objective selection, unlaunched RFpeptides, alphavbeta6 metal-free MM-GBSA, PD-L1 blockade decision, SNAT2 prior-art verdict, alphavbeta6 gold-standard assay spread. IP-sensitive documents (FTO reads, patent mapping) are deliberately not indexed.

Lessons the ledger makes explicit (each backed by a verified quote): hit rates are reported per target and across incompatible definitions (relative ipTM, Delta-G < 0, affinity, functional readout); peptide design papers rarely report non-binders; BindCraft peptides gave **no detectable binding for PD-1/PD-L1** (our PD-L1 target) while MDM2 gave 7 of 15; AfCycDesign's pLDDT > 0.85 filter was right for 80% (44 of 55) of predictions; PepGLAD notes that even ground-truth peptides only reach 36% under AF2-consistency evaluation; romidepsin shows that stability engineering (removing a reducible disulfide) cost 10-100-fold potency; permeability-raising N-methylation cost cellular activity and selectivity in matched pairs; 91% of PAMPA records in a public macrocycle database come from one publication.

## 3. What is new relative to `kb_audit/peptide_sar_rules_v1.json`
That file: 6 data-mined rules (TPSA, HBD, logP, Veber, ...) from all 21 training sources of our own labels, no external provenance, and not leak-safe for any comparison whose stop or held-out verifiers use a subset of those sources. This layer: 107 externally sourced, quote-verified entries with provenance; leak-free by construction with respect to our labels (no label is used to create or weight an entry; weights are a uniform prior, see section 5); plus cards, cautions and fundamentals that the old file cannot represent. The old file stays available as an ablation arm.

## 4. Direction check against our own labels (source group A only)
Group A is the v2 train group from Track E (`track_e/source_groups_v2.json`): **2020_Townsend (n = 2,881) and 2021_Kelly (n = 1,518)**. Rows from every other source are dropped while reading, and the script asserts that only group A sources remain; groups S and B labels were never loaded. Label = raw PAMPA; statistic = within-source Spearman rho (rank-based, equal to using the within-source z-score); intervals = cluster bootstrap over flat-structure (stereoisomer) groups, B = 300, seed 0. Descriptive only (no multiplicity correction). Only rules whose stated outcome is permeability are tested; solubility and stability rules are marked not applicable (an earlier run that tested them against the permeability label was wrong and was replaced).

Result over 107 entries: **17 agree, 7 mixed, 0 disagree, 83 not testable** (cards, cautions and context entries have no directional claim; some windows lack group size).

| feature (expected sign) | Townsend rho [95% CI] | Kelly rho [95% CI] | reading |
|---|---|---|---|
| N-methyl count (+) | +0.50 [0.43, 0.57] | +0.53 [0.33, 0.66] | agrees in both |
| HBD (-) | -0.44 [-0.51, -0.36] | -0.53 [-0.66, -0.35] | agrees in both |
| TPSA (-) | -0.47 [-0.55, -0.37] | -0.49 [-0.61, -0.28] | agrees in both |
| cLogP (+, Crippen) | +0.29 [0.18, 0.38] | +0.49 [0.29, 0.62] | agrees in both |
| HBA (-) | -0.26 [-0.37, -0.13] | -0.07 [-0.13, -0.01] | agrees, weak in Kelly |
| MW / heavy atoms (-) | -0.12 [-0.24, -0.02] | **+0.48** [0.30, 0.61] | **sign flips between sources: rule not stable** |
| rotatable bonds (-) | +0.16 [0.06, 0.27] | -0.10 [-0.28, 0.08] | mixed |
| D-residue count (+) | -0.04 [-0.09, 0.01] | +0.02 [-0.05, 0.08] | no signal at count level |

Windows and shapes: lipophilicity peak (inverted U; quadratic coefficient -0.113 [-0.144, -0.085] Townsend, -0.120 [-0.167, -0.063] Kelly) agrees in both; the macrocycle drug window (HBD <= 7 with MW < 1000 or cLogP > 2.5) shows inside-window peptides more permeable in Kelly (+0.43 [0.09, 0.63], 1,172 inside vs 346 outside; untestable in Townsend, all inside); the POL window (cLogP < 4) is weakly contradicted in Townsend (-0.12 [-0.24, 0.04]).

Reading for the loop: N-methyl count, HBD, TPSA and cLogP are the stable, literature-supported directions on our own two largest sources; **size and D-residue rules should not be weighted** (sign unstable / no signal), and the stored uniform weights for them are a placeholder. These two sources are labs known for heavily N-methylated series, so agreement is evidence of consistency, not of causation.

## 5. Interface and use
- `knowledge_loader.KnowledgePotential(kb, lam, stats, outcome_class="permeability")`: sequence-level log-linear potential from weight-eligible rules (z-scored features with caller-supplied group A means and SDs; hinge penalties for windows; `any_of` and `max_violations` semantics for the guideline rules). Permeability, stability and solubility rules are never summed into one potential. Weights are a uniform prior (0.10 x confidence scale; 0 for conflicts, cautions, context). **Weight tuning on group A has not been run in this phase**; the direction check above is the evidence that decides which rules to keep.
- `rules_text(kb, ...)`: provenance-tagged snippets for retrieval-conditioned prompts, deterministic.
- `features_from_smiles` (RDKit, lazy) computes the 2D features; `n_dres` needs monomer parsing (`ihlm/symbolic.py`).
- Schema fields requested by the coordinator are present: `structure_ref` (list of PDB ids, currently empty everywhere; K3 fills it) and `applicable_target` (list or null; set on cards).

## 6. Tests and reproducibility
`test_knowledge.py` (17 unit tests, run on EC2): schema, unique ids, provenance, every quote verified against stored text, unverified never weighted, weights only for T1/T2 rules with computable features, cautions and conflicts weightless, directional and window behaviour of the potential, outcome classes not mixed, loader rejects an unverified entry that carries weight, deterministic text output, deterministic build (two builds produce the same sha256). Pipeline: `fetch_fulltext.py` / `fetch_arxiv.py` -> `build_kb.py` -> `test_knowledge.py` -> `direction_check.py`, driven by `run_build_job.sh` on spot via `launch_job.sh`. Runs recorded under `s3://biomate-nextflow-work/cyclic_peptide/allatom/k/` (fetch2, fetch3, fetcharxiv, build5). Spend: nine small spot instances (c6i.large / c5.large, 5-10 minutes each), about USD 0.05 (estimate; spot price history not queried); no GPU; no laptop compute.

## 7. Limitations and not done
- Collection stopped at the coordinator's instruction after the existing-knowledge survey: **not collected** — target pharmacophore rules (RGD / alphavbeta6, PD-L1 macrocycle series, GRPR / bombesin; target-structure side belongs to K3), Wikipedia / Wikidata / database facts (no T3 entries), display-campaign hit rates (RaPID, mRNA and phage display), per-drug properties of approved cyclic peptides. Imports of CyclicPeptideDB-type collections belong to K2 and are referenced by id, not rebuilt.
- 36 of the 107 entries are T2 (18 are weight-eligible): review summaries, restatements of results the source cites to other papers, authors' background, one textbook rule and one project goal. The cited primary studies behind them were **not** opened by us (section 8). An earlier version of this line said '14'; that was wrong: 14 was the number of weight-eligible entries among the 31 T2 entries at that time, not the number of T2 entries.
- Many 2026 sources: the Europe PMC records and DOIs were read from the fetched XML, but several articles are very recent and unreviewed by us.
- Direction check: two sources only (Townsend dominates), peptide descriptors from the stratification annotation (Crippen logP, RDKit TPSA/HBD), cluster bootstrap by flat structure but not by lab; no multiplicity control; PAMPA only.
- One rule (`LIT-CHAM-003`, grazoprevir) and the depsipeptide / macrobicycle series are not peptides in the strict sense; scope fields say so.
- Weights are not tuned; no score has been used in a loop yet.

## 8. Tier audit (2026-10-29, requested by the coordinator after the KB manuscript writer found the '14 vs 31' discrepancy)
**Reconciliation.** The 14 in section 7 was an error of mine: at the time there were 31 T2 entries and 14 of them were weight-eligible; I had carried the second number into a sentence about the first.

**Rule applied (written once in `tier_decisions.py` and applied to all 107 entries).** The tier follows the provenance of the quoted statement, not the article type. T1 = the quote reports a result or method obtained in the source's own experiment, simulation, benchmark or data analysis. T2 = a review's summary of other people's work, a restatement of a result the source cites to another paper, a textbook rule, authors' background or motivation, or a project goal. If the stored text does not let us establish that a number is the source's own result, the default is T2. Before the audit I had applied this rule inconsistently (the tier partly followed the article type).

**Evidence.** `tier_audit_context.py` (run on EC2) extracted, for every entry, the source article type from the stored Europe PMC XML and the quote's surrounding text with citation markers and cue words; I then read the context of all 31 T2 entries and of the 32 T1 entries flagged by review-type source, citation marker or restatement cue words. Entries not flagged were not individually re-read for provenance (their quotes sit in Results/abstract sentences describing the source's own work); this is a limit of the audit.

**Changes (13): nine T1 -> T2, four T2 -> T1.** T1 -> T2: `LIT-3DPSA-001`, `LIT-EPSA-001`, `LIT-NMEPOS-002`, `LIT-SIZE-001`, `LIT-NME-006`, `LIT-IMHB-004`, `LIT-NME-003` (quote restates a result cited to other work), `LIT-CHAM-002` (cannot establish from the text that the PROTAC comparison is the paper's own; default T2), `LIT-OB-001` (a design goal, not a result). T2 -> T1: `CARD-MACRODRUG-001`, `LIT-CLIN-002`, `LIT-CLIN-003`, `LIT-PEP-001` (the source, a review or data paper, analysed its own data set). The HighFold-MeD card kept T1 but now rests on two added verified quotes stating the paper's own method (its original quotes were background).

**Counts after the audit.** T1 60 (was 65), T2 36 (was 31), T-internal 11; 107/107 quotes still verified; **weight eligibility unchanged: 32 entries, the identical set** (eligibility requires tier in {T1, T2} and does not distinguish them). New hash `29368807…6951`. The direction check is unaffected by tier (17 agree, 7 mixed, 0 disagree, 83 not testable).

**The 36 T2 entries** (`tier_audit.json`, one row each with (a) source is a review, (b) underlying primary study opened by us, (c) character of the quote): source type review or commentary 18, research article or other 18; (b) is "no" for all 36 (the studies behind the quoted statements were not opened by us); (c) review's own wording 11, restates a cited primary result 16, authors' background 6, textbook rule 1, project goal 1, uncertain (default T2) 1. A test (`test_tier_audit_matches_kb`) asserts that the T2 table equals the T2 set in the KB and that every change is applied.

**Consequence for users.** T2 weights are no less eligible than T1 in the potential. If a stricter policy is wanted (for example weights only from T1), 18 of the 32 eligible rules (the T2 ones) would drop out; the loader can filter by tier but the default is unchanged.
