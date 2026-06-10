#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cormotif — correlation_motif_analysis
// Fit correlation motif models to multiple gene expression studies to identify shared and study-specific differential expression patterns, handle missing data, an
// Input: exprs.simu2, simu2_groupid, simu2_compgroup
// Container: quay.io/biocontainers/bioconductor-cormotif:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Cormotif
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare expression matrix, group IDs, and comparison group matrix. 2. Fit correlation motif models for a range of motif numbers (K

nextflow.enable.dsl = 2

process BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS {
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
    
    # Load required library
    library(Cormotif)
    
    # Helper function to robustly read input files with various extensions and formats
    read_file <- function(base_name) {
      extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        path <- paste0(base_name, ext)
        if (file.exists(path)) {
          # Try reading as RDS
          out <- tryCatch(readRDS(path), error = function(e) NULL)
          if (!is.null(out)) return(out)
          
          # Try reading as table/matrix with row names
          out <- tryCatch({
            df <- read.table(path, header = TRUE, sep = "", row.names = 1, check.names = FALSE)
            as.matrix(df)
          }, error = function(e) NULL)
          if (!is.null(out)) return(out)
          
          # Try reading as CSV with row names
          out <- tryCatch({
            df <- read.csv(path, header = TRUE, row.names = 1, check.names = FALSE)
            as.matrix(df)
          }, error = function(e) NULL)
          if (!is.null(out)) return(out)
          
          # Try reading as table without row names
          out <- tryCatch({
            df <- read.table(path, header = TRUE, sep = "", check.names = FALSE)
            if (ncol(df) == 1) as.vector(df[[1]]) else as.matrix(df)
          }, error = function(e) NULL)
          if (!is.null(out)) return(out)
          
          # Try reading as scan vector
          out <- tryCatch(scan(path, quiet = TRUE), error = function(e) NULL)
          if (!is.null(out)) return(out)
        }
      }
      stop(paste("File not found or could not be read:", base_name))
    }
    
    # 1. Prepare expression matrix, group IDs, and comparison group matrix
    exprs.simu2 <- read_file("exprs.simu2")
    exprs.simu2 <- as.matrix(exprs.simu2)
    
    simu2_groupid <- read_file("simu2_groupid")
    if (is.matrix(simu2_groupid) || is.data.frame(simu2_groupid)) {
      if (nrow(simu2_groupid) == 1) {
        simu2_groupid <- as.vector(simu2_groupid[1, ])
      } else if (ncol(simu2_groupid) == 1) {
        simu2_groupid <- as.vector(simu2_groupid[, 1])
      } else {
        simu2_groupid <- as.vector(as.matrix(simu2_groupid))
      }
    } else {
      simu2_groupid <- as.vector(simu2_groupid)
    }
    
    simu2_compgroup <- read_file("simu2_compgroup")
    simu2_compgroup <- as.matrix(simu2_compgroup)
    
    # 2. Fit correlation motif models for a range of motif numbers (K) using cormotiffit
    motif.fitted <- cormotiffit(exprs.simu2, simu2_groupid, simu2_compgroup,
                                K=1:5, max.iter=1000, BIC=TRUE)
    
    # 3. Evaluate model fit using BIC/AIC values and plot information criteria using plotIC
    motif.fitted\$bic
    write.csv(motif.fitted\$bic, "motif_fitted_bic.csv", row.names = FALSE)
    
    pdf("plot_ic.pdf")
    plotIC(motif.fitted)
    dev.off()
    
    # 4. Visualize the discovered correlation motifs and their frequencies using plotMotif
    pdf("plot_motif.pdf")
    plotMotif(motif.fitted)
    dev.off()
    
    # 5. Extract posterior probabilities of differential expression and identify active patterns
    head(motif.fitted\$bestmotif\$p.post)
    write.csv(motif.fitted\$bestmotif\$p.post, "posterior_probabilities.csv", row.names = TRUE)
    
    dif.pattern.simu2 <- (motif.fitted\$bestmotif\$p.post > 0.5)
    head(dif.pattern.simu2)
    write.csv(dif.pattern.simu2, "differential_patterns.csv", row.names = TRUE)
    
    # 6. Rank genes in each study based on posterior probabilities using generank
    topgenelist <- generank(motif.fitted\$bestmotif\$p.post)
    head(topgenelist)
    write.csv(topgenelist, "top_gene_list.csv", row.names = FALSE)
    
    # Save the main fitted model object
    saveRDS(motif.fitted, "motif_fitted.rds")
    
    # 7. Fit alternative models (all, separate, or full motifs) using cormotiffitall, cormotiffitsep, or cormotiffitfull
    motif.fitted.all <- cormotiffitall(exprs.simu2, simu2_groupid, simu2_compgroup, max.iter=1)
    saveRDS(motif.fitted.all, "motif_fitted_all.rds")
    
    motif.fitted.sep <- cormotiffitsep(exprs.simu2, simu2_groupid, simu2_compgroup, max.iter=1)
    saveRDS(motif.fitted.sep, "motif_fitted_sep.rds")
    
    motif.fitted.full <- cormotiffitfull(exprs.simu2, simu2_groupid, simu2_compgroup, max.iter=1)
    saveRDS(motif.fitted.full, "motif_fitted_full.rds")

    writeLines(c(
        '"BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS":',
        paste0('    Cormotif: ', as.character(packageVersion('Cormotif')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_motif_analysis.csv versions.yml
    """
}

workflow BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs.simu2, simu2_groupid, simu2_compgroup ] ]

    main:
    BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS.out.tables
    plots    = BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS.out.plots
    objects  = BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS.out.objects
    versions = BIOC_CORMOTIF_CORRELATION_MOTIF_ANALYSIS.out.versions
}
