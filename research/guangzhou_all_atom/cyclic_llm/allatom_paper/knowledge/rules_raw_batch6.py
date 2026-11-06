# Batch 6: internal campaign cards (T-internal). Source = our own repo documents (path); quotes verified verbatim against the file text on EC2.
# IP-sensitive documents (FTO reads, patent mapping) are deliberately NOT indexed.
from rules_raw_batch1 import add, R  # noqa

def icard(id, path, title, date, summary, quote, quotes, method, modality, outcome, failure_modes, lessons, targets=None, confidence="medium"):
    add(id=id, path=path, title=title, date=date, tier="T-internal", kind="card", scope=["internal campaign"], outcome="campaign ledger",
        statement=summary, feat=None, direction="context", effect=None, quote=quote, quotes=quotes, confidence=confidence, notes="internal record; status as of the document date",
        applicable_target=targets, card=dict(method=method, modality=modality, outcome=outcome, failure_modes=failure_modes, lessons=lessons))

MAP = "docs/20261021_PROGRAM_CHALLENGE_MAP.md"
icard("INT-AFFINITY-001", MAP, "Cyclic-Peptide / Drug-Design Program - Challenge Map", "2026-10-21",
      "Zero-shot novel-target affinity prediction hit a convergent ~0.42 ceiling across ECFP, ChemBERTa, concat, interaction and few-shot models; cross-target LLM was null.",
      "Convergent ~0.42 ceiling across ECFP/ChemBERTa/concat/interaction/few-shot (2026-10-21); OOD PD-L1 0.18→~0.42; cross-target LLM NULL.", [],
      "ECFP, ChemBERTa, concatenation, interaction and few-shot affinity models evaluated on held-out targets", "novel-target binding affinity (cyclic peptides, ChEMBL+BindingDB)",
      "convergent ~0.42 ceiling; OOD PD-L1 0.18 to ~0.42; cross-target LLM null (as of 2026-10-21)",
      "More data/larger models did not move the ceiling; public data saturated; later audits (2026-10-28 to 30) found the binding benchmarks fail validity gates",
      "Zero-shot novel-target affinity is a field frontier; invest in physics grounding or target-specific labels instead of bigger models", targets=["PD-L1"])
icard("INT-PERM-001", MAP, "Cyclic-Peptide / Drug-Design Program - Challenge Map", "2026-10-21",
      "Static permeability models were weak out-of-distribution (gate R2 0.45, OOD R2 0.19); the diagnosed signal is dynamical (chameleon H-bond shielding).",
      "gate R²0.45, OOD R²**0.19**; ML ECFP R²0.23", ["signal is **DYNAMICAL (chameleon H-bond shielding)** — static ECFP structurally can't capture it"],
      "ECFP/static-descriptor permeability regression on CycPeptMPDB", "cyclic peptide membrane permeability",
      "gate R2 0.45 in-distribution, OOD R2 0.19, ECFP ML R2 0.23",
      "Static features cannot capture conformational (chameleonic) shielding; OOD collapse",
      "Use dynamical/conformer-based descriptors or lab-aware models; our later test of ensemble features on public data did not show a gain under lab shift (idea A, 2026-10-29)")
icard("INT-GENDOCKQ-001", MAP, "Cyclic-Peptide / Drug-Design Program - Challenge Map", "2026-10-21",
      "Our cyclic fine-tune of the generator reached DockQ 0.506 versus 0.759 for UniMoMo (linear-only, in-distribution).",
      "cyclic-FT DockQ **0.506 vs UniMoMo 0.759** (linear-only, in-dist)", [],
      "BoltzGen cyclic fine-tune compared with UniMoMo on DockQ", "cyclic peptide complex generation",
      "DockQ 0.506 (ours) versus 0.759 (UniMoMo)", "Fine-tuned generator plateaued below the open baseline; a claimed 0.7754 UniMoMo adapter result was unconfirmed (run failed)",
      "Use the base/open generators as-is unless a modification is shown to beat them on the same split", targets=None)
icard("INT-LOOP-001", MAP, "Cyclic-Peptide / Drug-Design Program - Challenge Map", "2026-10-21",
      "The closed learning loop was built only on synthetic signal and not validated (as of 2026-10-21).",
      "built-synthetic only; NOT validated.", [],
      "DPO/DBTL wiring with self-tests fed by verify-and-select pairs", "closed-loop learning for cyclic peptide design",
      "wiring and self-tests passed; no real preference signal fed", "Synthetic-only evidence; no held-out validation of improvement",
      "Retrospective replays on real measured labels (2026-10-27 to 30) are the first real evidence and show modest in-distribution gains that shrink under shift")
icard("INT-NEURO-001", MAP, "Cyclic-Peptide / Drug-Design Program - Challenge Map", "2026-10-21",
      "Earlier rounds found rules to be a good filter but a poor generator: a rule-fixed scaffold only reproduced the patented genus.",
      "Rounds showed rules = good filter / poor generator (rule-fixed scaffold → only patented genus)", [],
      "rule-constrained generation", "cyclic peptide generation under hard rules", "rules work as filters",
      "As generators, rules fixed the scaffold and only reproduced the patented genus", "Use rules to constrain decoding and filter, not to define the scaffold; design the constraint set so that it leaves chemistry free")
icard("INT-MULTIOBJ-001", MAP, "Cyclic-Peptide / Drug-Design Program - Challenge Map", "2026-10-21",
      "Multi-objective selection by qNEHVI and greedy hypervolume beat a composite score on PD-L1 candidates.",
      "qNEHVI +37.6%, greedy-HV +115% vs composite (PD-L1)", [],
      "qNEHVI / greedy hypervolume selection versus composite scoring", "multi-objective candidate selection (PD-L1)",
      "qNEHVI +37.6% and greedy-HV +115% versus composite", "Evaluated on internal candidates and objectives; no wet-lab confirmation",
      "Pareto-style selection outperformed weighted composites in this setting", targets=["PD-L1"])
icard("INT-RFPEP-001", MAP, "Cyclic-Peptide / Drug-Design Program - Challenge Map", "2026-10-21",
      "RFpeptides physics-prior design was built and pre-flight checked but never launched (0 results); literature bar 12/39 targets at ~9.4 nM.",
      "RFpeptides preflight OK, 0 results. Lit bar 12/39 targets, ~9.4 nM (canonical-AA).", [],
      "RFpeptides pipeline prepared for novel-target macrocycle design", "novel-target binder design via physics prior",
      "pre-flight OK; no designs produced", "Never launched, so no performance data of our own", "Literature bar for comparison: 12 of 39 targets with ~9.4 nM binders")
icard("INT-AVB6METAL-001", "docs/20261019_AVB6_METAL_MMGBSA_METHODDEV.md", "alphavbeta6 metal-aware MM-GBSA method development", "2026-10-19",
      "Metal-free MM-GBSA lost the MIDAS Mn-Asp interaction and gave weak/positive binding energies for alphavbeta6 RGD ligands.",
      "so the bridging Asp→Mn interaction vanished and ΔG came out weak/positive (e.g. metal-free EN-04 +6.77 kcal/mol)", [],
      "MM-GBSA rescoring of alphavbeta6 ligands with and without the MIDAS Mn2+", "metal-mediated integrin binding (RGD)",
      "metal-free scoring was structurally unable to score the real binding mode (EN-04 +6.77 kcal/mol)",
      "Dropping the metal in split_design() removed the bridging Asp-Mn interaction", "For metalloprotein sites the metal must be retained and parameterised before any physics score is trusted (a later frame bug about the Mn position was fixed on 2026-10-25)",
      targets=["avb6"])
icard("INT-PDL1-001", "docs/20261013_PDL1_BLOCKADE_SINGLE_TARGET.md", "PD-L1 blockade macrocycle: single-target program", "2026-10-13",
      "PD-L1 is pursued as a blockade (PD-1/PD-L1 PPI-block) single-target macrocycle, not a radioligand or bispecific.",
      "PD-L1 is pursued as a blockade (PD-1/PD-L1 PPI-block) agent, single-target — not a radioligand and not a bispecific arm", [],
      "single-target PD-1/PD-L1 blocking macrocycle program", "PPI-blocking cyclic peptide", "decision recorded; plan documented",
      "No wet-lab binding result for this program is recorded in this document", "Blockade framing removes the expression-sink and chelator-handle liabilities of the radioligand modality; external BindCraft peptides for PD-1/PD-L1 gave no detectable binding (CARD-BINDCRAFT-002)",
      targets=["PD-L1"])
icard("INT-SNAT2-001", "docs/20260823_SNAT2_NOVELTY_VERDICT.md", "SNAT2 novelty verdict", "2026-08-23",
      "No experimental 3D structure of human SNAT2/SLC38A2 exists, and prior computation is single-state.",
      "No experimental 3D structure of human SNAT2/SLC38A2 (Q96QD8) has ever been published or deposited", [],
      "prior-art review (deep-research workflow) before modelling the SNAT2 transport cycle", "transporter conformational states (not a peptide campaign)",
      "verdict: novel and sensible; strongest novel asset is time-sensitive", "Structure-less target: all prior computation is single-state",
      "A structure-less target limits structure-based design; alternate-state modelling is the open niche", targets=["SNAT2"])
icard("INT-AVB6GOLD-001", "docs/20261024_AVB6_FEP_GOLD_BENCHMARK_PREREG.md", "alphavbeta6 metal-aware FEP gold-standard pre-registration", "2026-10-24",
      "The gold-standard alphavbeta6 ligand A20FMDV2 has assay-format-dependent affinity: K_D 0.22 nM (radioligand), ~3 nM immobilized, ~63 nM in cells.",
      "K_D 0.22 nM (radioligand); ~3 nM immobilized; ~63 nM cell", [],
      "pre-registered FEP benchmark against measured alphavbeta6 affinities and selectivities", "metal-aware relative FEP for integrin affinity/selectivity",
      "pre-registration only in this document (written before any benchmark edge ran)", "Affinity of one compound varies about 290-fold across assay formats (0.22 nM vs ~63 nM, ratio computed)",
      "Compare predictions to a single assay format and report the format; cross-assay ranges bound achievable accuracy", targets=["avb6"])
