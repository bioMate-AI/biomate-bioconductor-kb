# Blog draft — “From one structure to two discovery tracks” (ANDV in silico)

**Slug ideas:** `andv-two-tracks-nextflow`, `structure-to-epitope-biomate`  
**Tone:** confident but honest about demo vs production wiring.  
**Length target:** 900–1,200 words when expanded with screenshots.

---

## Lede

One viral structure on disk is not a program—it is a **forking point**. In our ANDV campaign we treated a deposited model as the shared root of two tracks: **small-molecule triage** (pocket → pharmacophore → ADMET → docking) and **immunoinformatics** (epitope prediction via nf-core). The interesting engineering story is not “we ran Docker,” it is **where workflows silently decouple** if you are not strict about file handoffs and cloud staging.

---

## What we actually shipped

- **Inhibitor stack:** four Nextflow steps with fat-finger-friendly HTML reports and machine-readable JSON. Pocket metrics and docking poses are satisfying artifacts for a blog: readers can *see* geometry and scores.
- **Epitope stack:** nf-core/epitopeprediction on **AWS Batch** with S3 inputs. The boring details matter: samplesheets on S3 need **absolute `s3://` paths** for sequence files, and nf-core profiles are not interchangeable with a generic `aws` label.
- **Plan B extras:** codon tool, RNA 2D, LNP workflow—useful as a sidebar on “adjacent automation” without derailing the virology narrative.

---

## The paragraph you should not skip (integrity)

Our own audit flagged a **chain-of-custody gap** on the demo inhibitor run: pharmacophore filtering produced one SMILES panel, while ADMET and docking consumed a **different fixed list**. Execution succeeded; the **scientific story** would be wrong if we claimed those steps consumed filtered hits without a re-run. Blogs age better when they say that plainly—and show the fixed diagram **after** rewiring.

---

## Figures for social and the post

1. **Hero image:** split panel—virus schematic (stock or custom illustration) + pipeline DAG snippet.  
2. **Animated GIF (optional):** HTML report scroll (timeline) to show “real software, real logs.”  
3. **One clean bar chart:** docking affinities or ADMET desirability (after ligand list is unified).  
4. **Epitope track:** peptide length histogram or allele coverage strip—very readable on Twitter/X.

---

## Call to action

- If you are reproducing: clone manifests, run `ensure_nfcore_epitopeprediction_worktree.sh` where applicable, pin Nextflow, and record **`run_id`**.  
- If you are collaborating: ask for the **manifest** first, not screenshots.

---

## Tags

`nextflow`, `nf-core`, `aws-batch`, `structural-biology`, `alphavirus`, `vaccine-informatics`, `docking`, `reproducibility`

---

## Published marketing pair (two-agent framing)

| Track | Substack | LinkedIn |
|-------|----------|----------|
| Inhibitor (4-step triage) | `business/marketing/blog_posts/post_10_substack.md` | `business/marketing/blog_posts/post_10_linkedin.md` |
| Plan A (epitopeprediction) | `business/marketing/blog_posts/post_11_substack.md` | `business/marketing/blog_posts/post_11_linkedin.md` |
| Inhibitor ZINC tiering (600 blog → publication HTS) | `business/marketing/blog_posts/post_12_substack.md` | `business/marketing/blog_posts/post_12_linkedin.md` |

## Related internal paths

- **Preprint (primary long-form):** `research/anti-virus/docs/MANUSCRIPT_DRAFT_ANDV_CAMPAIGN.md` (bioRxiv-oriented template, checklist, graphical abstract spec)
- `research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md`
- `research/anti-virus/runs/plan_a_exec_20260512T184220Z/EXECUTION_REPORT.md`
- `research/anti-virus/runs/plan_b_exec_20260512T184230Z/EXECUTION_REPORT.md`
