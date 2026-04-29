# CryoEnsemble: Approach Assessment, Competing Methods, and Protein Expansion

**Date:** 2026-04-29  
**Context:** Answering whether CryoEnsemble uses the most advanced approach; whether it helps with RNA/single-cell; and expanding the protein benchmark to 16 proteins with membrane protein emphasis.

---

## 1. Is CryoEnsemble the Most Advanced Approach?

### Honest answer: Advanced but not frontier on every dimension.

**What we have that is genuinely novel:**

| Contribution | Status |
|---|---|
| Per-particle likelihood × BioEmu prior (Bayesian posterior) | Novel combination, unpublished |
| Conformational completeness gap as a quantitative metric | New metric, no prior definition |
| Formal proof that map-level reweighting cannot recover rare states | New theoretical result |
| Targeting states *below* the reconstruction floor specifically | Not addressed by any competitor |

**What competitors do better:**

| Method | Venue | Advantage over CryoEnsemble | Limitation |
|---|---|---|---|
| Latent-space diffusion (end-to-end) | PMC12282479, 2024 | Diffusion prior learned jointly with cryo-EM likelihood — tighter coupling | Doesn't target sub-reconstruction-floor states; single-chain Cα |
| CryoPhold / CryoBoltz | biorxiv 2025 | AlphaFold3 diffusion head — all-atom, multi-chain | Heterogeneity conditioning still indirect; no rare-state proof |
| RECOVAR | PNAS 2025 | Statistically rigorous PCA with FSC regularization; calibrated densities | Classical, no prior, no rare-state mechanism |
| cryoDRGN-AI | Nat Methods 2025 | Better pose estimation (neural ab initio) | Doesn't recover states below reconstruction floor |
| MCGDiff | NeurIPS 2023 | Score-based diffusion posterior — theoretically optimal Bayesian framework | Not yet validated on rare-state recovery; not cryo-EM-specific |

**The key differentiation that holds:**  
Every competing method targets states that are *already present in the cryo-EM particle distribution*. They improve accuracy within the observable population. CryoEnsemble is the only method specifically motivated by states that never made it into the particle stack — the vitrification bias / resolution floor problem. This is a distinct and currently unaddressed problem.

**The weakest point:**  
BioEmu operates on single-chain Cα atoms only. For GPCRs bound to G-proteins, for ABC transporters, for multi-subunit complexes — the relevant conformational change is inter-chain. AlphaFold3-based priors handle this naturally. This is the Year 2 upgrade path: replace BioEmu with AF3 diffusion head as the prior, retaining the per-particle likelihood framework.

**What the most theoretically advanced approach looks like (not yet implemented by anyone):**
```
Full score-based diffusion posterior:
  P(x | Y) ∝ ∏_i L(y_i | x, φ_i, Ω_i) × p_θ(x)
  
where p_θ is a score network trained on BioEmu/AF3 MD data,
and inference uses annealed importance sampling or DPS-style
score distillation — not importance weighting.
```
This is the natural Year 2-3 implementation target. Year 1 (current proposal) validates the per-particle likelihood mechanism and the gap metric.

---

## 2. Does CryoEnsemble Help with Single-Cell RNA / RNA-seq?

### No. Different domain, different tools.

CryoEnsemble is a structural biology method: cryo-EM particle images in → posterior conformational ensemble out. It has no connection to:

- **scRNA-seq** (single-cell transcriptomics — gene expression, not structure)
- **Bulk RNA-seq** (differential gene expression)
- **RNA structure** (folding, secondary structure — possible future extension but different tools)

**The conceptual analogy exists but the methods don't transfer:**  
Rare cell states in scRNA-seq face an analogous detection floor problem (rare populations undersampled). But the solution — trajectory inference, imputation, pseudotime — uses completely different mathematical machinery.

**What BioMate already does for RNA/single-cell:**  
This is covered by nf-core/rnaseq, scRNA-seq workflows, and the existing 865 transcriptomics workflows in the BioMate database. These are separate, mature capabilities on the platform.

**One indirect connection worth noting:**  
If CryoEnsemble identifies a cryptic allosteric pocket on a GPCR, knowing which tissues express that GPCR at therapeutically relevant levels requires scRNA-seq analysis. BioMate integrates both ends of this pipeline — but as independent tools, not a unified method.

---

## 3. Protein Benchmark Expansion: 10 → 16 Proteins

### Rationale

Given that the sister's lab focuses on membrane proteins and GPCRs, and that vitrification bias is most severe for membrane-embedded systems, the benchmark was expanded from 10 to 16 proteins with membrane proteins now comprising 10/16 (63%).

### Six new proteins added

| Protein | PDB | Category | Why added |
|---------|-----|----------|-----------|
| **A2A adenosine receptor** | 3EML | GPCR A | Best-characterized allosteric GPCR; Parkinson's target; extensive smFRET data for validation |
| **GLP-1 receptor** | 6X18 | GPCR B (Class B) | Semaglutide/tirzepatide target; massive clinical relevance; Class B GPCRs have larger conformational changes |
| **5-HT2B serotonin receptor** | 4IB4 | GPCR A | Well-studied ECL2 gating; psychiatric drug target |
| **TRPA1** | 3J9P | TRP channel | Ankyrin-repeat remodeling (large N-terminal motion); complements TRPV1 |
| **ASIC1a** | 2QTS | Ion channel | 8 Å thumb domain motion between open/closed/desensitized; well-characterized conformational ensemble |
| **SERT** | 5I6X | Transporter | Alternating-access mechanism (10+ Å); SSRI antidepressant target |

### Full 16-protein set

```
Membrane proteins (10):
  GPCRs:     β₂AR, μOR, A2A, GLP-1R, 5-HT2B
  Channels:  TRPV1, TRPA1, ASIC1a, KcsA
  Transport: SERT

Soluble controls (6):
  Enzymes:   ADK (open + closed pair), HIV-1 RT
  Other:     Hsp90, p53 DBD, Calmodulin
```

### Planned pilot runs (after Pilot 0/2 validate the pipeline)

Priority for real BioEmu runs (after v1.0.5 Pilot 0 lands):
1. **A2A** — has published smFRET data (Bhattacharya et al.) for posterior validation
2. **GLP-1R** — highest clinical relevance; EMPIAR data available (EMPIAR-10756)
3. **SERT** — strong structural biology from sister's field; EMPIAR data available

PDB files for the 6 new proteins:
```bash
# Download and upload to S3
for pdb in 3EML 6X18 4IB4 3J9P 2QTS 5I6X; do
  wget -q https://files.rcsb.org/download/${pdb}.pdb
  aws s3 cp ${pdb}.pdb s3://biomate-nextflow-work/pilot/pdbs/${pdb,,}.pdb
done
```

---

## 4. What's Needed to Validate on the 6 New Proteins

### Immediate (this week, before May 1 proposal)
- [ ] Add 6 new PDBs to S3 pilot bucket
- [ ] Add to `gap_analysis.py` simulated-mode protein list
- [ ] Run simulated gap analysis (confirms 10% gap — expected by construction)

### Near-term (Year 1 of funded project)
- [ ] Run real BioEmu Pilot 0 for A2A (priority: smFRET validation data available)
- [ ] Run real BioEmu Pilot 0 for GLP-1R (priority: clinical impact)
- [ ] Collect EMPIAR data for SERT, A2A, GLP-1R — run real cryoDRGN gap analysis

### Year 2 upgrade (AF3 prior)
- Replace BioEmu single-chain Cα with AlphaFold3 diffusion head
- Enable multi-chain: GPCR + G-protein complex, ABC transporters
- This addresses the main weakness vs CryoPhold/CryoBoltz

---

## 5. Summary Recommendation

**CryoEnsemble is worth pursuing because:**
1. The gap it addresses (sub-reconstruction-floor conformers) is real and unaddressed by all competing methods
2. The proof of map-level reweighting insufficiency is a genuine theoretical contribution
3. The membrane protein focus is exactly where the problem is worst and where the sister's lab has domain expertise
4. The per-particle likelihood framework is extensible to the more advanced score-based posteriors (natural upgrade path)

**The two honest weaknesses to address in the proposal:**
1. Single-chain Cα limitation — acknowledged, Year 2 AF3 upgrade planned
2. No CryoBench benchmark comparison yet — needs to be a Year 1 deliverable

**RNA/single-cell: not applicable to CryoEnsemble, but BioMate handles these via separate workflows.**
