# Task-Design Committee Review — are the benchmark tasks deep enough for the field, and complex enough to show platform ability?

**2026-10-27.** Four-lens committee (senior bioinformatics-core director; clinical-pharmacology/DMPK expert;
ML benchmark-design methodologist; adversarial product skeptic) reviewed the **real items** of all three
benchmarks (RealBio, channel routing, DrugDev), not the manuscript prose. Verdict is unanimous.

## The two questions, answered

**1. In-depth enough for the field?** — *Partly.* Topic literacy is genuinely good, especially RealBio and
DrugDev: realistic Nextflow failure logs (Salmon OOM, CRAM-without-reference, cross-region S3), context-aware
QC (snRNA mito thresholds, low-occupancy TF ChIP), and real PK/trial parameters (CLint, fu_plasma, OATP1B1,
BOIN with inter-individual variability). The *topics* show domain depth.

**2. Complex enough to show platform ability?** — **No, not yet.** This is the unanimous finding. Almost every
item is a **single-turn, text-in/text-out classification or slot-fill**, which a plain chat model solves from
the prompt alone. The tasks test the ability to *describe* competent work, not to *perform* it — so they do
**not** exercise or reveal the differentiators of an execution platform (retrieval, deterministic rules,
mechanistic computation, real pipeline execution, output verification).

### Committee ratings (1 = shallow / weak discrimination, 5 = deep / strongly execution-discriminating)

| Benchmark | Field depth | Capability discrimination | Core limitation |
|---|---|---|---|
| **RealBio** | 3–4.5 | **2–3.5** | broad coverage, but recognition + narrated diagnosis rather than verified operation |
| **Channel routing** | 2 | **1** | resource-*label* classification; a lexical classifier already scores ~0.80 (we measured this) |
| **DrugDev** | 2–4 | **2–4 (iff execution required)** | highest potential, but underdetermined specs + named-drug memory shortcut |

Our own **keyword baseline (0.80 on channel routing)** empirically confirms the committee's point that a modest
lexical classifier performs well — the task does not require understanding, let alone a platform.

## Validity bugs found (fix regardless of direction)

- **Items that print their own answer.** Several autofix logs state the fix ("Provide `--fasta`…", "requires
  Java 17+… Installed: Java 11", "Memory required ~28 GB; allocated 16 GB", and the S3 item even lists
  remedies). Several protocol items give away the verdict ("this is a genuinely defective sample"; "true
  biology still captured… valid"). These test reading comprehension, not fault isolation.
- **An internally inconsistent item.** The cross-region S3 log says 47.2 GB at 15 MB/s ≈ 8.3 h; that is ~1 h.
  A capable system should flag the inconsistency, not comply.
- **Ambiguity scored as fact.** Parameter-fill maps "no strand information provided" → `unstranded`, conflating
  *unknown* strandedness with an *unstranded library*; the competent action is to inspect/ask. Accepting
  `nf-core/rnaseq` for lncRNA *discovery* likewise needs qualification.
- **Named-drug memory shortcut (DrugDev).** Aspirin/sildenafil/verapamil invite recall of published Cmax;
  and EC50 in nM cannot be compared to a dose in mg without a molecular-weight conversion that the item omits.
- **Difficulty labels are asserted, not calibrated.** "direct/indirect/adversarial/hard" should be set
  empirically against lexical, plain-LLM, retrieval-only, and execution-capable baselines.

## The unanimous #1 upgrade

**Make the primary score depend on a hidden, independently-verifiable outcome from an artifact-backed,
execution-grounded task — not on naming the intended method.** Concretely, per benchmark:

- **RealBio.** Attach real artifacts (FASTQ headers, sample sheets, a failed workspace + logs *without* the
  diagnosis). Require an executable fix (e.g. a `nextflow.config` resource override), resume the run on a small
  dataset, and verify outputs. Penalize unsafe fixes (dropping samples, switching reference builds). Grade
  generated workflows by execution + scientific invariants (target-decoy FDR, reference consistency), not
  tool-name presence. Add conflict items (user says "human" but reads map to mouse) where the right move is to
  detect and resolve.
- **Channel routing.** Replace single-label classification with **multi-step resource plans with dependencies**
  (discover cohort → verify access/licensing → inspect data dictionary → decide feasibility), **matched minimal
  pairs** that hold vocabulary constant while varying the correct resource (explain Tanimoto vs. compute it vs.
  find measured data), and **abstention/infeasibility** cases. Score downstream success (correct record
  retrieved, compatible accession, workflow actually initiated), keeping route-label accuracy as a diagnostic.
- **DrugDev.** Publish a reproducible **modeling contract** (physiology, formulation, clearance scaling,
  analyte, MW, software version, tolerances). **Blind the compounds** (structures + measured properties, not
  names) to kill recall. Turn dose-finding into **sequential trial execution** with hidden toxicity curves, and
  score **operating characteristics** (MTD-selection frequency, overdose allocation, early-stop) with Monte
  Carlo uncertainty. Separate PK/PD-model validation from dose-finding-rule validation.

## What this means for the manuscripts

The three papers are honest about what they measure, but they should **state plainly that the current tasks
measure recognition/selection, that a lexical/chat baseline is competitive on several of them, and that an
execution-grounded v2 (artifact-backed, hidden-verification) is the design that will discriminate platform
capability.** The execution-grounded direction is already consistent with the planned cross-stage track; the
committee validates making it the headline, not an appendix.

## Prioritized action plan
1. **Fix the validity bugs** (answer-leakage items, the S3 inconsistency, the ambiguity-as-fact gold, add MW to
   the PK items) — unambiguous improvements to the *existing* tasks.
2. **Blind the DrugDev compounds** + publish the modeling contract — closes the memory shortcut.
3. **Empirically calibrate difficulty** against the lexical / plain-LLM / retrieval / execution baselines.
4. **Build the execution-grounded v2 task family** (artifact-backed, hidden-outcome scoring) — the real lever,
   overlapping the cross-stage execution-grader track.
