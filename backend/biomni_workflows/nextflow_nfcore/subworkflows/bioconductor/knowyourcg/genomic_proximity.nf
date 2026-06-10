#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowYourCG — genomic_proximity
// Test whether a query set of probes shares close genomic proximity (co-localization).
// Input: character vector
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: knowYourCG
// Bioconductor: 3.20 | R: 4.4
// Requires: knowYourCG
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run proximity testing

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_GENOMIC_PROXIMITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("knowYourCG")
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
    library(knowYourCG)
    
    # Define input file path
    input_file <- "probes.txt"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user input (character vector of CpG probe IDs, one per line)
    probes <- readLines(input_file)
    probes <- trimws(probes)
    probes <- probes[probes != ""]
    
    # Run the genomic proximity testing using the exact documented function and arguments
    res <- testProbeProximity(probeIDs = probes)
    
    # Save the complete results object as an RDS file
    saveRDS(res, "proximity_results.rds")
    
    # Save the statistical summary to a CSV file
    if (!is.null(res\$Stats)) {
      write.csv(res\$Stats, "proximity_stats.csv", row.names = FALSE)
    }
    
    # Save the identified co-localized clusters to a CSV file
    if (!is.null(res\$Clusters)) {
      write.csv(res\$Clusters, "proximity_clusters.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_KNOWYOURCG_GENOMIC_PROXIMITY":',
        paste0('    knowYourCG: ', as.character(packageVersion('knowYourCG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_proximity.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ character vector ] ]

    main:
    BIOC_KNOWYOURCG_GENOMIC_PROXIMITY(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY.out.tables
    plots    = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY.out.plots
    objects  = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY.out.objects
    versions = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY.out.versions
}
