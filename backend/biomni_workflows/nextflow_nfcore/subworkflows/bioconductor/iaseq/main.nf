#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iASeq — allele_specific_motif_analysis
// Fit correlation motif models to multiple allele-specific sequencing studies to identify, select, and visualize joint allele-specific event patterns.
// Input: sampleASE_exprs, sampleASE_studyid, sampleASE_repid, sampleASE_refid
// Container: quay.io/biocontainers/bioconductor-iaseq:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iASeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and the dataset
//  * 2. [Core Analysis] Inspect the study, replicate, and reference allele structures
//  * 3. [Core Analysis] Fit the iASeq motif model across a range of motif numbers (K) using iASeqmotif
//  * 4. [Visualization & Output] Evaluate model fit using BIC values and plot the BIC curve using plotBIC
//  * 5. [Visualization & Output] Visualize the learned motif patterns and SNP frequencies using plotMotif
//  * 6. [Core Analysis] Extract posterior probabilities for allele-specific events from the best model

nextflow.enable.dsl = 2

process BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS {
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
    .bm_deps <- c("iASeq")
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
    library(iASeq)
    
    # Helper function to robustly load user input files from the working directory
    as_vector_or_factor <- function(x) {
      if (is.data.frame(x)) {
        if (ncol(x) == 1) {
          return(x[[1]])
        } else if (nrow(x) == 1) {
          return(as.vector(unlist(x)))
        }
      }
      return(as.vector(x))
    }
    
    load_input <- function(name) {
      # Try exact name first (e.g. if saved without extension)
      if (file.exists(name)) {
        res <- tryCatch(readRDS(name), error = function(e) NULL)
        if (!is.null(res)) return(res)
        res <- tryCatch(read.csv(name, header=TRUE, check.names=FALSE), error = function(e) NULL)
        if (!is.null(res)) {
          if (name == "sampleASE_exprs") {
            if (!is.numeric(res[[1]])) {
              rownames(res) <- res[[1]]
              res <- res[, -1, drop=FALSE]
            }
            return(as.matrix(res))
          }
          return(as_vector_or_factor(res))
        }
      }
      
      # Try with common extensions
      for (ext in c(".rds", ".csv", ".tsv", ".txt")) {
        path <- paste0(name, ext)
        if (file.exists(path)) {
          if (ext == ".rds") {
            return(readRDS(path))
          }
          sep <- if (ext == ".csv") "," else ""
          df <- read.table(path, header=TRUE, sep=sep, check.names=FALSE, stringsAsFactors=FALSE)
          if (name == "sampleASE_exprs") {
            if (!is.numeric(df[[1]])) {
              rownames(df) <- df[[1]]
              df <- df[, -1, drop=FALSE]
            }
            return(as.matrix(df))
          } else {
            if (ncol(df) > 1 && !is.numeric(df[[1]])) {
              return(df[[2]])
            }
            return(df[[1]])
          }
        }
      }
      stop(paste("Required input file not found in working directory:", name))
    }
    
    # 1. Load the dataset from user input files
    sampleASE_exprs <- load_input("sampleASE_exprs")
    sampleASE_studyid <- load_input("sampleASE_studyid")
    sampleASE_repid <- load_input("sampleASE_repid")
    sampleASE_refid <- load_input("sampleASE_refid")
    
    # 2. Inspect the study, replicate, and reference allele structures
    print("--- Column Names of Expression Matrix ---")
    print(colnames(sampleASE_exprs))
    
    print("--- Study IDs ---")
    print(sampleASE_studyid)
    
    print("--- Replicate IDs ---")
    print(sampleASE_repid)
    
    print("--- Reference Allele Indicators ---")
    print(sampleASE_refid)
    
    # 3. Fit the iASeq motif model across a range of motif numbers (K) using iASeqmotif
    motif.fitted<-iASeqmotif(sampleASE_exprs,sampleASE_studyid,sampleASE_repid,
    	sampleASE_refid,K=1:5,iter.max=5,tol=1e-3)
    
    # 4. Evaluate model fit using BIC values and plot the BIC curve using plotBIC
    print("--- BIC Values ---")
    print(motif.fitted\$bic)
    
    # Save BIC values to a CSV file
    write.csv(as.data.frame(motif.fitted\$bic), "motif_fitted_bic.csv", row.names=FALSE)
    
    # Plot BIC curve and save to PDF
    pdf("plot_bic.pdf")
    plotBIC(motif.fitted)
    dev.off()
    
    # 5. Visualize the learned motif patterns and SNP frequencies using plotMotif
    pdf("plot_motif.pdf")
    plotMotif(motif.fitted\$bestmotif,cutoff=0.9)
    dev.off()
    
    # 6. Extract posterior probabilities for allele-specific events from the best model
    print("--- Head of Posterior Probabilities ---")
    print(head(motif.fitted\$bestmotif\$p.post))
    
    # Save posterior probabilities to a CSV file
    p_post_df <- data.frame(
      SNP = if (!is.null(rownames(sampleASE_exprs))) rownames(sampleASE_exprs) else seq_along(motif.fitted\$bestmotif\$p.post),
      Posterior_Probability = motif.fitted\$bestmotif\$p.post
    )
    write.csv(p_post_df, "posterior_probabilities.csv", row.names=FALSE)
    
    # Save the complete fitted model object
    saveRDS(motif.fitted, "motif_fitted.rds")
    
    print("--- Pipeline completed successfully. Outputs saved to working directory. ---")

    writeLines(c(
        '"BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS":',
        paste0('    iASeq: ', as.character(packageVersion('iASeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allele_specific_motif_analysis.csv versions.yml
    """
}

workflow BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleASE_exprs, sampleASE_studyid, sampleASE_repid, sampleASE_refid ] ]

    main:
    BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS.out.tables
    plots    = BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS.out.plots
    objects  = BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS.out.objects
    versions = BIOC_IASEQ_ALLELE_SPECIFIC_MOTIF_ANALYSIS.out.versions
}
