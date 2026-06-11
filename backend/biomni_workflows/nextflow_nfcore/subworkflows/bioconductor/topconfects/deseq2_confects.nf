#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: topconfects — deseq2_confects
// Rank genes by confident fold change from a DESeq2 analysis.
// Input: arab, Time, Treat, arab_info
// Container: quay.io/biocontainers/bioconductor-topconfects:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, ggplot2, topconfects
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create DESeqDataSet and run DESeq
//  * 2. [Core Analysis] Calculate confident effect sizes using deseq2_confects
//  * 3. [Visualization & Output] Visualize results using confects_plot

nextflow.enable.dsl = 2

process BIOC_TOPCONFECTS_DESEQ2_CONFECTS {
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
            library(DESeq2)
            library(topconfects)
            library(ggplot2)
            
            # Helper function to robustly read user input files (supporting RDS or CSV)
            read_input <- function(name, is_matrix = FALSE, is_factor = FALSE) {
              if (file.exists(paste0(name, ".rds"))) {
                val <- readRDS(paste0(name, ".rds"))
                if (is_matrix) val <- as.matrix(val)
                if (is_factor) {
                  if (is.data.frame(val)) {
                    val <- setNames(as.factor(val[[1]]), rownames(val))
                  } else {
                    val <- as.factor(val)
                  }
                }
                return(val)
              } else if (file.exists(paste0(name, ".csv"))) {
                val <- read.csv(paste0(name, ".csv"), row.names = 1, check.names = FALSE)
                if (is_matrix) val <- as.matrix(val)
                if (is_factor) {
                  if (is.data.frame(val)) {
                    val <- setNames(as.factor(val[[1]]), rownames(val))
                  } else {
                    val <- as.factor(val)
                  }
                }
                return(val)
              } else if (file.exists(name)) {
                val <- tryCatch({
                  readRDS(name)
                }, error = function(e) {
                  read.csv(name, row.names = 1, check.names = FALSE)
                })
                if (is_matrix) val <- as.matrix(val)
                if (is_factor) {
                  if (is.data.frame(val)) {
                    val <- setNames(as.factor(val[[1]]), rownames(val))
                  } else {
                    val <- as.factor(val)
                  }
                }
                return(val)
              } else {
                stop(paste("Required input file not found:", name))
              }
            }
            
            # Read user inputs from the working directory
            arab <- read_input("arab", is_matrix = TRUE)
            Time <- read_input("Time", is_factor = TRUE)
            Treat <- read_input("Treat", is_factor = TRUE)
            arab_info <- read_input("arab_info")
            
            # Ensure Treat factor has "mock" as the reference level if present
            if ("mock" %in% levels(Treat)) {
              Treat <- relevel(Treat, ref = "mock")
            }
            
            # 1. Create DESeqDataSet and run DESeq
            dds <- DESeqDataSetFromMatrix(
                countData = arab,
                colData = data.frame(Time, Treat),
                rowData = arab_info,
                design = ~Time+Treat)
            
            dds <- DESeq(dds)
            
            # 2. Calculate confident effect sizes using deseq2_confects
            coef_name <- grep("^Treat_", resultsNames(dds), value = TRUE)[1]
            dconfects <- deseq2_confects(dds, name=coef_name, step=0.05)
            
            # Save tabular results
            write.csv(dconfects\$table, "deseq2_confects_results.csv", row.names = FALSE)
            saveRDS(dconfects, "deseq2_confects.rds")
            
            # 3. Visualize results using confects_plot
            pdf("deseq2_confects_plot.pdf", width = 7, height = 6)
            print(confects_plot(dconfects))
            dev.off()

    writeLines(c(
        '"BIOC_TOPCONFECTS_DESEQ2_CONFECTS":',
        paste0('    topconfects: ', as.character(packageVersion('topconfects')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deseq2_confects.csv versions.yml
    """
}

workflow BIOC_TOPCONFECTS_DESEQ2_CONFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arab, Time, Treat, arab_info ] ]

    main:
    BIOC_TOPCONFECTS_DESEQ2_CONFECTS(ch_input)

    emit:
    tables   = BIOC_TOPCONFECTS_DESEQ2_CONFECTS.out.tables
    plots    = BIOC_TOPCONFECTS_DESEQ2_CONFECTS.out.plots
    objects  = BIOC_TOPCONFECTS_DESEQ2_CONFECTS.out.objects
    versions = BIOC_TOPCONFECTS_DESEQ2_CONFECTS.out.versions
}
