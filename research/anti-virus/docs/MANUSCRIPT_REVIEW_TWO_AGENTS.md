# Dual-agent review of earlier manuscript drafts (internal QC)

**Purpose:** The first drafts read as **lab notebooks / SOPs** (manifest paths, run UUIDs, “GROMACS did not succeed” in the abstract). This memo records two **independent reviewer roles** and the **consensus** applied when rewriting to **v1.0 research manuscripts** (`MANUSCRIPT_DRAFT_PLAN_A_VACCINE.md`, `MANUSCRIPT_DRAFT_ANDV_INHIBITOR.md`).

**External structuring guide adopted:** Mensh & Kording, *Ten simple rules for structuring papers*, *PLoS Comput Biol* 13(9): e1005619 (2017) — [DOI 10.1371/journal.pcbi.1005619](https://doi.org/10.1371/journal.pcbi.1005619). Emphasis: **one central contribution**, **context–content–conclusion** per section, **abstract ≠ troubleshooting log**.

---

## Agent A — Reviewer for scientific narrative and contribution (“story”)

**Verdict on prior drafts:** **Major revision.**

**Strengths**

- The underlying work is **real** (epitopeprediction succeeded; inhibitor pipeline produced interpretable docking and QC).

**Failures relative to a research article**

1. **No clear “Rule of One” contribution** in the opening: the reader could not answer, in one sentence, what **new scientific knowledge** is gained (as opposed to what repository paths exist).

2. **Abstract violated C–C–C for impatient readers:** operational failures belong in **Discussion / Limitations**, not in the **summary of findings**. A reader scanning the abstract should learn **what biology was analyzed** and **what pattern emerged**, not which cloud job failed.

3. **Results read as instructions to authors** (“extract from JSON…”) instead of **claims supported by evidence**. A manuscript **states findings**; supplementary methods or a separate protocol can house exhaustive provenance.

4. **Tone:** second-person checklists (“Authors should…”) belong in a **guide**, not a **Results** section.

**Required fixes (applied in v1.0)**

- Reframe as **hypothesis-motivated immunoinformatics** (Plan A) and **structure-guided prioritization** (inhibitor).
- Move UUIDs, bucket URIs, and audit cross-links to **Data availability** or **Supplementary Methods**.
- **Abstract** = motivation + approach + **biological/computational outcome** + **bounded interpretation** + one-sentence limitation (e.g., *in silico only*).

---

## Agent B — Reviewer for methods integrity, ethics, and reproducibility (“audit”)

**Verdict on prior drafts:** **Major revision** on **ethics of presentation**; **accept** on underlying transparency intent.

**Strengths**

- Early drafts **did not hide** chain-of-custody problems (important for the inhibitor audit run).

**Failures**

1. **Conflated transparency with placement:** `AUDIT.md` disclosures must appear in **Methods** and **Limitations**, but **must not** dominate the **Abstract** unless the paper’s *sole* contribution is forensic re-analysis of a broken pipeline (it is not).

2. **Risk of over-claiming:** docking affinities were presented without enough **physics and domain** caveats in prose (Vina scores are not ΔG_binding in solution).

3. **Reproducibility:** a research article still needs **enough** methodological specificity (tool, allele panel, receptor accession) to replicate — but that is **Methods**, not **Abstract**.

**Required fixes (applied in v1.0)**

- **Inhibitor:** clearly separate (i) **primary chained analysis** suitable for main Results from (ii) **historical audit run** cited only where methodological lessons require it.
- **Plan A:** disclose **fixed two-allele panel** and **MHCnuggets-only** predictor choice as **limitations on generalization**, not as “smoke test” jargon in the Abstract.
- **Generative step:** report **filter outcome** honestly in **Results** (scientific fact), interpret in **Discussion** (why strict filters may yield zero survivors).

---

## Consensus: what changed in v1.0 manuscripts

| Issue | Resolution |
|-------|------------|
| Tech-report tone | Replaced with **IMRaD** prose (Introduction → Methods → Results → Discussion → Conclusions). |
| Abstract clutter | Removed UUIDs, bucket paths, and failed-job language; **one** concise limitation clause each. |
| “Authors should…” | Replaced with **past-tense findings** or **third-person methods**. |
| Contribution | Each title + abstract now states **one** primary contribution (epitope landscape **or** integrated inhibitor triage). |
| Ethics | Audit-run ligand-feed caveat retained in **Methods/Limitations**, not **Abstract**. |

**Note:** v1.0 manuscripts still require **author names**, **funding**, **final figure files**, and **literature expansion** before submission.
