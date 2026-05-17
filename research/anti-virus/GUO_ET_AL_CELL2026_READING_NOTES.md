# Reading notes: Guo et al., *Cell* 2026 — ANDV glycoprotein structures

**Source PDF**: `anti_hanta.pdf`  
**Citation**: Guo L. et al., *Cell* **189**, 2731–2747 (2026). https://doi.org/10.1016/j.cell.2026.01.030  
**Purpose**: Extract biology, structure, and assay context for the BioMate ANDV GP inhibitor / SBDD track (companion to `ANDV_INHIBITOR_TRACK_IMPLEMENTATION.md`).

---

## 1. Disease and entry (context)

- **ANDV** (New World hantavirus) causes **hantavirus cardiopulmonary syndrome (HCPS)**; case fatality cited up to ~40%. No approved vaccines or therapeutics in the article framing.
- **Entry**: virus binds **protocadherin-1 (PCDH1)**; after endocytosis, **acidic endosomes** trigger conformational changes: **release of Gc from the Gn–Gc complex** and transition of **Gc** toward **postfusion** for membrane fusion.
- **Gn and Gc** are the primary surface antigens and neutralizing-antibody targets.

---

## 2. Deposited structures (align with implementation plan)

Public coordinates/maps match the paper’s **Data availability** section:

| System | PDB | EMDB |
|--------|-----|------|
| ANDV tetramer | 9P3I | EMD-71241 |
| Dimer of tetramers, conformation I | 9P3X | EMD-71258 |
| Dimer of tetramers, conformation II | 9P3M | EMD-71243 |
| Dimer of tetramers, conformation III | 9P3L | EMD-71242 |
| Tetramer + ADI-65534 Fab | 9P3Y | EMD-71259 |
| ADI-65534-bound dimer of tetramers | *(map-focused deposit)* | EMD-71260 |

**Modeling implications**

- **9P3I** (~2.35 Å): best resolved **single tetramer** — primary choice for **atomic pocket** work.
- **9P3X / 9P3M / 9P3L**: same biological unit in **three hinged conformations** — account for **conformational plasticity** (ensemble docking, induced fit, or worst-case pose checks).
- **9P3Y**: **Fab epitope** and quaternary context for **avoiding clash** or designing **orthogonal** sites vs antibody.

---

## 3. Experimental system vs wild-type virion

- High-resolution work uses **ANDV-DM-eVLP** with mutations **V535K** and **S1096L** (and **eVLP tag**) to improve particles for cryo-EM.
- Authors note **authentic virions** may differ subtly (e.g. **lipid environment**, lattice context). Document which PDB state matches which planned assay (e.g. pseudotype vs VLP).

---

## 4. Mechanism hotspots (relevant to small molecules)

The paper stresses **pH-dependent destabilization** of prefusion interfaces via **histidine protonation** and electrostatic repulsion (analogy to HA, flavivirus E, VSV G).

**Highlighted residue regions** (starting points for literature-informed SAR / overlays, not automatic drug pockets):

- **GnH2–Gc1**: **His716, His820, His935** on Gc adjacent to a **positively charged GnH2** surface (**Lys21, Arg169**, **Pro20**); suggested link to **acid-driven tetramer dissociation**.
- **GnB2–Gc stem**: **His1064** (Gc) near **Lys448** (GnB2).
- **GnH1–Gc1**: **His279, His285** in a region interacting with **Gc lysines**.
- **Inter-tetramer Gc–Gc interface**: **His953** from opposing protomers — proposed **pH-triggered repulsion** contributing to **Gc homodimer** disruption and **lattice** disassembly.

**Prior functional mutations** (cited fusion work): **Glu677, Asp679, Arg951, His953** — fusion defective when mutated; useful for **cross-species conservation** and **selectivity** reasoning.

---

## 5. Antibody ADI-65534 (context for complementary design)

- **Fab** structures enable EM fitting; **full IgG1** geometry is argued to **not** bridge neighboring tetramers efficiently without extreme Fab elbow angles; **IgG3** backbone gave **~3×** improved neutralization vs IgG1 in their rVSV-ANDV assay — **avidity and geometry** matter on the lattice.
- **Small-molecule takeaway**: affinity on a single protomer may be insufficient; consider **quaternary** or **multivalent** hypotheses where consistent with data.

**IP / reagents**: authors declare interest in patent applications on **anti-hantavirus antibodies** including ADI-65534; unique reagents may require **MTA** (lead contact per paper).

---

## 6. Assays mentioned (alignment with downstream validation)

- **Neutralization**: **rVSV-ANDV** with GFP readout (infectivity / GFP+ cells) — conceptually parallel to **pseudotype** screening in a therapeutic pipeline.
- **Immunogenicity**: **repRNA/LION** in mice — **binding** titers do not always track **neutralizing** titers; **eVLP** variants improved binding in some conditions but **neutralization** was not uniformly superior to **WT GPC**. This is primarily **vaccine** learning, but it reinforces using **functional entry/neutralization** endpoints for candidates, not ELISA alone.

---

## 7. Software / “code availability”

- Paper states **no original code**; cryo-EM used standard tools (e.g. cryoSPARC, crYOLO, ChimeraX, Phenix, Coot, DeepEMhancer/EMReady, AlphaFold3 for auxiliary modeling). BioMate inhibitor work remains free to publish **new** analysis scripts and Zenodo datasets.

---

## 8. Suggested updates to `ANDV_INHIBITOR_TRACK_IMPLEMENTATION.md`

- Replace placeholder PDB language with the **9P3I / 9P3Y / 9P3X / 9P3M / 9P3L** IDs above.
- Add a short **“mechanism anchors”** subsection: interface **His** clusters + cited **Gc** fusion mutants for cross-checking **orthohantavirus** conservation.
- Explicitly choose **primary docking receptor(s)**: apo **9P3I** vs Fab-bound **9P3Y** vs ensemble of **dimer-of-tetramer** models.
- Note **ANDV-DM** background when comparing to assays that use **WT** glycoproteins.

---

**Document version**: 1.0 (May 2026)
