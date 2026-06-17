#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: synergyfinder — two_drug_with_replicates
// Analyze and visualize drug combinations with replicates using bootstrapping to estimate confidence intervals and p-values.
// Input: drug_screening_replicates.csv
// Container: quay.io/biocontainers/bioconductor-synergyfinder:3.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: synergyfinder
// Visualizations: heatmap
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Reshape and pre-process data with bootstrapping using ReshapeData
//  * 2. [Core Analysis] Calculate synergy scores with bootstrapping using CalculateSynergy
//  * 3. [Core Analysis] Calculate sensitivity scores with bootstrapping using CalculateSensitivity
//  * 4. [Visualization & Output] Visualize response and synergy statistics (SEM, CI) using Plot2DrugHeatmap

nextflow.enable.dsl = 2

process BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("synergyfinder")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(synergyfinder)
    
    # Read the user-provided input file
    # The file must contain columns: block_id, drug1, drug2, conc1, conc2, response, conc_unit, etc.
    input_data <- read.csv("drug_screening_replicates.csv", stringsAsFactors = FALSE)
    
    # 1. Reshape and pre-process data with bootstrapping using ReshapeData
    res <- ReshapeData(
      data = input_data,
      data_type = "inhibition",
      impute = TRUE,
      impute_method = NULL,
      noise = TRUE,
      iteration = 10,
      seed = 1
    )
    
    # 2. Calculate synergy scores with bootstrapping using CalculateSynergy
    res <- CalculateSynergy(
      data = res,
      method = c("ZIP", "HSA", "Bliss", "Loewe"),
      Emin = NA,
      Emax = NA,
      correct_baseline = "non",
      iteration = 10
    )
    
    # 3. Calculate sensitivity scores with bootstrapping using CalculateSensitivity
    res <- CalculateSensitivity(
      data = res,
      correct_baseline = "non",
      iteration = 10
    )
    
    # Save meaningful results to files
    saveRDS(res, file = "synergy_results.rds")
    
    if (!is.null(res\$drug_pairs)) {
      write.csv(res\$drug_pairs, file = "drug_pairs_metrics.csv", row.names = FALSE)
    }
    if (!is.null(res\$synergy_scores)) {
      write.csv(res\$synergy_scores, file = "synergy_scores.csv", row.names = FALSE)
    }
    if (!is.null(res\$synergy_scores_statistics)) {
      write.csv(res\$synergy_scores_statistics, file = "synergy_scores_statistics.csv", row.names = FALSE)
    }
    if (!is.null(res\$sensitivity_scores_statistics)) {
      write.csv(res\$sensitivity_scores_statistics, file = "sensitivity_scores_statistics.csv", row.names = FALSE)
    }
    
    # 4. Visualize response and synergy statistics (SEM, CI) using Plot2DrugHeatmap
    # Plot 1: Standard error of mean (SEM) for response
    p1 <- Plot2DrugHeatmap(
      data = res,
      plot_block = 1,
      drugs = c(1, 2),
      plot_value = "response",
      dynamic = FALSE,
      statistic = "sem",
      summary_statistic = c("mean",  "median")
    )
    
    pdf("heatmap_response_sem.pdf", width = 8, height = 7)
    print(p1)
    dev.off()
    
    # Plot 2: 95% confidence interval (CI) for ZIP synergy
    p2 <- Plot2DrugHeatmap(
      data = res,
      plot_block = 1,
      drugs = c(1, 2),
      plot_value = "ZIP_synergy",
      statistic = "ci",
      dynamic = FALSE,
      summary_statistic = c("quantile_25", "quantile_75")
    )
    
    pdf("heatmap_zip_synergy_ci.pdf", width = 8, height = 7)
    print(p2)
    dev.off()

    writeLines(c(
        '"BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES":',
        paste0('    synergyfinder: ', as.character(packageVersion('synergyfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_drug_with_replicates.csv versions.yml
    """
}

workflow BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ drug_screening_replicates.csv ] ]

    main:
    BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES(ch_input)

    emit:
    tables   = BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES.out.tables
    plots    = BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES.out.plots
    objects  = BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES.out.objects
    versions = BIOC_SYNERGYFINDER_TWO_DRUG_WITH_REPLICATES.out.versions
}
