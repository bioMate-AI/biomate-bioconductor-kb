#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LBE — lbe_fdr_estimation
// Estimate the proportion of true null hypotheses, FDR, and q-values from a vector of p-values, visualize the results, and export them.
// Input: golub.pval
// Container: quay.io/biocontainers/bioconductor-lbe:1.78.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: LBE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and p-value data
//  * 2. [Core Analysis] Run the main LBE estimation with desired parameters (e.g., FDR level, confidence interval level, or specific number of significant
//  * 3. [Visualization & Output] Plot the results using multiple plot types
//  * 4. [Visualization & Output] Summarize the estimation results
//  * 5. [Visualization & Output] Write the results to a file

nextflow.enable.dsl = 2

process BIOC_LBE_LBE_FDR_ESTIMATION {
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
    .bm_deps <- c("LBE")
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
        
    # Load the required package
    library(LBE)
    
    # 1. Load the p-value data from the user input file "golub.pval"
    if (!file.exists("golub.pval")) {
      stop("Error: Required input file 'golub.pval' not found in the working directory.")
    }
    
    # Robustly read the p-values as a numeric vector
    golub.pval <- tryCatch({
      val <- scan("golub.pval", quiet = TRUE)
      if (length(val) == 0 || any(is.na(val))) stop("Empty or non-numeric file")
      val
    }, error = function(e) {
      # Fallback: read table and extract the first numeric column
      df <- read.table("golub.pval", header = FALSE, stringsAsFactors = FALSE)
      num_cols <- sapply(df, is.numeric)
      if (any(num_cols)) {
        df[[which(num_cols)[1]]]
      } else {
        as.numeric(df[[1]])
      }
    })
    
    # Remove any NA values to ensure clean estimation
    golub.pval <- golub.pval[!is.na(golub.pval)]
    
    # 2. Run the main LBE estimation with desired parameters
    pdf("LBE_res.pdf")
    LBE.res <- LBE(golub.pval)
    dev.off()
    
    print(names(LBE.res))
    print(LBE.res\$pi0); print(LBE.res\$pi0.ci); print(LBE.res\$ci.level)
    
    LBE.res2 <- LBE(golub.pval, ci.level=0.8, plot.type="none")
    print(LBE.res2\$pi0.ci); print(LBE.res2\$ci.level)
    
    LBE.res3 <- LBE(golub.pval, FDR.level=0.1, plot.type="none")
    print(LBE.res3\$qvalues[1:10])
    print(LBE.res3\$n.significant)
    
    pdf("LBE_res4.pdf")
    LBE.res4 <- LBE(golub.pval, FDR.level=NA, n.significant=300)
    dev.off()
    
    print(LBE.res4\$qvalues[1:10])
    
    # 3. Plot the results using multiple plot types (saving to PDF)
    pdf("LBE_plots.pdf", width = 8, height = 8)
    LBEplot(LBE.res, plot.type="multiple")
    dev.off()
    
    # 4. Summarize the estimation results (printing to console and saving to text file)
    sink("LBE_summary.txt")
    LBEsummary(LBE.res)
    sink()
    
    # Also print summary to standard output
    LBEsummary(LBE.res)
    
    # 5. Write the results to a file (LBEwrite writes to "LBEresults.txt" by default)
    LBEwrite(LBE.res)
    
    # Save the main LBE result object as an RDS file for downstream R analyses
    saveRDS(LBE.res, "LBE_res.rds")

    writeLines(c(
        '"BIOC_LBE_LBE_FDR_ESTIMATION":',
        paste0('    LBE: ', as.character(packageVersion('LBE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lbe_fdr_estimation.csv versions.yml
    """
}

workflow BIOC_LBE_LBE_FDR_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ golub.pval ] ]

    main:
    BIOC_LBE_LBE_FDR_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_LBE_LBE_FDR_ESTIMATION.out.tables
    plots    = BIOC_LBE_LBE_FDR_ESTIMATION.out.plots
    objects  = BIOC_LBE_LBE_FDR_ESTIMATION.out.objects
    versions = BIOC_LBE_LBE_FDR_ESTIMATION.out.versions
}
