#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rsvsim — comparing_sv_sets
// Compare simulated ground-truth SVs with query SVs detected by an algorithm to evaluate performance.
// Input: simulated_svs.csv, detected_svs.bed
// Container: quay.io/biocontainers/bioconductor-rsvsim:1.50.0--r45hdfd78af_0
// R packages: RSVSim
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSVSIM_COMPARING_SV_SETS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rsvsim:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("RSVSim")
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
    library(RSVSim)
    
    # --- Load the simulated ground-truth SVs (simSVs) ---
    # The user input simulated_svs.csv contains the ground-truth SVs
    simSVs <- read.csv("simulated_svs.csv", stringsAsFactors = FALSE)
    
    # --- Load and format the query SVs (querySVs) from the BED file ---
    # Standard BED files are tab-separated and do not have a header.
    # We map the first three columns to 'chr', 'start', and 'end'.
    # If a fourth column exists (e.g., containing the breakpoint sequence), we map it to 'bpSeq'.
    querySVs_raw <- read.table("detected_svs.bed", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
    
    querySVs <- data.frame(
      chr = as.character(querySVs_raw[[1]]),
      start = as.numeric(querySVs_raw[[2]]),
      end = as.numeric(querySVs_raw[[3]]),
      stringsAsFactors = FALSE
    )
    
    if (ncol(querySVs_raw) >= 4) {
      querySVs\$bpSeq <- as.character(querySVs_raw[[4]])
    }
    
    # --- Run compareSV with specified tolerances as documented ---
    comparison_tol0 <- compareSV(querySVs, simSVs, tol=0)
    comparison_tol3 <- compareSV(querySVs, simSVs, tol=3)
    
    # --- Write the meaningful results to output files ---
    write.csv(comparison_tol0, "comparison_results_tol0.csv", row.names = FALSE)
    write.csv(comparison_tol3, "comparison_results_tol3.csv", row.names = FALSE)
    
    # Save the comparison objects as RDS for downstream R analysis
    saveRDS(comparison_tol0, "comparison_results_tol0.rds")
    saveRDS(comparison_tol3, "comparison_results_tol3.rds")

    writeLines(c(
        '"BIOC_RSVSIM_COMPARING_SV_SETS":',
        paste0('        rsvsim: ', as.character(packageVersion("rsvsim")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comparing_sv_sets.csv versions.yml
    """
}

workflow BIOC_RSVSIM_COMPARING_SV_SETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simulated_svs.csv, detected_svs.bed ] ]

    main:
    BIOC_RSVSIM_COMPARING_SV_SETS(ch_input)

    emit:
    tables   = BIOC_RSVSIM_COMPARING_SV_SETS.out.tables
    plots    = BIOC_RSVSIM_COMPARING_SV_SETS.out.plots
    objects  = BIOC_RSVSIM_COMPARING_SV_SETS.out.objects
    versions = BIOC_RSVSIM_COMPARING_SV_SETS.out.versions
}
