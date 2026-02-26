# Twitter/X Content — Launch Thread + Weekly Posts
**Account to create:** @BiomateAI
**Handle alternatives:** @BioMateAI, @Biomate_AI, @BioMate_io

---

## Launch Thread (post as a thread, 1/ through 8/)

**1/**
Introducing BioMate 🧬

Describe your bioinformatics analysis in plain English.
BioMate generates, configures, and runs the Nextflow pipeline.
No conda debugging. No SLURM scripts. No parameter lookup.

Texas beta open now — 50 invite codes 🧵

**2/**
The problem: wet-lab researchers have the biology questions.
Bioinformaticians have the pipeline knowledge.

Most groups have one without the other.

BioMate closes that gap.

**3/**
What makes it different from "ChatGPT write me a Nextflow pipeline":

→ 10,595 validated bioinformatics tools (not hallucinated ones)
→ Runs on YOUR infrastructure (local/Slurm/AWS Batch)
→ Evidence-graded QC gates — every threshold is published-citation-backed
→ Shows you the Nextflow code before running

**4/**
The QC governance piece is our core innovation.

Every threshold has a tier:
🥇 GOLD — universally accepted (cannot be overridden)
🥈 SILVER — community standard (can override with audit log)
🥉 BRONZE — field heuristic (fully adjustable)

We're writing this up as a Nature Methods paper.

**5/**
Named QC profiles for your specific protocol:

`rna_seq_ffpe` — lower alignment thresholds for degraded RNA
`scrna_cardiac` — adjusted mito% for cardiomyocytes (naturally high)
`metagenomics_soil` — soil samples have 40-58% classification (not a failure)
`cryo_em_spa` — full 23-step SPA pipeline with CryoSPARC integration

**6/**
Domains covered today:
✅ RNA-seq, scRNA-seq, WGS/WES
✅ ATAC-seq, ChIP-seq, metagenomics
✅ Cryo-EM SPA + Cryo-ET (23 steps)
✅ LC-MS/MS proteomics (MaxQuant, DIA-NN)
✅ Drug discovery (ADMET, docking, pharmacogenomics)

Built on Galaxy (20yr platform) + Nextflow execution

**7/**
Texas angle: we're also building for the energy-biology intersection.

Oil reservoir metagenomics (MEOR). Bioremediation genomics. Algae biofuels.

No other bioinformatics platform is talking about this — but there are dozens of labs in Houston and College Station doing exactly this work.

**8/**
Texas closed beta — 50 invite codes, free professional tier for 90 days.

→ DM us or [signup link]

If you try it and it doesn't work for your use case, tell us. We add workflows based on real researcher requests.

#bioinformatics #nfcore #rnaseq #metagenomics #scRNAseq #proteomics #cryoEM

---

## Weekly Post Templates (3x/week cadence)

### Week 1 — Educational

**Post 1: QC threshold explainer**
```
The most common RNA-seq QC mistake I see:

Using the same alignment rate threshold for:
→ Fresh frozen tissue (expect >85%)
→ FFPE samples (60-70% is normal, not a failure)
→ Single-cell (cell barcodes inflate mapping %, different baseline)

BioMate uses protocol-aware QC profiles that adjust automatically.

The FFPE RNA-seq threshold difference is ENCODE-validated [citation].
#bioinformatics #RNAseq #QualityControl
```

**Post 2: Tool count credibility post**
```
People ask: "How is BioMate different from asking an LLM to write Nextflow?"

The LLM might suggest STAR for alignment. Fine.
But it won't know:
→ Which version works with your genome build
→ Whether your data needs --soloFeatures for 10x
→ That your FFPE samples need --alignIntronMax 1 for degraded RNA

10,595 validated tools. 967 workflow templates.
Domain expertise baked in, not hallucinated.
#bioinformatics
```

**Post 3: Energy-biology angle (unique content)**
```
Did you know oil & gas companies use metagenomics?

MEOR (Microbially Enhanced Oil Recovery): 16S rRNA sequencing identifies
halophilic microbes in petroleum reservoirs that produce oil-displacing
fatty acids and CO2.

BioMate's metagenomics workflows run this analysis.
Texas energy sector, meet computational biology.

#bioinformatics #metagenomics #energybiotech #MEOR
```

### Week 2 — Feature spotlights

**Post 4: Pilot mode**
```
Running 200 samples through your scRNA-seq pipeline?

BioMate's auto-pilot mode:
1. Picks 10 representative samples
2. Runs the full pipeline
3. Reviews QC gates (mito%, genes detected, doublet rate)
4. Asks before committing the full cohort

Saves ~72 hours of compute if your protocol is wrong.
#scRNAseq #bioinformatics
```

**Post 5: Cryo-EM angle**
```
Full cryo-EM SPA pipeline in one command:

Import → Motion correction → CTF → Particle picking (Topaz/crYOLO)
→ 2D classify → Ab initio → Homogeneous refinement
→ CTF refinement → Sharpening

23 steps. CryoSPARC + RELION backend. QC gates at each stage.

BioMate handles the orchestration.
#cryoEM #structuralbiology #bioinformatics
```

**Post 6: Drug discovery angle**
```
Drug discovery bioinformatics pipeline:

1. ADMET prediction (absorption, distribution, metabolism, excretion, toxicity)
2. Molecular docking (AutoDock Vina / Gnina)
3. Pharmacogenomics (CYP2D6, TPMT, DPYD variant interpretation)
4. LC-MS/MS target engagement proteomics

All in one platform. All QC-governed.

BioMate beta — Texas open now.
#drugdiscovery #bioinformatics #pharmacogenomics
```
