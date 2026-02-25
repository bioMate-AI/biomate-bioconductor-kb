# Innovation Survey: Are BioMate's Claims Real?
**Date:** 2026-02-25 11:38
**Status:** Based on competitive landscape research — honest assessment
**Purpose:** Verify which claimed innovations survive peer review scrutiny

---

## Verdict Summary (Updated 2026-02-25 after full cryo-EM competitive survey)

| Claim | Domain | Verdict | Reason |
|---|---|---|---|
| **Interactive halt + require human decision** at QC failure | Both | ✅ **Genuinely novel** | All existing tools filter automatically (CryoSPARC Live) or alert only (Scipion) — none halt and require approval |
| Protocol-aware threshold profiles (biology-specific) | Both | ✅ **Genuinely novel** | No tool has membrane protein vs purified protein profiles, or phospho vs plasma proteomics profiles |
| Evidence-graded governance (GOLD/SILVER/BRONZE) | Both | ✅ **Genuinely novel** | Concept does not exist in any bioinformatics QC tool |
| Actionable parameter suggestions at failure | Both | ✅ **Genuinely novel** | No tool proposes specific parameter changes at the failing step |
| **Cryo-EM per-micrograph threshold rejection** (automatic) | Cryo-EM | ❌ **NOT novel** | CryoSPARC Live (2019), Warp (2019), RELION Schemes (2021) all do this |
| **Real-time cryo-EM monitoring** | Cryo-EM | ❌ **NOT novel** | CryoSPARC Live, Warp, TranSPHIRE, Scipion all do real-time monitoring |
| mzQC standard adoption | Proteomics | ⚠️ **Partially novel** | mzQC format exists (HUPO-PSI 2023); no tool uses it with governance |
| SMILES validation before ADMET | Drug discovery | ⚠️ **Partially novel** | RDKit sanitizes; but no governed pipeline gate exists |

---

## Cryo-EM: Detailed Assessment (Updated after full competitive survey 2026-02-25)

### Complete competitive landscape surveyed
Tools examined: CryoSPARC Live, RELION 4 Schemes, Scipion, TranSPHIRE, Warp, cryoAssess, CryoFLARE.
**Finding: No nf-core cryo-EM SPA pipeline exists as of February 2026** (confirmed by survey). Prior reference to "nf-core/crispy" in draft materials was incorrect — this pipeline does not exist.

### CryoSPARC Live — the most important competitor
CryoSPARC Live provides threshold-based exposure exclusion:
- Users set CTF, defocus, astigmatism, and motion score thresholds via sliders
- Exposures outside thresholds are marked "rejected" and excluded from downstream jobs (particles removed, jobs recalculated)
- **BUT:** the Live session does NOT halt; it continues processing new incoming data automatically
- The "Auto-Pause" in v5.0 is triggered by *no new data*, not by quality failure
- Exposure exclusion is silent and non-interactive — no human decision point

**The critical distinction:** CryoSPARC Live does automatic silent filtering. BioMate does interactive halting with human approval required. These are fundamentally different patterns: one removes bad data automatically and continues; the other stops the workflow and demands a decision before continuing.

### RELION 4 Schemes — automation with conditional branching
RELION 4 Schemes can implement conditional logic (Fork nodes, boolean variables, LT/GT operators). It applies a single global CTF quality filter at micrograph selection. However:
- No interactive halt-and-decide mechanism
- No named sample-type profiles
- No failure-time remediation suggestions
- Continues automatically through all branches

### Scipion monitors — alerts only
Scipion's `ProtMonitorCTF` sends email/notification alerts when defocus exceeds thresholds. It does NOT halt downstream protocol execution. Requires manual `right-click → STOP STREAMING` to stop.

### Other tools (TranSPHIRE, Warp, cryoAssess)
- **TranSPHIRE**: continuous feedback/re-training; no halt; no protocol profiles; no remediation suggestions
- **Warp**: real-time monitoring and confidence-threshold filtering; no halt; no interactivity
- **cryoAssess**: post-hoc ML classifier for micrograph/class quality; no halt; no protocol profiles

### What no tool does (BioMate's genuine cryo-EM differentiators)

**Differentiator 1: Interactive human-in-the-loop QC gate (halt + require decision)**
Every existing tool either filters automatically (CryoSPARC Live, Warp, RELION Schemes) or sends alerts (Scipion). None halt the pipeline and require explicit human approval before downstream execution continues. BioMate's SSE-driven gate — halt → surface failure + suggestion → await Proceed/Override/Abort decision → log outcome — does not exist in any competing tool.

**Differentiator 2: Protocol-aware named profiles for sample biology**
CryoSPARC Live's "Configuration Profiles" save microscope hardware settings (pixel size, voltage, Cs). They are instrument profiles, not sample-biology-aware profiles. No existing tool has named profiles with different drift/CTF thresholds for membrane protein vs. purified protein vs. in-situ tomography samples. This is completely novel.

**Differentiator 3: Failure-time actionable parameter suggestions**
All existing tools report metric values and mark data as rejected. None generate machine-authored text explaining *why* a failure occurred or *what specific parameter* to change. BioMate's suggestion engine ("Enable dose weighting; check gain reference"; "Widen CTF search range minimum") is entirely novel.

**Differentiator 4: Evidence-graded threshold governance**
CryoSPARC Live thresholds are user-defined with no citation provenance. RELION Schemes has a single CTF filter with no evidence tier. The GOLD/SILVER/BRONZE system — where evidence quality determines override permissions — does not exist in any cryo-EM or bioinformatics pipeline tool.

**Differentiator 5: Cross-domain portable audit trail**
CryoSPARC Live's QC decisions are locked inside CryoSPARC's proprietary job history. BioMate produces a portable JSONL audit trail with decision, evidence level, override approver, and timestamp — usable for EMDB deposition, FDA submissions, and cross-site reproducibility.

### Revised cryo-EM innovation claim (survives peer review)
> "BioMate provides the first interactive QC governance framework for cryo-EM SPA, combining pipeline-halting gates that require explicit human approval, sample-biology-aware threshold profiles, failure-time parameter suggestions, and evidence-graded override governance — extending beyond the automatic exposure filtering of CryoSPARC Live to supervised, audited decision governance."

**Retire:** "first real-time cryo-EM QC gates" — CryoSPARC Live (2019), Warp (2019), TranSPHIRE (2020) all predate BioMate. The novelty is the *interactivity*, the *protocol profiles*, the *suggestions*, and the *evidence governance* — not the monitoring itself.

---

## Proteomics: Detailed Assessment

### What PTXQC already does (partially overlaps)
PTXQC (Bielow et al. 2016, J Proteome Res) generates comprehensive MaxQuant QC reports:
- Checks protein/peptide FDR, CV, missed cleavages, mass accuracy, RT stability
- Produces HTML reports with pass/warn/fail colour coding
- BUT: **post-hoc only** — runs after MaxQuant completes, does not halt execution
- No protocol-aware profiles
- No evidence-graded governance
- No SMILES or drug discovery integration

### What mzQC exists as (partially overlaps)
The HUPO-PSI mzQC format (Bittremieux et al. 2023, MCP) is a community standard JSON format for proteomics QC metrics with 100+ controlled vocabulary terms. **Currently used for reporting only** — no execution platform implements it with governed threshold checking.

### What QCloud/iMonDB does (partially overlaps)
QCloud (Chiva et al. 2018) and iMonDB monitor instrument performance over time — drift, sensitivity, mass accuracy. These are **instrument-level monitoring tools**, not analysis pipeline governance tools. They do not check biological QC (protein FDR, phosphosite localization, pulldown enrichment).

### What the 2024 JPR framework paper shows (confirms the gap)
Bittremieux et al. 2024 (J Proteome Res, "A Framework for Quality Control in Quantitative Proteomics") explicitly states: *"there is no common method for instrument control, resulting in different thresholds for assessing quality across labs"* and calls for standardized, automated QC governance. This is BioMate's exact contribution — the paper describes the gap; BioMate fills it.

### What no tool does (BioMate's genuine proteomics differentiators)

**Differentiator 1: Execution halting — the critical gap**
Every existing tool (PTXQC, QCloud, OpenMS/pmultiqc, MSstats) produces a report after analysis completes. None halt execution when QC fails. BioMate is the first to stop the pipeline at the failing step — preventing downstream compute waste.

**Differentiator 2: Protocol-aware profiles for proteomics experiment types**
No tool distinguishes phosphoproteomics (lower PSM count acceptable, localization score critical) from standard DDA (higher PSM count, no localization requirement) from plasma biomarker (tighter CV, missing value gate). This is a direct parallel to the cryo-EM membrane protein profile — genuinely novel.

**Differentiator 3: mzQC as governance (not just reporting)**
Existing mzQC implementations read metrics and output reports. BioMate would be the first to use mzQC controlled vocabulary terms as governed threshold identifiers — where the CV term determines whether the threshold is GOLD or BRONZE and who can override it.

**Differentiator 4: Drug discovery-specific gates**
Pulldown enrichment ratio, phosphosite localization governance, and SMILES structure validation before ADMET — none of these exist in any proteomics QC tool because they are drug discovery workflow gates, not general proteomics gates.

### Revised proteomics innovation claim (survives peer review)
> "BioMate is the first platform to implement mzQC-governed, protocol-aware QC with execution halting for LC-MS/MS proteomics, extending from standard DDA to phosphoproteomics and plasma biomarker workflows within an integrated drug discovery pipeline."

---

## Cross-Domain: What Genuinely Does Not Exist Anywhere

These four properties together do not exist in any tool — individually some overlap, but the combination is novel:

1. **Execution halting** (not just reporting) when QC fails
2. **Protocol-aware profiles** that adjust thresholds for sample type without user intervention
3. **Evidence-graded governance** where citation quality determines overridability (no GOLD/SILVER/BRONZE concept exists anywhere in bioinformatics)
4. **Audit trail** of every QC decision with evidence level, override approver, and timestamp

The correct high-level novelty claim is: **BioMate is the first platform to implement governed QC — where evidence quality determines threshold authority — across multi-omics workflows, with execution halting and protocol-aware profiles.**

The word "governed" is the key differentiator. Everything else is reporting.

---

## Claims to Retire Immediately

These will not survive peer review:

| Retired claim | Why | Replace with |
|---|---|---|
| "First real-time cryo-EM QC gates" | CryoSPARC Live (2019), Warp (2019), TranSPHIRE (2020) all predate BioMate | "First interactive, human-supervised QC gate framework with sample-biology-aware profiles" |
| "First cryo-EM pipeline to halt on QC failure" | Needs precision — CryoSPARC Live silently filters; BioMate **halts and requires human approval** — "halt" is accurate but must be defined precisely as "interactive halt awaiting human decision" |
| "First to implement mzQC" | mzQC format has existing implementations | "First to implement mzQC metrics with execution governance and protocol-aware profiles" |
| "nf-core/crispy has no QC governance" | No nf-core cryo-EM pipeline exists at all (confirmed February 2026) | Remove entirely; use CryoSPARC Live as the automated comparator |
| "BioMate halts execution unlike MultiQC" | True but trivially different from saying "we are not a report generator" | Focus on what BioMate does, not what MultiQC doesn't |
| "15% of ChEMBL compounds have SMILES errors" | Whitehead et al. 2022 cite cannot be verified; may be from a specific database version | Verify citation before using; if unverifiable, run BioMate's own ChEMBL analysis and report observed rate |

---

## What This Means for the Papers

### Cryo-EM paper: revised positioning
- **Lead with**: interactive human-in-the-loop gate (vs. CryoSPARC Live's silent automatic filtering); protocol-aware profiles; actionable suggestions; evidence governance
- **Primary comparator**: CryoSPARC Live (not "no QC") — the comparison is automatic-silent-filter vs. interactive-halt-and-approve
- **Key differentiating experiment**: Run TRPV1/EMPIAR-10005 (membrane protein) through both CryoSPARC Live (with purified protein thresholds) and BioMate. CryoSPARC Live silently rejects good membrane protein micrographs. BioMate fires the gate, user sees "membrane protein — drift threshold may be too strict for lipid-bilayer embedded particles," user overrides with logged justification, pipeline completes with better micrograph retention. This is the story: *not* that BioMate catches something CryoSPARC Live misses — it is that BioMate shows the investigator what happened and gives them agency.
- **Second comparator**: RELION 4 Schemes (open-source automated path)
- **Drop**: all references to nf-core/crispy (does not exist)

### Proteomics paper: positioning is strong as-is
- All 4 core claims survive. The 2024 JPR paper literally describes the problem BioMate solves.
- Lead with the 2024 JPR framework paper as the "gap this paper fills"
- PTXQC comparison is essential: show BioMate catches failures before analysis runs; PTXQC catches them after

### Shared platform paper (Paper 1): unchanged
- Evidence-graded governance is the core claim — confirmed genuinely novel
- No existing tool has the GOLD/SILVER/BRONZE concept or the community-standard citation-backed threshold hierarchy

---

## Sources Found in Survey

### Cryo-EM sources
- CryoSPARC Live documentation: https://guide.cryosparc.com/live/about-cryosparc-live
- CryoSPARC Live session-level functions: https://guide.cryosparc.com/live/live-jobs-and-session-level-functions
- CryoSPARC v5.0 Auto-Pause feature: https://cryosparc.com/updates/v5.0
- RELION 4 Schemes: https://relion.readthedocs.io/en/release-4.0/Reference/Schemes.html
- New tools in RELION-4.0 (Biochem J): https://portlandpress.com/biochemj/article/478/24/4169/230248/New-tools-for-automated-cryo-EM-single-particle
- Scipion CTF monitor: https://scipion-em.github.io/docs/modules/pyworkflow/em/protocol/monitors/protocol_monitor_ctf.html
- Scipion3 workflow engine (Biological Imaging): https://www.cambridge.org/core/journals/biological-imaging/article/scipion3
- TranSPHIRE (Nature Commun 2020): https://www.nature.com/articles/s41467-020-19513-2
- Warp (Nature Methods 2019): https://www.nature.com/articles/s41592-019-0580-y
- cryoAssess/MicAssess (Cell Structure 2020): https://www.cell.com/structure/fulltext/S0969-2126(20)30207-0
- CryoFLARE (JCIM 2020): https://pubs.acs.org/doi/10.1021/acs.jcim.9b01102
- Topaz (Nature Methods 2019): https://www.nature.com/articles/s41592-019-0575-8
- EMDB policies: https://www.ebi.ac.uk/emdb/documentation/policies

### Proteomics sources
- PTXQC: https://github.com/cbielow/PTXQC (Bielow et al. 2016, J Proteome Res)
- mzQC framework: Bittremieux et al. 2023, Molecular & Cellular Proteomics
- 2024 QC framework gap paper: https://pubs.acs.org/doi/10.1021/acs.jproteome.4c00363
- QCloud: Chiva et al. 2018
- Scipion facilities plugin: https://github.com/scipion-em/scipion-em-facilities
