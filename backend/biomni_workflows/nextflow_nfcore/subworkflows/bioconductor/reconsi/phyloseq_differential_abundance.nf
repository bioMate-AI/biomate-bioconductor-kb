#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: reconsi — phyloseq_differential_abundance
// Perform differential abundance analysis on a phyloseq object incorporating flow cytometry cell counts to account for correlation.
// Input: Vandeputte
// Container: quay.io/biocontainers/bioconductor-reconsi:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, phyloseq, reconsi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run differential abundance analysis using testDAA
//  * 2. [Visualization & Output] Extract and summarize the estimated tail-area false discovery rates

nextflow.enable.dsl = 2

process BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("reconsi", "phyloseq", "ggplot2")
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
    library(reconsi)
    library(phyloseq)
    
    # Read user input
    if (file.exists("Vandeputte")) {
      Vandeputte <- readRDS("Vandeputte")
    } else if (file.exists("Vandeputte.rds")) {
      Vandeputte <- readRDS("Vandeputte.rds")
    } else {
      stop("Error: Input file 'Vandeputte' or 'Vandeputte.rds' not found in the working directory.")
    }
    
    # 1. Run differential abundance analysis using testDAA
    testVanDePutte = testDAA(Vandeputte, groupName = "Health.status", FCname = "absCountFrozen", B = 1e2L)
    
    # 2. Extract and summarize the estimated tail-area false discovery rates
    FdrVDP = testVanDePutte\$Fdr
    q_summary = quantile(FdrVDP)
    
    # Print summary to console
    print(q_summary)
    
    # Write outputs
    # Save the full analysis object
    saveRDS(testVanDePutte, file = "testVanDePutte.rds")
    
    # Save FDR values as a CSV
    fdr_df <- data.frame(Taxon = names(FdrVDP), FDR = FdrVDP, stringsAsFactors = FALSE)
    write.csv(fdr_df, file = "FdrVDP.csv", row.names = FALSE)
    
    # Save quantile summary as a text file
    write.table(as.data.frame(t(q_summary)), file = "fdr_quantile_summary.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # Optional: Generate plots
    tryCatch({
      library(ggplot2)
      
      pdf("null_distribution_plot.pdf")
      print(plotNull(testVanDePutte))
      dev.off()
      
      pdf("approx_covar_plot.pdf")
      print(plotApproxCovar(testVanDePutte))
      dev.off()
    }, error = function(e) {
      warning("Could not generate plots: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE":',
        paste0('    reconsi: ', as.character(packageVersion('reconsi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phyloseq_differential_abundance.csv versions.yml
    """
}

workflow BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Vandeputte ] ]

    main:
    BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE(ch_input)

    emit:
    tables   = BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE.out.tables
    plots    = BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE.out.plots
    objects  = BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE.out.objects
    versions = BIOC_RECONSI_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE.out.versions
}
