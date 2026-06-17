#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DSS — rnaseq_multifactor_de
// Perform differential expression analysis for a multi-factor RNA-seq experiment by estimating dispersions in DSS and testing in edgeR.
// Input: counts.txt, design_df.txt
// Container: quay.io/biocontainers/bioconductor-dss:2.58.0--r45h01b2380_0
// R packages: DSS, edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: DSS, edgeR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create design matrix using model.matrix
//  * 2. [Input & Preparation] Create SeqCountSet object using newSeqCountSet
//  * 3. [Core Analysis] Estimate normalization factors using estNormFactors
//  * 4. [Core Analysis] Estimate and shrink gene-wise dispersions using estDispersion
//  * 5. [Core Analysis] Fit generalized linear model in edgeR using glmFit, plugging in DSS-estimated dispersions
//  * 6. [Core Analysis] Perform hypothesis testing in edgeR using glmLRT

nextflow.enable.dsl = 2

process BIOC_DSS_RNASEQ_MULTIFACTOR_DE {
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
    .bm_deps <- c("DSS", "edgeR")
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
    library(DSS)
    library(edgeR)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    # Read the counts matrix (genes as rows, samples as columns)
    counts_df <- read.table("counts.txt", header=TRUE, row.names=1, check.names=FALSE)
    counts <- as.matrix(counts_df)
    storage.mode(counts) <- "integer"
    
    # Read the experimental design covariates
    design <- read.table("design_df.txt", header=TRUE, stringsAsFactors=TRUE, check.names=FALSE)
    
    # Ensure the design matrix columns match the expected names in the documented formula.
    # We map the first two columns of the design data frame to 'gender' and 'strain'
    # to guarantee compatibility with the documented model formula.
    if (ncol(design) >= 2) {
      colnames(design)[1:2] <- c("gender", "strain")
    } else {
      stop("The design_df.txt file must contain at least two columns for the multi-factor design.")
    }
    
    # Ensure sample alignment between counts and design
    if (ncol(counts) != nrow(design)) {
      # Try to align by matching names if possible, otherwise stop
      if (!is.null(colnames(counts)) && !is.null(rownames(design))) {
        common_samples <- intersect(colnames(counts), rownames(design))
        if (length(common_samples) > 0) {
          counts <- counts[, common_samples, drop=FALSE]
          design <- design[common_samples, , drop=FALSE]
        } else {
          stop("Sample names in counts.txt and design_df.txt do not match.")
        }
      } else {
        stop("Number of columns in counts.txt must match the number of rows in design_df.txt.")
      }
    }
    
    # -----------------------------------------------------------------------------
    # 2. Execute Documented Workflow (Faithful Reproduction)
    # -----------------------------------------------------------------------------
    X = model.matrix(~gender+strain, data=design)
    seqData = newSeqCountSet(counts, as.data.frame(X))
    seqData = estNormFactors(seqData)
    seqData = estDispersion(seqData)
    fit.edgeR = glmFit(counts, X, dispersion=dispersion(seqData))
    lrt.edgeR = glmLRT(glmfit=fit.edgeR, coef=2)
    
    # -----------------------------------------------------------------------------
    # 3. Write Outputs (CSV tables, PDF plots, RDS objects)
    # -----------------------------------------------------------------------------
    # Extract and save differential expression results
    results_df <- as.data.frame(topTags(lrt.edgeR, n=Inf))
    write.csv(results_df, file="de_results_edgeR.csv", row.names=TRUE)
    
    # Save R objects for downstream analysis
    saveRDS(seqData, file="seqData_DSS.rds")
    saveRDS(lrt.edgeR, file="lrt_edgeR.rds")
    
    # Generate diagnostic plots
    pdf("diagnostic_plots.pdf", width=10, height=5)
    par(mfrow=c(1,2))
    
    # Plot 1: DSS Estimated Dispersions vs Mean Counts
    mean_counts <- rowMeans(counts)
    # Filter out zero-mean genes for log-scale plotting
    valid_idx <- mean_counts > 0
    plot(mean_counts[valid_idx], dispersion(seqData)[valid_idx], log="xy",
         xlab="Mean Count (log scale)", ylab="Dispersion (log scale)",
         main="DSS Estimated Dispersions", col="darkblue", pch=20, cex=0.5)
    
    # Plot 2: Distribution of log2 Fold Changes for the tested coefficient
    hist(results_df\$logFC, breaks=50, col="lightgrey", border="darkgrey",
         xlab="log2 Fold Change (tested coefficient)",
         main="Distribution of log2 Fold Changes")
    
    dev.off()

    writeLines(c(
        '"BIOC_DSS_RNASEQ_MULTIFACTOR_DE":',
        paste0('    DSS: ', as.character(packageVersion('DSS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_multifactor_de.csv versions.yml
    """
}

workflow BIOC_DSS_RNASEQ_MULTIFACTOR_DE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.txt, design_df.txt ] ]

    main:
    BIOC_DSS_RNASEQ_MULTIFACTOR_DE(ch_input)

    emit:
    tables   = BIOC_DSS_RNASEQ_MULTIFACTOR_DE.out.tables
    plots    = BIOC_DSS_RNASEQ_MULTIFACTOR_DE.out.plots
    objects  = BIOC_DSS_RNASEQ_MULTIFACTOR_DE.out.objects
    versions = BIOC_DSS_RNASEQ_MULTIFACTOR_DE.out.versions
}
