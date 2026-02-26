# nf-core Slack Announcement
**Channel:** #tools or #general or #announcements
**Tone:** Collegial, technically honest — this is a sophisticated audience

---

## Message:

Hi nf-core community 👋

I wanted to share a project that's built on top of nf-core pipelines and might be interesting to this community: **BioMate** — an AI orchestration layer that lets researchers describe their analysis in plain English and get a configured, running Nextflow workflow.

**How it relates to nf-core:**
BioMate uses nf-core pipelines (rnaseq, scrnaseq, sarek, chipseq, atacseq, mag, viralrecon, etc.) as the execution backend. It handles the parameter configuration, profile selection, and QC monitoring on top — the parts that are still hard for wet-lab researchers without Nextflow experience.

**What we've added:**
- Evidence-graded QC governance (GOLD/SILVER/BRONZE tier thresholds with published citations for each)
- Named QC profiles (`rna_seq_ffpe`, `scrna_cardiac`, `metagenomics_soil`) that adjust thresholds per protocol
- Real-time SSE-based QC gate monitoring during execution
- Auto-pilot mode for large cohorts (pilot subset → QC review → full run)

**We're not trying to replace nf-core** — we're trying to make it accessible to the thousands of researchers who have the biology questions but not the Nextflow expertise. Think of it as a researcher-facing application layer.

Texas closed beta is open now (50 invite codes, free for 90 days). Would love feedback from people in this community, especially on whether our nf-core integration is idiomatic or if we're doing something terrible 😅

More info: [biomate.ai] | Beta signup: [link]

Happy to answer any questions here.

---

## Follow-up message (if someone asks about the pipeline generation):

The workflow generation uses Claude (Anthropic) with a 10,595-tool knowledge base derived from the Galaxy tool shed + Bioconductor package KB + nf-core module catalog. When it picks tools, it's drawing from validated tool metadata, not generating tool names from scratch.

The generated Nextflow code is always shown to the user before execution — they can edit it or run it as-is. We're not hiding the pipeline.
