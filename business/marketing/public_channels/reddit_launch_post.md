# r/bioinformatics Launch Post
**Subreddit:** r/bioinformatics (120K members)
**Post type:** Text post — "Show r/bioinformatics"
**Tone:** Honest, technical, not salesy — this community will smell marketing instantly

---

## Title options (pick one):

**Option A (most upvoted style):**
> Show r/bioinformatics: I built a platform where you describe your analysis in plain English and it runs the Nextflow pipeline — 50 Texas beta spots open

**Option B (problem-first):**
> Tired of spending 2 days debugging Nextflow configs instead of doing biology? We built BioMate — beta invite inside

**Option C (QC angle, for credibility):**
> Show r/bioinformatics: BioMate — evidence-graded QC governance for RNA-seq, scRNA, WGS, metagenomics, cryo-EM (open beta, 50 invite codes)

---

## Post body:

Hey r/bioinformatics,

I've been building BioMate for the past year and wanted to share it here for honest feedback.

**The problem we're solving:** Most wet-lab researchers have real biological questions but spend 80% of their time on pipeline plumbing — conda environments, Nextflow configs, SLURM scripts, parameter tuning. The biology gets lost.

**What BioMate does:** You describe your analysis in plain English ("run differential expression on my RNA-seq data, samples are FFPE, compare tumor vs normal, use DESeq2"). BioMate generates the Nextflow workflow, configures it correctly, runs it on your data, and monitors QC gates in real time.

**What makes it different from just asking ChatGPT to write Nextflow:**

1. **10,595 validated bioinformatics tools** indexed — it knows which tool actually works for your data type, not just which one sounds right
2. **Evidence-graded QC governance** — every QC threshold is cited (GOLD = universally accepted, SILVER = community standard, BRONZE = heuristic). You can override SILVER/BRONZE thresholds with audit logging. GOLD thresholds (like mapping rate floors) cannot be overridden.
3. **Named QC profiles** — 20 protocol-aware profiles like `rna_seq_ffpe`, `scrna_cardiac`, `metagenomics_soil`, `cryo_em_spa` that adjust thresholds to your specific protocol
4. **Pilot mode** — for large cohorts (>50 samples), it automatically runs a pilot on a subset, reviews QC, then asks before committing the full run

**Domains currently covered:**
- RNA-seq, scRNA-seq, WGS/WES, ATAC-seq, ChIP-seq, Hi-C
- Metagenomics (16S + WGS), environmental genomics
- Cryo-EM SPA (full 23-step pipeline) + Cryo-ET
- LC-MS/MS proteomics (MaxQuant, DIA-NN, OpenMS)
- Drug discovery (ADMET, molecular docking, pharmacogenomics)
- ...and ~15 more

**Execution:** Runs on local, AWS Batch, or Slurm. Backend is Galaxy (the 20-year-old bioinformatics platform) with Nextflow as the execution engine.

**Texas beta cohort:** We're starting with a Texas-focused beta (UT Southwestern, MD Anderson, Texas A&M, etc.) and opening 50 invite codes to the broader community. Free professional tier for 90 days.

Would genuinely appreciate feedback — especially from people who've tried tools like this before and found them frustrating. What would make this actually useful for your workflow?

Invite code request form: [link] or DM me directly.

---

**Anticipated critical questions to address in comments:**

- *"How is this different from nf-core?"* → nf-core is the pipeline library; BioMate is the orchestration layer on top. It uses nf-core pipelines internally.
- *"What if my analysis isn't supported?"* → Request it. We add workflows based on user demand, and the Galaxy tool catalog covers most things.
- *"Can I see the generated Nextflow code?"* → Yes, always. Every generated workflow is visible and editable before execution.
- *"What about data privacy?"* → Runs on your own infrastructure (local, your AWS account, your Slurm cluster). We never see your data.
