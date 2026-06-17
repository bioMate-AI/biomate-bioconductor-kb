#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneSelectMMD — expression_set_workflow
// Select differentially expressed genes, estimate error rates, and plot model fit from an ExpressionSet object.
// Input: eSet1
// Container: quay.io/biocontainers/bioconductor-geneselectmmd:2.54.0--r45h63f16b7_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GeneSelectMMD
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare sample membership vector
//  * 2. [Core Analysis] Run gene selection using gsMMD
//  * 3. [Core Analysis] Estimate error rates using errRates
//  * 4. [Visualization & Output] Plot density fit using plotHistDensity

nextflow.enable.dsl = 2

process BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW {
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
    .bm_deps <- c("GeneSelectMMD", "Biobase")
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
    library(GeneSelectMMD)
    library(Biobase)
    
    # Read user input
    if (file.exists("eSet1")) {
      eSet1 <- readRDS("eSet1")
    } else if (file.exists("eSet1.rds")) {
      eSet1 <- readRDS("eSet1.rds")
    } else {
      stop("Input file 'eSet1' or 'eSet1.rds' not found in the working directory.")
    }
    
    # 1. Prepare sample membership vector
    pheno <- pData(eSet1)
    if (ncol(pheno) == 0) {
      stop("No phenotype data found in ExpressionSet.")
    }
    
    mem.str <- as.character(pheno[[1]])
    unique_groups <- unique(mem.str)
    if (length(unique_groups) != 2) {
      stop("The first phenotype column must contain exactly two unique groups.")
    }
    
    nSubjects <- length(mem.str)
    memSubjects <- rep(0, nSubjects)
    # First group coded as 0, second group coded as 1
    memSubjects[mem.str == unique_groups[2]] <- 1
    
    # 2. Run gene selection using gsMMD
    obj.gsMMD <- gsMMD(eSet1, memSubjects, transformFlag = TRUE, 
      transformMethod = "boxcox", scaleFlag = TRUE, quiet = TRUE)
    para <- obj.gsMMD\$para
    print(round(para, 3))
    
    # Save parameters to CSV
    para_df <- data.frame(Parameter = names(para), Value = para)
    write.csv(para_df, "estimated_parameters.csv", row.names = FALSE)
    
    # Save the full results object
    saveRDS(obj.gsMMD, "gsMMD_results.rds")
    
    # 3. Estimate error rates using errRates
    errs <- errRates(obj.gsMMD)
    print(round(errs, 3))
    
    # Save error rates to CSV
    errs_df <- data.frame(Metric = names(errs), Value = errs)
    write.csv(errs_df, "estimated_error_rates.csv", row.names = FALSE)
    
    # 4. Plot density fit using plotHistDensity
    pdf("density_fit_plot.pdf", width = 7, height = 7)
    plot_title <- paste0("Histogram of gene expression levels for ", unique_groups[2], "\nimposed with estimated density (case)")
    plotHistDensity(obj.gsMMD, plotFlag = "case", 
        mytitle = plot_title, 
        plotComponent = TRUE, 
        x.legend = "topright", 
        y.legend = NULL,
        numPoints = 500,
        cex.main = 1,
        cex = 1)
    dev.off()

    writeLines(c(
        '"BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW":',
        paste0('    GeneSelectMMD: ', as.character(packageVersion('GeneSelectMMD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expression_set_workflow.csv versions.yml
    """
}

workflow BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eSet1 ] ]

    main:
    BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW.out.tables
    plots    = BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW.out.plots
    objects  = BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW.out.objects
    versions = BIOC_GENESELECTMMD_EXPRESSION_SET_WORKFLOW.out.versions
}
