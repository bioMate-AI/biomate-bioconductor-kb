#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HybridMTest — k_group_comparison
// Perform hybrid multi-group comparison using ANOVA and Kruskal-Wallis tests weighted by Shapiro-Wilk normality test EBPs.
// Input: GroupComp.data
// Container: quay.io/biocontainers/bioconductor-hybridmtest:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, HybridMTest
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and the group comparison dataset
//  * 2. [Core Analysis] Extract expression and phenotype data for inspection
//  * 3. [Input & Preparation] Define the test specifications mapping to row-wise test functions
//  * 4. [Input & Preparation] Define the EBP weighting rules using the Shapiro-Wilk EBP
//  * 5. [Core Analysis] Run the hybrid test using hybrid.test and view results

nextflow.enable.dsl = 2

process BIOC_HYBRIDMTEST_K_GROUP_COMPARISON {
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
    .bm_deps <- c("HybridMTest", "Biobase")
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
    
    # 1. Load the package and the group comparison dataset
    library(HybridMTest)
    library(Biobase)
    
    # Read the user-provided GroupComp.data file from the working directory
    input_file <- "GroupComp.data"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    # Attempt to load the ExpressionSet object from the file
    GroupComp.data <- tryCatch({
      readRDS(input_file)
    }, error = function(e) {
      # Fallback to load() if it is an RData/rda file
      env <- new.env()
      load(input_file, envir = env)
      # Find an ExpressionSet object in the loaded environment
      objs <- ls(env)
      eset_idx <- sapply(objs, function(x) is(env[[x]], "ExpressionSet"))
      if (any(eset_idx)) {
        env[[objs[which(eset_idx)[1]]]]
      } else {
        env[[objs[1]]]
      }
    })
    
    if (!is(GroupComp.data, "ExpressionSet")) {
      stop("Error: Loaded object is not an ExpressionSet.")
    }
    
    # 2. Extract expression and phenotype data for inspection
    brain.express.set <- exprs(GroupComp.data)
    brain.pheno.data  <- pData(GroupComp.data)
    
    # Print inspection details to stdout
    cat("Expression data dimensions:\n")
    print(dim(brain.express.set))
    cat("\nFirst 5 rows and 8 columns of expression data:\n")
    print(brain.express.set[1:min(5, nrow(brain.express.set)), 1:min(8, ncol(brain.express.set))])
    cat("\nFirst few rows of phenotype data:\n")
    print(head(brain.pheno.data))
    
    # 3. Define the test specifications mapping to row-wise test functions
    test.specs<-cbind.data.frame(label=c("anova","kw","shapiro"),
                                 func.name=c("row.oneway.anova","row.kruskal.wallis","row.kgrp.shapiro"),
                                 x=rep("grp",3),
                                 opts=rep("",3))
    
    # 4. Define the EBP weighting rules using the Shapiro-Wilk EBP
    ebp.def<-cbind.data.frame(wght=c("shapiro.ebp","(1-shapiro.ebp)"),
                              mthd=c("anova.ebp","kw.ebp"))
    
    # 5. Run the hybrid test using hybrid.test and view results
    Kgrp.res<-hybrid.test(GroupComp.data,test.specs,ebp.def)
    
    cat("\nFirst few rows of hybrid test results:\n")
    print(head(Kgrp.res))
    
    # 6. Write meaningful results to output files
    write.csv(Kgrp.res, file = "Kgrp_results.csv", row.names = TRUE)
    saveRDS(Kgrp.res, file = "Kgrp_results.rds")
    
    # Generate a PDF plot of the results
    pdf("Kgrp_results_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    if ("best.pval" %in% colnames(Kgrp.res)) {
      hist(Kgrp.res\$best.pval, main = "Distribution of Best P-values",
           xlab = "P-value", col = "skyblue", border = "white")
    }
    if ("wgt.mean.ebp" %in% colnames(Kgrp.res)) {
      hist(Kgrp.res\$wgt.mean.ebp, main = "Distribution of Weighted Mean EBP",
           xlab = "Weighted Mean EBP", col = "salmon", border = "white")
    }
    dev.off()
    
    cat("\nPipeline completed successfully. Outputs saved to 'Kgrp_results.csv', 'Kgrp_results.rds', and 'Kgrp_results_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_HYBRIDMTEST_K_GROUP_COMPARISON":',
        paste0('    HybridMTest: ', as.character(packageVersion('HybridMTest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_k_group_comparison.csv versions.yml
    """
}

workflow BIOC_HYBRIDMTEST_K_GROUP_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GroupComp.data ] ]

    main:
    BIOC_HYBRIDMTEST_K_GROUP_COMPARISON(ch_input)

    emit:
    tables   = BIOC_HYBRIDMTEST_K_GROUP_COMPARISON.out.tables
    plots    = BIOC_HYBRIDMTEST_K_GROUP_COMPARISON.out.plots
    objects  = BIOC_HYBRIDMTEST_K_GROUP_COMPARISON.out.objects
    versions = BIOC_HYBRIDMTEST_K_GROUP_COMPARISON.out.versions
}
