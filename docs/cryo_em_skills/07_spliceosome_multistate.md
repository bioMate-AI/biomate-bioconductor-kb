# Skill: Spliceosome Multi-State Analysis — Shi Lab (Nat Commun 2024)

**Paper:** "Molecular basis for the activation of human spliceosome"  
**Authors:** Zhan X, Lu Y, Shi Y  
**Journal:** Nature Communications, 2024 | DOI: 10.1038/s41467-024-50785-0  
**Why it matters for BioMate:** Completely different paradigm from membrane protein SPA — endogenous multi-MDa RNA-protein complex, multi-state classification from one dataset, glycerol gradient purification.

---

## 1. How This Differs From Standard SPA

```
STANDARD SPA (membrane protein)          SPLICEOSOME / LARGE RNP
────────────────────────────────         ──────────────────────────────
Single recombinant protein               Endogenous complex from cell extract
His-tag / FLAG affinity purification     Glycerol gradient sedimentation
One conformational state (agonist-bound) Multiple assembly intermediates (6+ states)
Target resolution: < 3 Å                Target resolution: 3.5–5 Å per state
100K–500K particles for final map        10K–50K particles per state (many classes)
One dataset → one structure              One dataset → 6 simultaneous structures
Model: AF2 prediction docked             Model: known snRNP crystal structures fit
```

---

## 2. Key Protocol Divergences

### Endogenous Purification (replaces recombinant expression)
```
Cell source: HeLa S3 cells (suspension, ~50L culture)
Nuclear extract preparation:
  1. Hypotonic lysis: swell cells, Dounce homogenize
  2. Salt extraction: 420 mM KCl releases nuclear proteins
  3. Dialysis: 150 mM KCl (removes salt)
  → Nuclear extract: ~4 mg/mL protein total

Stall spliceosome at target step:
  - B complex: use ATP + SF3b inhibitor (pladienolide)
  - B→Bact: add recombinant PRP2 helicase + ATP
  - Each step requires different reaction conditions

Glycerol gradient sedimentation:
  10–30% linear glycerol gradient (v/v)
  Spin: 200,000×g, 12–16 hr, 4°C (SW40Ti rotor)
  Fractions: 0.5 mL, 24 fractions total
  Spliceosome: sediments at ~40S (B) to ~50S (Bact)
  Detect: dot blot with anti-SmB antibody (spliceosome marker)
  Pool: 2–3 peak fractions → cryo-EM

QC:
  - Silver stain SDS-PAGE: complex band pattern (> 50 subunits!)
  - Northern blot: verify target snRNAs (U2, U5, U6) present
  - Negative stain: irregular particles ~20–30 nm

Typical yield: 0.05–0.5 mg from 50L culture
```

### Multi-State Classification Strategy
```
One cryo-EM dataset → multiple conformational intermediates:

Total particles collected: 500K–2M (larger sample needed)

Round 1 (global): 2D → 3D hetero refine, 8–12 classes
  → Separate: broken complexes, free snRNPs, intact spliceosome

Round 2 (focused): Take intact spliceosome class
  → 3DVA (3D variability analysis): 5 components
  → Component 1: PRP2 helicase position (major motion)
  → Component 2: U2 snRNP rotation

Round 3: Sub-classify along each component trajectory
  → Cluster: K-means into 4–6 clusters per component
  → Each cluster = one intermediate state

Final maps:
  B complex: ~3.8 Å
  B* complex: ~4.2 Å
  Bact complex: ~3.5 Å
  (Resolution limited by conformational averaging, not particle count)

Key principle: DO NOT force homogeneous refinement on heterogeneous sample.
Accept that each state will have moderate resolution.
```

### Model Building for Multi-Subunit RNP
```
Spliceosome = ~50 protein subunits + 5 snRNAs + pre-mRNA substrate

Strategy:
  1. Collect known crystal structures of each snRNP module:
     - U1 snRNP: PDB 3PGW
     - U2 snRNP SF3b: PDB 5IFE  
     - U4/U6.U5 tri-snRNP: PDB 5O9Z
  2. Rigid-body dock each module into state-specific map
  3. Fit RNA using phenix.fit_loops (RNA-specific)
  4. Rebuild unique loop regions in Coot
  5. PHENIX real_space_refine with RNA restraints
  
For novel proteins (not in any structure):
  - AlphaFold2 prediction per protein
  - Dock if density is > 5 Å in that region
  - Do not build < 5 Å regions (insufficient detail)

RNA fitting:
  phenix.real_space_refine with:
    --nucleotide_restraints
    --rna_sugar_pucker_restraints
  ERRASER for RNA sugar pucker correction
```

---

## 3. BioMate Gaps for Spliceosome-type Work

| Gap | Priority | Action |
|-----|----------|--------|
| Glycerol gradient purification guidance | P1 | Add protocol: sucrose/glycerol gradient parameters, rotor choice, fraction collection |
| Multi-state classification workflow | P0 | 3DVA interpretation guide + K-means clustering of components |
| RELION 3D multi-body for large RNPs | P1 | Document body definition strategy for modular complexes |
| RNA structure modeling | P2 | ERRASER + RNA-specific PHENIX restraints |
| Nuclear extract preparation | P2 | HeLa cell culture scale-up protocol |
| snRNP module library | P2 | Database of known snRNP PDB structures for common RNPs |

---

## 4. Key Principles for BioMate

1. **Endogenous purification requires stalling the complex at a defined state:** Spliceosome at any given intermediate is a fleeting snapshot. To capture it: add specific inhibitors (pladienolide for B), remove/add specific helicases (PRP2 for Bact). BioMate must ask: "At what functional state do you want to capture the complex?" before suggesting purification strategy.

2. **One dataset → multiple papers (multi-state):** Shi lab routinely publishes 5–6 simultaneous spliceosome structures from one cryo-EM session. The key is not collecting more data — it's better 3D classification. BioMate should always suggest 3DVA for large conformationally heterogeneous complexes.

3. **Glycerol gradient replaces affinity column for endogenous complexes:** Without an overexpressed affinity tag, the complex is isolated by its sedimentation coefficient (size + shape). This enriches the native complex including all transient associated factors that an affinity tag would miss. Resolution is lower than tag-purified, but biological authenticity is higher.

4. **Resolution expectation must be recalibrated for > 500 kDa flexible complexes:** At 3.5–5 Å, helices are resolved but sidechains are not. This is acceptable for large RNPs. BioMate should communicate: "For the spliceosome-scale complex, per-state resolution of 3.5–5 Å is world-class; sub-3 Å requires a fixed, rigid complex."

5. **RNA density looks different from protein density:** RNA backbone produces characteristic repeat patterns in cryo-EM maps. BioMate should note: use ERRASER/PHENIX RNA restraints, not standard protein refinement, for RNA-containing structures.
