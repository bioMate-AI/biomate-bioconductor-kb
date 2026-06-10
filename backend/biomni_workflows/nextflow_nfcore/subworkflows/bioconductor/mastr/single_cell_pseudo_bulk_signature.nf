#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mastR — single_cell_pseudo_bulk_signature
// Convert single-cell RNA-sequencing data into pseudo-bulk samples and identify group-specific marker signatures.
// Input: user_scRNA_counts.RData, user_scRNA_metadata.RData
// Container: quay.io/biocontainers/bioconductor-mastr:1.10.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, mastR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Aggregate single-cell counts into pseudo-bulk samples using pseudo_samples(). 2. Convert the pseudo-bulk matrix into a DGEList obj

nextflow.enable.dsl = 2

process BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(mastR)
    library(edgeR)
    
    # Load user inputs from the working directory
    env_counts <- new.env()
    load("user_scRNA_counts.RData", envir = env_counts)
    counts_obj_name <- names(env_counts)[1]
    counts <- env_counts[[counts_obj_name]]
    
    env_meta <- new.env()
    load("user_scRNA_metadata.RData", envir = env_meta)
    meta_obj_name <- names(env_meta)[1]
    meta <- env_meta[[meta_obj_name]]
    
    # Ensure counts is a matrix and meta is a data.frame
    counts <- as.matrix(counts)
    meta <- as.data.frame(meta)
    
    # 1. Aggregate single-cell counts into pseudo-bulk samples using pseudo_samples()
    pb <- pseudo_samples(counts, by = meta)
    
    # 2. Convert the pseudo-bulk matrix into a DGEList object
    pb <- edgeR::DGEList(counts = pb, group = gsub("\\\\..*", "", colnames(pb)))
    
    # Dynamically select the first available group as the target group
    target_group <- as.character(unique(pb\$samples\$group)[1])
    
    # 3. Run filter_subset_sig() to identify the target group's signature
    sig <- filter_subset_sig(pb, group_col = "group", target_group = target_group)
    
    # Write named output files for the meaningful results
    saveRDS(pb, "pseudo_bulk_dgelist.rds")
    saveRDS(sig, "target_group_signature.rds")
    write.csv(data.frame(Signature_Genes = sig), "target_group_signature.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE":',
        paste0('    mastR: ', as.character(packageVersion('mastR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_pseudo_bulk_signature.csv versions.yml
    """
}

workflow BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_scRNA_counts.RData, user_scRNA_metadata.RData ] ]

    main:
    BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE(ch_input)

    emit:
    tables   = BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE.out.tables
    plots    = BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE.out.plots
    objects  = BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE.out.objects
    versions = BIOC_MASTR_SINGLE_CELL_PSEUDO_BULK_SIGNATURE.out.versions
}
