#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metapone — metapone_pathway_analysis
// Conduct metabolic pathway testing from untargeted metabolomics feature-level test results using permutation or GSEA-type testing.
// Input: pos_features.csv, neg_features.csv
// Container: quay.io/biocontainers/bioconductor-metapone:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metapone
// Visualizations: pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the metapone package and input feature-level test results
//  * 2. [Input & Preparation] Load the built-in HMDB compound m/z mapping and pathway databases
//  * 3. [Input & Preparation] Define the allowed adduct lists for positive and negative modes
//  * 4. [Core Analysis] Run the pathway testing using the metapone function
//  * 5. [Core Analysis] Extract and filter significant pathways using ptable and ftable
//  * 6. [Visualization & Output] Visualize the pathway testing results using bbplot1d and bbplot2d

nextflow.enable.dsl = 2

process BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("metapone")
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
    
    # 1. Load the metapone package and input feature-level test results
    library(metapone)
    
    # Read user input files
    if (!file.exists("pos_features.csv") || !file.exists("neg_features.csv")) {
      stop("Required input files 'pos_features.csv' and/or 'neg_features.csv' are missing in the working directory.")
    }
    
    pos <- read.csv("pos_features.csv", check.names = FALSE)
    neg <- read.csv("neg_features.csv", check.names = FALSE)
    
    # Standardize column names to ensure compatibility with metapone expectations
    standardize_cols <- function(df) {
      colnames(df) <- gsub("p.value", "p-value", colnames(df), fixed = TRUE)
      colnames(df) <- gsub("p_value", "p-value", colnames(df), fixed = TRUE)
      colnames(df) <- gsub("pvalue", "p-value", colnames(df), fixed = TRUE)
      colnames(df) <- gsub("retention_time", "time", colnames(df), fixed = TRUE)
      colnames(df) <- gsub("retention.time", "time", colnames(df), fixed = TRUE)
      colnames(df) <- gsub("rt", "time", colnames(df), fixed = TRUE)
      colnames(df) <- gsub("m.z", "mz", colnames(df), fixed = TRUE)
      colnames(df) <- gsub("m_z", "mz", colnames(df), fixed = TRUE)
      return(df)
    }
    
    pos <- standardize_cols(pos)
    neg <- standardize_cols(neg)
    
    # 2. Load the built-in HMDB compound m/z mapping and pathway databases
    # Accessing lazy-loaded datasets directly to avoid forbidden data() call
    hmdbCompMZ <- metapone::hmdbCompMZ
    pa <- metapone::pa
    
    # 3. Define the allowed adduct lists for positive and negative modes
    pos.adductlist = c("M+H", "M+NH4", "M+Na", "M+ACN+H", "M+ACN+Na", "M+2ACN+H", "2M+H", "2M+Na", "2M+ACN+H")
    neg.adductlist = c("M-H", "M-2H", "M-2H+Na", "M-2H+K", "M-2H+NH4", "M-H2O-H", "M-H+Cl", "M+Cl", "M+2Cl")
    
    # 4. Run the pathway testing using the metapone function
    dat <- list(pos, neg)
    type <- list("pos", "neg")
    
    r <- metapone(
      dat, 
      type, 
      pa, 
      hmdbCompMZ = hmdbCompMZ, 
      pos.adductlist = pos.adductlist, 
      neg.adductlist = neg.adductlist, 
      p.threshold = 0.05, 
      n.permu = 200, 
      fractional.count.power = 0.5, 
      max.match.count = 10, 
      use.fgsea = FALSE
    )
    
    # Save the full metapone result object
    saveRDS(r, "metapone_result.rds")
    
    # 5. Extract and filter significant pathways using ptable and ftable
    # Open PDF device to capture all plots
    pdf("pathway_analysis_plots.pdf", width = 8, height = 6)
    
    # Plot p-value distribution histogram
    hist(ptable(r)[,1], main = "P-value Distribution of Pathways", xlab = "P-value")
    
    # Filter and save significant pathways
    selection <- which(ptable(r)[,1] < 0.025)
    sig_pathways <- ptable(r)[selection, , drop = FALSE]
    write.csv(sig_pathways, "significant_pathways.csv", row.names = TRUE)
    
    # Filter and save significant features
    sig_features <- ftable(r)[which(ptable(r)[,1] < 0.025 & ptable(r)[,2] >= 2)]
    saveRDS(sig_features, "significant_features.rds")
    
    # 6. Visualize the pathway testing results using bbplot1d and bbplot2d
    bbplot1d(r@test.result, 0.025)
    bbplot2d(r@test.result, 0.025)
    
    # Close PDF device
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: 'metapone_result.rds', 'significant_pathways.csv', 'significant_features.rds', and 'pathway_analysis_plots.pdf'.")

    writeLines(c(
        '"BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS":',
        paste0('    metapone: ', as.character(packageVersion('metapone')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metapone_pathway_analysis.csv versions.yml
    """
}

workflow BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pos_features.csv, neg_features.csv ] ]

    main:
    BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS.out.tables
    plots    = BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS.out.plots
    objects  = BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS.out.objects
    versions = BIOC_METAPONE_METAPONE_PATHWAY_ANALYSIS.out.versions
}
