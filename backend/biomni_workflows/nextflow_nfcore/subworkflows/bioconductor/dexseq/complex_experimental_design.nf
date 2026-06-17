#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEXSeq — complex_experimental_design
// Perform differential exon usage analysis controlling for additional covariates or blocking factors (e.g., library type).
// Input: dxd
// Container: quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0
// R packages: DEXSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: DEXSeq
// Visualizations: MA plot, dispersion plot
// QC: dispersion/size-factor estimation, dispersion QC plot, diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define full and reduced model formulas
//  * 2. [Core Analysis] Estimate dispersions using the full model formula in estimateDispersions
//  * 3. [Core Analysis] Test for differential exon usage using both formulas in testForDEU
//  * 4. [Core Analysis] Extract results using DEXSeqResults

nextflow.enable.dsl = 2

process BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN {
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
    .bm_deps <- c("DEXSeq")
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
        library(DEXSeq)
        
        # Read the user input file 'dxd' from the working directory
        if (file.exists("dxd")) {
          dxd <- readRDS("dxd")
        } else if (file.exists("dxd.rds")) {
          dxd <- readRDS("dxd.rds")
        } else {
          stop("Error: Input file 'dxd' or 'dxd.rds' not found in the working directory.")
        }
        
        # Estimate size factors (required before estimating dispersions)
        dxd = estimateSizeFactors(dxd)
        
        # Identify the blocking factor (covariate) dynamically
        covariate = setdiff(colnames(sampleAnnotation(dxd)), c("sample", "condition", "sizeFactor"))[1]
        
        # 1. Define full and reduced model formulas dynamically
        formulaFullModel    = as.formula(paste0("~ sample + exon + ", covariate, ":exon + condition:exon"))
        formulaReducedModel = as.formula(paste0("~ sample + exon + ", covariate, ":exon"))
        
        # 2. Estimate dispersions using the full model formula
        dxd = estimateDispersions( dxd, formula = formulaFullModel )
        
        # 3. Test for differential exon usage
        dxd = testForDEU( dxd, 
        	reducedModel = formulaReducedModel, 
                fullModel = formulaFullModel )
        
        # 4. Extract results
        dxr2 = DEXSeqResults( dxd )
        
        # Write outputs
        # Save the updated DEXSeqDataSet and DEXSeqResults objects as RDS files first
        # to ensure primary outputs are not lost if subsequent steps fail
        saveRDS(dxd, file = "dxd_complex_analyzed.rds")
        saveRDS(dxr2, file = "dxr2_complex_results.rds")
        
        # Save the results table as a CSV file
        # Convert DEXSeqResults to a data frame and flatten list/matrix columns for CSV compatibility
        dxr_df <- as.data.frame(dxr2)
        for (col in colnames(dxr_df)) {
          if (is.list(dxr_df[[col]]) || inherits(dxr_df[[col]], "List")) {
            dxr_df[[col]] <- vapply(dxr_df[[col]], paste, collapse = ";", FUN.VALUE = character(1))
          } else if (is.matrix(dxr_df[[col]])) {
            dxr_df[[col]] <- apply(dxr_df[[col]], 1, paste, collapse = ";")
          } else if (inherits(dxr_df[[col]], "GRanges")) {
            dxr_df[[col]] <- as.character(dxr_df[[col]])
          }
        }
        write.csv(dxr_df, file = "dexseq_complex_results.csv", row.names = TRUE)
        
        # Generate diagnostic plots
        pdf("dexseq_complex_plots.pdf", width = 7, height = 7)
        tryCatch({
          plotDispEsts(dxd)
        }, error = function(e) {
          warning("Could not generate dispersion plot: ", e\$message)
        })
        
        tryCatch({
          plotMA(dxr2)
        }, error = function(e) {
          warning("Could not generate MA plot: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN":',
        paste0('    DEXSeq: ', as.character(packageVersion('DEXSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complex_experimental_design.csv versions.yml
    """
}

workflow BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dxd ] ]

    main:
    BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN(ch_input)

    emit:
    tables   = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.tables
    plots    = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.plots
    objects  = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.objects
    versions = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.versions
}
