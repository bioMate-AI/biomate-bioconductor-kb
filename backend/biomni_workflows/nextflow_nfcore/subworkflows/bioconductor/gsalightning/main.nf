#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSALightning — unpaired_gsa
// Perform permutation-based gene set analysis on unpaired two-sample expression data with optional restandardization.
// Input: expression_matrix.csv, sample_metadata.csv, gene_sets.gmt
// Container: quay.io/biocontainers/bioconductor-gsalightning:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSALightning
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out genes with zero variance
//  * 2. [Core Analysis] Run GSALight with specified statistics, size filters, and missing gene handling
//  * 3. [Core Analysis] Run GSALight with restandardization enabled to obtain corrected p-values and q-values

nextflow.enable.dsl = 2

process BIOC_GSALIGHTNING_UNPAIRED_GSA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("GSALightning")
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
        library(GSALightning)
        
        # Helper function to read GMT files into a list of gene sets
        read_gmt <- function(file) {
          lines <- readLines(file)
          gsets <- list()
          for (line in lines) {
            if (trimws(line) == "") next
            parts <- strsplit(line, "\t")[[1]]
            if (length(parts) >= 3) {
              genes <- parts[3:length(parts)]
              genes <- genes[genes != "" & !is.na(genes)]
              gsets[[parts[1]]] <- genes
            }
          }
          return(gsets)
        }
        
        # 1. Read User Input Files
        expression <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        mode(expression) <- "numeric"
        expression <- na.omit(expression)
        
        sampleInfo <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
        # Ensure the TN column exists; if not, fallback to the second column
        if (!"TN" %in% colnames(sampleInfo)) {
          colnames(sampleInfo)[2] <- "TN"
        }
        
        targetGenes <- read_gmt("gene_sets.gmt")
        
        # 2. Filter out genes with zero variance
        expression <- expression[apply(expression,1,sd) != 0,]
        
        # 3. Run GSALight with specified statistics, size filters, and missing gene handling
        GSALightResults <- GSALight(eset = expression, fac = factor(sampleInfo\$TN), gs = targetGenes, nperm = 1000, minsize = 10, rmGSGenes = 'gene')
        write.csv(GSALightResults, "gsa_results_basic.csv", row.names = TRUE)
        
        GSALightResults <- GSALight(eset = expression, fac = factor(sampleInfo\$TN), gs = targetGenes, nperm = 1000, method = 'maxmean', restandardize = FALSE, minsize = 10, maxsize = 30, rmGSGenes = 'gene', verbose = FALSE)
        write.csv(GSALightResults, "gsa_results_maxmean_norestand.csv", row.names = TRUE)
        
        # Save the non-restandardized results for plotting
        GSALightResultsNoReStand <- GSALightResults
        
        # 4. Run GSALight with restandardization enabled to obtain corrected p-values and q-values
        GSALightResultsReStand <- GSALight(eset = expression, fac = factor(sampleInfo\$TN), gs = targetGenes, nperm = NULL, method = 'maxmean', restandardize = TRUE, minsize = 10, rmGSGenes = 'gene', verbose = FALSE)
        write.csv(GSALightResultsReStand, "gsa_results_restandardized.csv", row.names = TRUE)
        
        # 5. Generate Diagnostic Plots (Histogram of P-values)
        pdf("pvalue_comparison_histogram.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        
        pcol_norestand <- grep("p-value", colnames(GSALightResultsNoReStand), value = TRUE)[1]
        pcol_restand <- grep("p-value", colnames(GSALightResultsReStand), value = TRUE)[1]
        
        if (!is.na(pcol_norestand)) {
          hist(GSALightResultsNoReStand[, pcol_norestand], 
               main = "Without Restandardization", 
               xlab = "p-value", 
               col = "skyblue", 
               border = "white")
        }
        
        if (!is.na(pcol_restand)) {
          hist(GSALightResultsReStand[, pcol_restand], 
               main = "With Restandardization", 
               xlab = "p-value", 
               col = "tomato", 
               border = "white")
        }
        dev.off()
        
        # Save R objects for downstream analysis
        saveRDS(GSALightResultsNoReStand, "GSALightResultsNoReStand.rds")
        saveRDS(GSALightResultsReStand, "GSALightResultsReStand.rds")

    writeLines(c(
        '"BIOC_GSALIGHTNING_UNPAIRED_GSA":',
        paste0('    GSALightning: ', as.character(packageVersion('GSALightning')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unpaired_gsa.csv versions.yml
    """
}

workflow BIOC_GSALIGHTNING_UNPAIRED_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_metadata.csv, gene_sets.gmt ] ]

    main:
    BIOC_GSALIGHTNING_UNPAIRED_GSA(ch_input)

    emit:
    tables   = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.tables
    plots    = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.plots
    objects  = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.objects
    versions = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.versions
}
