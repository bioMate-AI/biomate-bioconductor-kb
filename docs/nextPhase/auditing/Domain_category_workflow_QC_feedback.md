1. Domain category of workflows:
BioMate workflows are organized by domain folder:
- `pharmacology/` — ADMET, docking, drug combinations, FDA labels
- `drug_discovery/` — pocket detection, pharmacophore filtering, REINVENT4, MOE, Schrödinger
- `genomics/` — germline, somatic, WGS, panel
- `single_cell/` — scRNA-seq, trajectory, CITE-seq
- `cryo_em/` — motion correction, CTF estimation, particle picking, 3D reconstruction
- `bioconductor/` — R-based analysis
- `physiology/` — PK/PD models
- `bioengineering/` — stability assays, formulation analysis
- `imaging/` — microscopy analysis

Response: pharmacology and drug_discovery should be the same, bioconductor should be more fine granular, double check the categories.
1. make sure there is no duplicate R wrapper and existing workflows
2. for duplicate r wrapper and existing workflows, what are the difference?
3. make sure there is no ambiguous domain categories, merge categories for both tools and workflows if necessary. make sure the categories of tools and workflows are consistent.

2. ### Leveraging Existing Workflows to Build New Ones

**Current mechanism:** The LLM in `nextflow_composer.py` can include any available tool from the catalog. When generating a custom workflow, it can reference existing subworkflow processes.

**Gap:** There is no automatic "compose a new workflow from existing subworkflow blocks" feature. The system generates fresh Nextflow code rather than composing from tested subworkflow modules. A future improvement would be to have the generator search for matching nf-core subworkflows (e.g., `bam_sort_stats_samtools`) and `include` them rather than regenerating.

If so, how exactly is the code doing to leverage existing workflows? 
    Chain workflow/sub-workflow/tools
            May need to rewrite the workflow code, what skill file is used here to avoid common errors?
            

3. **Gap:** The QC Gate currently reads from BioMate Nextflow trace files. For standard nf-core pipelines (run via `nextflow run nf-core/rnaseq`), the trace file format should be compatible, but this has not been systematically verified across all 230 nf-core pipelines.

First of all, there should be more than 230 workflows; second, double check the consistency of the QC steps and the QC gates, third, make sure the QC report htmls can be directly accessible in UI, fourth, the QC profile selection should be very straight forward intuitively according to different workflows, which can be prepared ahead most of the time, double check the current solution.



