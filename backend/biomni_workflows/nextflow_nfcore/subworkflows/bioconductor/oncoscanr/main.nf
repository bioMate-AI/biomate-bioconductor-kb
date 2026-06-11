#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oncoscanr — chas_custom_workflow
// Load, clean, and perform custom step-by-step analysis of ChAS CNV data to compute individual HRD, TDplus, and arm-level alteration scores.
// Input: chas_file.txt
// Container: quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0
// R packages: jsonlite, magrittr, oncoscanR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("jsonlite", "magrittr", "oncoscanR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(oncoscanR)
    library(magrittr)
    
    # Define input file path
    chas.fn <- "chas_file.txt"
    
    # Check if the input file exists
    if (!file.exists(chas.fn)) {
      stop(paste("Error: Input file", chas.fn, "not found in the working directory."))
    }
    
    # 1. Load the ChAS file
    segments <- load_chas(chas.fn, oncoscan_na33.cov)
    
    # 2. Clean the segments: restricted to Oncoscan coverage, LOH not overlapping
    # with copy loss segments, smooth & merge segments within 300kb and prune
    # segments smaller than 300kb.
    segs.clean <- trim_to_coverage(segments, oncoscan_na33.cov) %>%
        adjust_loh() %>%
        merge_segments() %>%
        prune_by_size()
    
    # Save the cleaned segments as an RDS object
    saveRDS(segs.clean, "cleaned_segments.rds")
    
    # 3. Compute the arm-level alteration for loss and LOH since many 
    # scores discard arms that are globally altered.
    arms.loss <- names(get_loss_segments(segs.clean) %>%
            armlevel_alt(kit.coverage = oncoscan_na33.cov))
    arms.loh <- names(get_loh_segments(segs.clean) %>%
            armlevel_alt(kit.coverage = oncoscan_na33.cov))
    
    # Save arm-level alterations to a CSV file
    arm_alts <- data.frame(
      Arm = unique(c(arms.loss, arms.loh)),
      Loss = unique(c(arms.loss, arms.loh)) %in% arms.loss,
      LOH = unique(c(arms.loss, arms.loh)) %in% arms.loh
    )
    write.csv(arm_alts, "arm_level_alterations.csv", row.names = FALSE)
    
    # 4. Compute individual HRD scores
    # Get the number of LST
    lst <- score_lst(segs.clean, oncoscan_na33.cov)
    
    # Get the number of HR-LOH
    hrloh <- score_loh(segs.clean, arms.loh, arms.loss, oncoscan_na33.cov)
    
    # Get the genomic LOH score
    gloh <- score_gloh(segs.clean, arms.loh, arms.loss, oncoscan_na33.cov)
    
    # Get the number of nLST
    wgd <- score_estwgd(segs.clean, oncoscan_na33.cov)  # Get the avg CN, including 21p
    nlst <- score_nlst(segs.clean, wgd["WGD"], oncoscan_na33.cov)
    
    # 5. Compute TDplus score
    td <- score_td(segs.clean)
    
    # Print results to console
    print(c(LST=lst, `HR-LOH`=hrloh, gLOH=gloh, nLST=nlst))
    print(td\$TDplus)
    
    # Save all computed scores to a CSV file
    scores_df <- data.frame(
      Metric = c("LST", "HR-LOH", "gLOH", "nLST_score", "nLST_status", "TDplus", "WGD"),
      Value = c(
        as.character(lst),
        as.character(hrloh),
        as.character(gloh),
        as.character(nlst["nLST"]),
        as.character(nlst["HRD"]),
        as.character(td\$TDplus),
        as.character(wgd["WGD"])
      )
    )
    write.csv(scores_df, "hrd_and_td_scores.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW":',
        paste0('        oncoscanr: ', as.character(packageVersion("oncoscanr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chas_custom_workflow.csv versions.yml
    """
}

workflow BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chas_file.txt ] ]

    main:
    BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW.out.tables
    plots    = BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW.out.plots
    objects  = BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW.out.objects
    versions = BIOC_ONCOSCANR_CHAS_CUSTOM_WORKFLOW.out.versions
}
