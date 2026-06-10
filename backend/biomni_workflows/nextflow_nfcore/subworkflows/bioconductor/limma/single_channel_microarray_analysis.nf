#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: limma — single_channel_microarray_analysis
// Analyze single-channel microarray data (e.g., Affymetrix) to identify differentially expressed genes.
// Input: targets.txt, .CEL
// Container: quay.io/biocontainers/bioconductor-limma:3.66.0--r45h01b2380_0
// R packages: affy, gcrma, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, gcrma, limma
// Visualizations: volcano plot, mean-difference plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read targets metadata using readTargets(). 2. Read and pre-process raw data using ReadAffy() and gcrma() from the gcrma package. 3

nextflow.enable.dsl = 2

process BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS {
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
    .bm_deps <- c("affy", "gcrma", "limma")
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
    library(affy)
    library(gcrma)
    library(limma)
    
    # 1. Read targets metadata using readTargets()
    targets <- readTargets("targets.txt")
    
    # 2. Read and pre-process raw data using ReadAffy() and gcrma()
    ab <- ReadAffy(filenames=targets\$FileName)
    eset <- gcrma(ab)
    
    # 3. Construct a design matrix representing the experimental groups
    # Dynamically identify the condition column (first column that is not 'FileName')
    cond_col <- setdiff(colnames(targets), "FileName")[1]
    condition <- factor(targets[[cond_col]])
    design <- model.matrix(~ condition)
    
    # 4. Fit gene-wise linear models using lmFit()
    fit <- lmFit(eset, design)
    
    # 5. Apply empirical Bayes smoothing with robust and trend options using eBayes()
    fit <- eBayes(fit, trend=TRUE, robust=TRUE)
    
    # 6. Extract top differentially expressed genes using topTable()
    top_genes <- topTable(fit, coef=2, number=Inf)
    
    # Write named output files for the meaningful results
    write.csv(top_genes, "differential_expression_results.csv", row.names=TRUE)
    saveRDS(fit, "limma_fit_object.rds")
    
    # Generate diagnostic and results plots
    tryCatch({
      pdf("analysis_plots.pdf", width=10, height=5)
      par(mfrow=c(1, 2))
      
      coef_name <- colnames(design)[2]
      
      # Volcano plot
      volcanoplot(fit, coef=2, main=paste("Volcano Plot:", coef_name))
      
      # Mean-Difference (MD) plot
      plotMD(fit, column=2, main=paste("MD Plot:", coef_name))
      
      dev.off()
    }, error = function(e) {
      warning("Plot generation failed, but data outputs were successfully written.")
    })

    writeLines(c(
        '"BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS":',
        paste0('    limma: ', as.character(packageVersion('limma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_channel_microarray_analysis.csv versions.yml
    """
}

workflow BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets.txt, .CEL ] ]

    main:
    BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS.out.tables
    plots    = BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS.out.plots
    objects  = BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS.out.objects
    versions = BIOC_LIMMA_SINGLE_CHANNEL_MICROARRAY_ANALYSIS.out.versions
}
