#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fmcsr — pairwise_mcs_analysis
// Compute, extract, and visualize the exact or mismatch-tolerant maximum common substructure between two compounds.
// Input: sdfset.sdf
// Container: quay.io/biocontainers/bioconductor-fmcsr:1.52.0--r45ha27e39d_0
// R packages: fmcsR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-fmcsr:1.52.0--r45ha27e39d_0"

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
    .bm_deps <- c("fmcsR")
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
    
    library("fmcsR")
    
    # --- Import compound structures from an SDF file ---
    sdfset <- read.SDFset(file="sdfset.sdf")
    mysdf <- sdfset
    
    # --- Compute the MCS/FMCS between two compounds ---
    mcsa <- fmcs(sdfset[[1]], sdfset[[2]])
    mcsa_stats <- stats(mcsa)
    
    # Save stats to CSV
    write.csv(as.data.frame(t(mcsa_stats)), file="mcsa_stats.csv", row.names=FALSE)
    
    # Extract MCS components
    mcsa1 <- mcs1(mcsa)
    mcsa2 <- mcs2(mcsa)
    
    # Save MCS components to RDS
    saveRDS(mcsa1, file="mcsa1.rds")
    saveRDS(mcsa2, file="mcsa2.rds")
    
    # --- Extract the MCS substructure as an SDFset ---
    mcstosdfset <- mcs2sdfset(mcsa, type="new")
    write.SDF(mcstosdfset, file="mcstosdfset.sdf")
    
    # Plot the extracted substructure
    pdf("mcstosdfset_plot.pdf")
    plot(mcstosdfset[[1]], print=FALSE)
    dev.off()
    
    # --- Visualize the MCS highlighted in the compound structures ---
    test <- fmcs(sdfset[1], sdfset[2], au=2, bu=1)
    
    pdf("plotMCS_test.pdf")
    plotMCS(test, regenCoords=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS":',
        paste0('        fmcsr: ', as.character(packageVersion("fmcsr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_mcs_analysis.csv versions.yml
    """
}

workflow BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sdfset.sdf ] ]

    main:
    BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS.out.tables
    plots    = BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS.out.plots
    objects  = BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS.out.objects
    versions = BIOC_FMCSR_PAIRWISE_MCS_ANALYSIS.out.versions
}
