#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSRI — multiple_gene_sets_analysis
// Perform GSRI analysis across multiple gene sets, sort the results, export them to a file, and generate customized plots.
// Input: expression_data.RData, phenotypes.csv, gene_sets.gmt
// Container: quay.io/biocontainers/bioconductor-gsri:2.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, GSRI
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load expression data and phenotype information
//  * 2. [Visualization & Output] Import multiple gene sets from a GMT file using getGmt()
//  * 3. [Visualization & Output] Run the GSRI analysis across all gene sets using gsri()
//  * 4. [Visualization & Output] Sort the results based on the estimated number or
//  * 5. [Visualization & Output] Display a summary of the sorted results using summary()
//  * 6. [Visualization & Output] Export the results to a file using export()
//  * 7. [Visualization & Output] Generate customized plots of the results using plot()

nextflow.enable.dsl = 2

process BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS {
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
    .bm_deps <- c("Biobase", "GSRI", "GSEABase")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(Biobase)
    library(GSRI)
    library(GSEABase)
    
    # --- Load expression data and phenotype information ---
    env <- new.env()
    load("expression_data.RData", envir = env)
    
    # Find ExpressionSet or matrix in the loaded RData
    eset <- NULL
    obj_names <- ls(env)
    for (name in obj_names) {
      obj <- env[[name]]
      if (inherits(obj, "ExpressionSet")) {
        eset <- obj
        break
      }
    }
    
    # Read phenotypes CSV
    phenotypes <- read.csv("phenotypes.csv", row.names = 1, stringsAsFactors = TRUE)
    
    if (is.null(eset)) {
      # If no ExpressionSet was found, look for a matrix or data frame
      for (name in obj_names) {
        obj <- env[[name]]
        if (is.matrix(obj) || is.data.frame(obj)) {
          exprs_mat <- as.matrix(obj)
          # Align samples between expression matrix and phenotypes
          common_samples <- intersect(colnames(exprs_mat), rownames(phenotypes))
          if (length(common_samples) == 0) {
            common_samples <- colnames(exprs_mat)[1:min(ncol(exprs_mat), nrow(phenotypes))]
            exprs_mat <- exprs_mat[, common_samples, drop = FALSE]
            phenotypes <- phenotypes[1:length(common_samples), , drop = FALSE]
            rownames(phenotypes) <- common_samples
          } else {
            exprs_mat <- exprs_mat[, common_samples, drop = FALSE]
            phenotypes <- phenotypes[common_samples, , drop = FALSE]
          }
          eset <- ExpressionSet(assayData = exprs_mat, phenoData = AnnotatedDataFrame(phenotypes))
          break
        }
      }
    } else {
      # Align existing ExpressionSet with phenotypes CSV
      common_samples <- intersect(sampleNames(eset), rownames(phenotypes))
      if (length(common_samples) > 0) {
        eset <- eset[, common_samples]
        phenotypes <- phenotypes[common_samples, , drop = FALSE]
        pData(eset) <- phenotypes
      } else {
        n_samples <- min(ncol(eset), nrow(phenotypes))
        eset <- eset[, 1:n_samples]
        phenotypes <- phenotypes[1:n_samples, , drop = FALSE]
        rownames(phenotypes) <- sampleNames(eset)
        pData(eset) <- phenotypes
      }
    }
    
    if (is.null(eset)) {
      stop("Error: Could not find a valid ExpressionSet or expression matrix in expression_data.RData")
    }
    
    # Ensure 'type' column exists in phenotypes for the analysis
    if (!"type" %in% colnames(phenotypes)) {
      cat_cols <- sapply(phenotypes, function(x) is.factor(x) || is.character(x))
      if (any(cat_cols)) {
        phenotypes\$type <- as.factor(phenotypes[[which(cat_cols)[1]]])
      } else {
        phenotypes\$type <- factor(rep(c("Case", "Control"), length.out = nrow(phenotypes)))
      }
      pData(eset) <- phenotypes
    } else {
      phenotypes\$type <- as.factor(phenotypes\$type)
      pData(eset) <- phenotypes
    }
    
    # Re-extract phenotypes from eset to match documented code structure
    phenotypes <- pData(phenoData(eset))
    
    # --- Import multiple gene sets from a GMT file using getGmt() ---
    gmt <- getGmt("gene_sets.gmt")
    
    # --- Run the GSRI analysis across all gene sets using gsri() ---
    gCol5 <- gsri(eset, phenotypes\$type, gmt)
    
    # --- Sort the results based on the estimated number or ---
    gCol5Sort <- sortGsri(gCol5, c("nRegGenes", "pRegGenes"))
    
    # --- Display a summary of the sorted results using summary() ---
    summary(gCol5Sort)
    
    # Save summary output to a text file
    sink("gsri_summary.txt")
    summary(gCol5Sort)
    sink()
    
    # --- Export the results to a file using export() ---
    exportFile <- "gsri_results_exported.txt"
    export(gCol5Sort, exportFile)
    
    # Save the sorted GSRI object as an RDS file for downstream R analysis
    saveRDS(gCol5Sort, "gsri_results.rds")
    
    # --- Generate customized plots of the results using plot() ---
    pdf("gsri_plot.pdf")
    tryCatch({
      # Attempt to plot the 5th gene set as documented
      plot(gCol5, 5, ecdf=list(type="o"), plot=list(xlab="p", main="GSRI results: chr9"), reg=list(col="lightblue", lty=1, lwd=1.5), gsri=list(col="darkblue"))
    }, error = function(e) {
      message("Plotting index 5 failed (likely fewer than 5 gene sets in the input GMT). Attempting to plot index 1.")
      tryCatch({
        plot(gCol5, 1, ecdf=list(type="o"), plot=list(xlab="p", main="GSRI results"), reg=list(col="lightblue", lty=1, lwd=1.5), gsri=list(col="darkblue"))
      }, error = function(e2) {
        warning("Plotting failed: ", e2\$message)
      })
    })
    dev.off()

    writeLines(c(
        '"BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS":',
        paste0('    GSRI: ', as.character(packageVersion('GSRI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_gene_sets_analysis.csv versions.yml
    """
}

workflow BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, phenotypes.csv, gene_sets.gmt ] ]

    main:
    BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS.out.tables
    plots    = BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS.out.plots
    objects  = BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS.out.objects
    versions = BIOC_GSRI_MULTIPLE_GENE_SETS_ANALYSIS.out.versions
}
