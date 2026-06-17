#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tweeDEseq — goodness_of_fit_testing
// Assess whether count data for genes fits a specific distribution (like negative binomial).
// Input: countsNigerianNorm
// Container: quay.io/biocontainers/bioconductor-tweedeseq:1.56.0--r45ha27e39d_0
// R packages: tweeDEseq
// Bioconductor: 3.20 | R: 4.4
// Requires: tweeDEseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform goodness-of-fit testing across genes using gofTest
//  * 2. [Visualization & Output] Visualize the fit using quantile-quantile plots with qqchisq
//  * 3. [Core Analysis] Compare empirical distributions against Poisson, negative binomial, and Poisson-Tweedie using compareCountDist

nextflow.enable.dsl = 2

process BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING {
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
    .bm_deps <- c("tweeDEseq")
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
        library(tweeDEseq)
        
        # Read the user input file 'countsNigerianNorm' from the working directory
        # Supporting RDS, CSV, or extensionless formats
        if (file.exists("countsNigerianNorm.rds")) {
          countsNigerianNorm <- readRDS("countsNigerianNorm.rds")
        } else if (file.exists("countsNigerianNorm.csv")) {
          countsNigerianNorm <- as.matrix(read.csv("countsNigerianNorm.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("countsNigerianNorm")) {
          countsNigerianNorm <- tryCatch({
            readRDS("countsNigerianNorm")
          }, error = function(e) {
            as.matrix(read.csv("countsNigerianNorm", row.names = 1, check.names = FALSE))
          })
        } else {
          stop("Error: 'countsNigerianNorm' file not found in the working directory.")
        }
        
        # Ensure countsNigerianNorm is a matrix
        countsNigerianNorm <- as.matrix(countsNigerianNorm)
        
        # Define a subset of genes to avoid excessive computation times
        candidate_genes <- rownames(countsNigerianNorm)
        if ("ENSG00000070031" %in% candidate_genes) {
          geneSubset <- unique(c("ENSG00000070031", candidate_genes[1:min(40, length(candidate_genes))]))
        } else {
          geneSubset <- candidate_genes[1:min(40, length(candidate_genes))]
        }
        
        # Define xf (counts for a target gene in all samples)
        target_gene <- if ("ENSG00000070031" %in% geneSubset) "ENSG00000070031" else geneSubset[1]
        xf <- unlist(countsNigerianNorm[target_gene, ])
        
        # 1. Perform goodness-of-fit testing across genes using gofTest
        chi2gof <- gofTest(countsNigerianNorm[geneSubset, ], a=0)
        
        # Save goodness-of-fit test statistics
        write.csv(as.data.frame(chi2gof), "chi2gof_results.csv", row.names = TRUE)
        saveRDS(chi2gof, "chi2gof.rds")
        
        # 2. Visualize the fit using quantile-quantile plots with qqchisq
        pdf("gof_plots.pdf", width = 10, height = 5)
        par(mfrow=c(1,2), mar=c(4, 5, 3, 4))
        qq <- qqchisq(chi2gof, main="Chi2 Q-Q Plot")
        qq <- qqchisq(chi2gof, normal=TRUE)
        dev.off()
        
        # 3. Compare empirical distributions against Poisson, negative binomial, and Poisson-Tweedie using compareCountDist
        pdf("compare_count_dist.pdf", width = 6, height = 6)
        compareCountDist(xf, main="All samples")
        dev.off()

    writeLines(c(
        '"BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING":',
        paste0('    tweeDEseq: ', as.character(packageVersion('tweeDEseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_goodness_of_fit_testing.csv versions.yml
    """
}

workflow BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsNigerianNorm ] ]

    main:
    BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING(ch_input)

    emit:
    tables   = BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING.out.tables
    plots    = BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING.out.plots
    objects  = BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING.out.objects
    versions = BIOC_TWEEDESEQ_GOODNESS_OF_FIT_TESTING.out.versions
}
