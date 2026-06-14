#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaseqr2 — p_value_combination
// Combine externally calculated p-values from multiple differential expression algorithms using Simes, Harmonic Mean, or PANDORA weighting methods.
// Input: hg19pvalues
// Container: quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0
// R packages: metaseqR2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_METASEQR2_P_VALUE_COMBINATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0"

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
    .bm_deps <- c("metaseqR2")
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
    
    # Load required library
    library(metaseqR2)
    
    # --- Load external p-value data ---
    # The pipeline reads EXACTLY the 'hg19pvalues' file from the working directory.
    if (file.exists("hg19pvalues")) {
        hg19pvalues <- tryCatch({
            read.table("hg19pvalues", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        }, error = function(e) {
            read.csv("hg19pvalues", row.names = 1, check.names = FALSE)
        })
    } else if (file.exists("hg19pvalues.csv")) {
        hg19pvalues <- read.csv("hg19pvalues.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("hg19pvalues.tsv")) {
        hg19pvalues <- read.table("hg19pvalues.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    } else {
        stop("Required input file 'hg19pvalues' (or hg19pvalues.csv/tsv) not found in the working directory.")
    }
    
    # Ensure the data is in matrix format for apply operations
    hg19pvalues <- as.matrix(hg19pvalues)
    
    # --- Combine p-values using Simes method with combineSimes ---
    pSimes <- apply(hg19pvalues, 1, combineSimes)
    
    # --- Retrieve PANDORA weights using getWeights ---
    w <- getWeights("human")
    
    # --- Combine p-values using Harmonic Mean method with ---
    pHarm <- apply(hg19pvalues, 1, combineHarmonic, w)
    
    # --- Combine p-values using PANDORA weighted method with ---
    pPandora <- apply(hg19pvalues, 1, combineWeight, w)
    
    # Construct a combined data frame of results
    results <- data.frame(
        hg19pvalues,
        p_Simes = pSimes,
        p_Harmonic = pHarm,
        p_Pandora = pPandora,
        check.names = FALSE
    )
    
    # Write named output files for the meaningful results
    write.csv(results, "combined_pvalues.csv", row.names = TRUE)
    saveRDS(results, "combined_pvalues.rds")
    
    # Generate a PDF plot of the combined p-value distributions
    pdf("combined_pvalues_distribution.pdf", width = 10, height = 4)
    par(mfrow = c(1, 3))
    hist(pSimes, main = "Simes p-values", xlab = "p-value", col = "skyblue", breaks = 20)
    hist(pHarm, main = "Harmonic Mean p-values", xlab = "p-value", col = "lightgreen", breaks = 20)
    hist(pPandora, main = "PANDORA p-values", xlab = "p-value", col = "salmon", breaks = 20)
    dev.off()

    writeLines(c(
        '"BIOC_METASEQR2_P_VALUE_COMBINATION":',
        paste0('        metaseqr2: ', as.character(packageVersion("metaseqr2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_p_value_combination.csv versions.yml
    """
}

workflow BIOC_METASEQR2_P_VALUE_COMBINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg19pvalues ] ]

    main:
    BIOC_METASEQR2_P_VALUE_COMBINATION(ch_input)

    emit:
    tables   = BIOC_METASEQR2_P_VALUE_COMBINATION.out.tables
    plots    = BIOC_METASEQR2_P_VALUE_COMBINATION.out.plots
    objects  = BIOC_METASEQR2_P_VALUE_COMBINATION.out.objects
    versions = BIOC_METASEQR2_P_VALUE_COMBINATION.out.versions
}
