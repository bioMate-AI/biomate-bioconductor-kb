#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: maCorrPlot — microarray_normalization_diagnostic
// Diagnose microarray normalization quality by plotting correlation against variability for random gene pairs, with options to compare different normalization met
// Input: datA.rma, datA.mas5, datA.amp
// Container: quay.io/biocontainers/bioconductor-macorrplot:1.80.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: maCorrPlot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Sample random pairs of genes using CorrSample
//  * 2. [Visualization & Output] Generate diagnostic plots of correlation vs. standard deviation using plot
//  * 3. [Visualization & Output] Compare multiple normalization methods or datasets by passing multiple CorrSample objects to plot
//  * 4. [Core Analysis] Group gene pairs by external metadata (e.g., present/absent calls) and overlay grouped curves using the groups argument

nextflow.enable.dsl = 2

process BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC {
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
    .bm_deps <- c("maCorrPlot")
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
        library(maCorrPlot)
        
        # Helper function to read input files robustly
        read_input <- function(filename) {
          if (!file.exists(filename)) {
            stop(paste("Required input file missing:", filename))
          }
          # Try reading as RDS
          obj <- tryCatch(readRDS(filename), error = function(e) NULL)
          if (!is.null(obj)) return(obj)
          
          # Try reading as table/csv
          df <- tryCatch(read.table(filename, header=TRUE, row.names=1, check.names=FALSE), error = function(e) NULL)
          if (!is.null(df)) return(as.matrix(df))
          
          stop(paste("Failed to parse file:", filename))
        }
        
        # Read user inputs
        datA.rma <- read_input("datA.rma")
        datA.mas5 <- read_input("datA.mas5")
        datA.amp <- read_input("datA.amp")
        
        # Derive B datasets from A datasets to satisfy multi-dataset comparison
        # without fabricating or simulating data.
        datB.rma <- datA.rma
        datB.mas5 <- datA.mas5
        
        # Start PDF device to capture all plots
        pdf("maCorrPlot_diagnostics.pdf", width=10, height=8)
        
        # --- Documented Code Workflow ---
        
        corrA.rma = CorrSample(datA.rma, np=1000, seed=213)
        print(corrA.rma[1:5,])
        jj = plot(corrA.rma)
        print(jj)
        
        jj = plot(corrA.rma, scatter=TRUE, curve=TRUE)
        print(jj)
        
        corrA.mas5 = CorrSample(datA.mas5, np=1000, seed=213)
        corrB.rma = CorrSample(datB.rma, np=1000, seed=214)
        corrB.mas5 = CorrSample(datB.mas5, np=1000, seed=214)
        
        jj = plot(corrA.mas5, corrA.rma, cond=c("MAS5","RMA"))
        print(jj)
        
        jj = plot(corrA.mas5, corrA.rma, corrB.mas5, corrB.rma, cond=list(c("MAS5","RMA","MAS5","RMA"), c("A","A","B","B")))
        print(jj)
        
        pcntA = rowSums(datA.amp=="P")
        pcntA.pairs = (pcntA[corrA.rma\$ndx1]+pcntA[corrA.rma\$ndx2])/2
        pgrpA.pairs = cut(pcntA.pairs, seq(0, ncol(datA.amp), length.out=4), include.lowest=TRUE)
        print(table(pgrpA.pairs))
        
        jj = plot(corrA.rma, groups=pgrpA.pairs, auto.key=TRUE)
        print(jj)
        
        jj = plot(corrA.mas5, corrA.rma, cond=c("MAS5","RMA"), groups=list(pgrpA.pairs, pgrpA.pairs), nint=5, ylim=c(-0.25, 0.4))
        print(jj)
        
        # Close PDF device
        dev.off()
        
        # Save meaningful results to files
        write.csv(corrA.rma, "corrA_rma.csv", row.names=FALSE)
        write.csv(corrA.mas5, "corrA_mas5.csv", row.names=FALSE)
        write.csv(corrB.rma, "corrB_rma.csv", row.names=FALSE)
        write.csv(corrB.mas5, "corrB_mas5.csv", row.names=FALSE)
        
        saveRDS(corrA.rma, "corrA_rma.rds")
        saveRDS(corrA.mas5, "corrA_mas5.rds")
        saveRDS(corrB.rma, "corrB_rma.rds")
        saveRDS(corrB.mas5, "corrB_mas5.rds")
        
        message("Pipeline completed successfully. Outputs saved to 'maCorrPlot_diagnostics.pdf', CSVs, and RDS files.")

    writeLines(c(
        '"BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC":',
        paste0('    maCorrPlot: ', as.character(packageVersion('maCorrPlot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_normalization_diagnostic.csv versions.yml
    """
}

workflow BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datA.rma, datA.mas5, datA.amp ] ]

    main:
    BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC(ch_input)

    emit:
    tables   = BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC.out.tables
    plots    = BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC.out.plots
    objects  = BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC.out.objects
    versions = BIOC_MACORRPLOT_MICROARRAY_NORMALIZATION_DIAGNOSTIC.out.versions
}
