#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSAR — rnaseq_gsa
// Perform self-contained gene set analysis on RNA-seq count data, handling normalization and filtering of zero-variance genes.
// Input: PickrellDataSet, genes.length, group.label.pickrell, XYgenes
// Container: quay.io/biocontainers/bioconductor-gsar:1.44.0--r45hdfd78af_0
// R packages: GSAR, edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: GSAR, edgeR
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out low-expressed genes using count-per-million (CPM) thresholds. 2. Normalize counts using RPKM and log2-transform the dat

nextflow.enable.dsl = 2

process BIOC_GSAR_RNASEQ_GSA {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GSAR", "edgeR")
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
        library(edgeR)
        library(GSAR)
        
        # Helper function to load matrix inputs robustly
        load_matrix <- function(name) {
          for (ext in c(".rds", "", ".csv", ".tsv", ".txt")) {
            file <- paste0(name, ext)
            if (file.exists(file)) {
              if (grepl("\\\\.rds\$", file, ignore.case = TRUE)) {
                return(as.matrix(readRDS(file)))
              } else {
                tryCatch({
                  return(as.matrix(read.csv(file, row.names = 1, check.names = FALSE)))
                }, error = function(e) {
                  return(as.matrix(read.csv(file, header = TRUE, check.names = FALSE)))
                })
              }
            }
          }
          stop(paste("Matrix file not found:", name))
        }
        
        # Helper function to load vector inputs robustly
        load_vector <- function(name, mode = "numeric") {
          for (ext in c(".rds", "", ".csv", ".tsv", ".txt")) {
            file <- paste0(name, ext)
            if (file.exists(file)) {
              if (grepl("\\\\.rds\$", file, ignore.case = TRUE)) {
                val <- readRDS(file)
                if (mode == "numeric") return(as.numeric(val))
                return(as.character(val))
              } else {
                tryCatch({
                  df <- read.csv(file, header = FALSE, stringsAsFactors = FALSE)
                  val <- df[[1]]
                  if (mode == "numeric") {
                    if (is.na(as.numeric(val[1]))) {
                      df <- read.csv(file, header = TRUE, stringsAsFactors = FALSE)
                      val <- df[[1]]
                    }
                    return(as.numeric(val))
                  } else {
                    return(as.character(val))
                  }
                }, error = function(e) {
                  lines <- readLines(file)
                  if (mode == "numeric") return(as.numeric(lines))
                  return(as.character(lines))
                })
              }
            }
          }
          stop(paste("Vector file not found:", name))
        }
        
        # 1. Read user input files from the working directory
        PickrellDataSet      <- load_matrix("PickrellDataSet")
        genes.length         <- load_vector("genes.length", "numeric")
        group.label.pickrell <- load_vector("group.label.pickrell", "numeric")
        XYgenes              <- load_vector("XYgenes", "character")
        
        # Reconstruct the 'gender' variable to ensure the documented code runs seamlessly
        # group.label.pickrell is expected to be 1 for female and 2 for male
        gender <- ifelse(group.label.pickrell == 2, "male", "female")
        
        # 2. Execute the documented workflow steps
        cpm.matrix <- cpm(PickrellDataSet)
        cpm.means <- rowMeans(cpm.matrix)
        cpm.filter <- which(cpm.means > 0.1)
        PickrellDataSet <- PickrellDataSet[cpm.filter,]
        genes.length <- genes.length[cpm.filter]
        rpkm.set <- rpkm(PickrellDataSet, genes.length)
        rpkm.set <- log2(1 + rpkm.set)
        
        # Filter target pathway genes to only those present in the normalized dataset
        XYgenes <- XYgenes[XYgenes %in% rownames(rpkm.set)]
        XYpathway <- rpkm.set[XYgenes,]
        
        group.label.pickrell <- (gender == "male") + 1
        
        # Run statistical tests on the initial pathway matrix
        WW_pvalue <- WWtest(XYpathway, group.label.pickrell)
        KS_pvalue <- KStest(XYpathway, group.label.pickrell)
        
        # Filter out genes with zero or tiny standard deviation (< 1e-3) in either group
        tiny.sd.XY.female <- which(apply(XYpathway[, group.label.pickrell == 1], 1, "sd") < 1e-3)
        tiny.sd.XY.male <- which(apply(XYpathway[, group.label.pickrell == 2], 1, "sd") < 1e-3)
        tiny.sd.XY.remove <- unique(c(tiny.sd.XY.male, tiny.sd.XY.female))
        if(length(tiny.sd.XY.remove) > 0) XYpathway <- XYpathway[-tiny.sd.XY.remove,]
        
        # Run statistical tests on the filtered pathway matrix
        WW_pvalue_filtered <- WWtest(XYpathway, group.label.pickrell)
        KS_pvalue_filtered <- KStest(XYpathway, group.label.pickrell)
        
        # 3. Write named output files for the results
        # Save the p-values to a CSV table
        results_df <- data.frame(
          Analysis_Stage = c("Pre-filtering", "Pre-filtering", "Post-filtering", "Post-filtering"),
          Test = c("Wald-Wolfowitz (WWtest)", "Kolmogorov-Smirnov (KStest)", "Wald-Wolfowitz (WWtest)", "Kolmogorov-Smirnov (KStest)"),
          P_Value = c(WW_pvalue, KS_pvalue, WW_pvalue_filtered, KS_pvalue_filtered)
        )
        write.csv(results_df, "gsa_results.csv", row.names = FALSE)
        
        # Save the normalized, filtered pathway expression matrix
        write.csv(as.data.frame(XYpathway), "XYpathway_normalized_filtered_expression.csv")
        saveRDS(XYpathway, "XYpathway_normalized_filtered_expression.rds")
        
        # Generate and save the Minimum Spanning Tree (MST2) plots to a PDF
        tryCatch({
          pdf("XYpathway_MST2_plots.pdf", width = 12, height = 7)
          plotMST2.pathway(
            object = XYpathway,
            group = group.label.pickrell,
            name = "XYpathway",
            legend.size = 1.2,
            cor.method = "pearson"
          )
          dev.off()
        }, error = function(e) {
          warning("Could not generate MST2 plot: ", e\$message)
        })
        
        cat("Pipeline completed successfully. Outputs written to 'gsa_results.csv', 'XYpathway_normalized_filtered_expression.csv', and 'XYpathway_MST2_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_GSAR_RNASEQ_GSA":',
        paste0('    GSAR: ', as.character(packageVersion('GSAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_gsa.csv versions.yml
    """
}

workflow BIOC_GSAR_RNASEQ_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PickrellDataSet, genes.length, group.label.pickrell, XYgenes ] ]

    main:
    BIOC_GSAR_RNASEQ_GSA(ch_input)

    emit:
    tables   = BIOC_GSAR_RNASEQ_GSA.out.tables
    plots    = BIOC_GSAR_RNASEQ_GSA.out.plots
    objects  = BIOC_GSAR_RNASEQ_GSA.out.objects
    versions = BIOC_GSAR_RNASEQ_GSA.out.versions
}
