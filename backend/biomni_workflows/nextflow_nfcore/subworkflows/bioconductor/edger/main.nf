#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edgeR — quasi_likelihood_pipeline
// Perform differential expression analysis using the robust quasi-likelihood F-test framework.
// Input: TableOfCounts.txt
// Container: quay.io/biocontainers/bioconductor-edger:4.8.2--r45h01b2380_0
// R packages: edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR
// Visualizations: mean-difference plot
// QC: filter low-expression genes
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read count data and define groups
//  * 2. [Input & Preparation] Create DGEList object
//  * 3. [Core Analysis] Filter lowly expressed genes
//  * 4. [Core Analysis] Normalize library sizes
//  * 5. [Input & Preparation] Define design matrix
//  * 6. [Core Analysis] Fit QL GLM model
//  * 7. [Core Analysis] Perform quasi-likelihood F-test
//  * 8. [Core Analysis] Extract top differentially expressed genes

nextflow.enable.dsl = 2

process BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE {
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
    .bm_deps <- c("edgeR")
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
    
    # Load required library
    library(edgeR)
    
    # 1. Read count data and define groups
    x <- read.delim("TableOfCounts.txt", row.names="Symbol")
    group <- factor(c(1, 1, 2, 2))
    
    # 2. Create DGEList object
    y <- DGEList(counts=x, group=group)
    
    # 3. Filter lowly expressed genes
    keep <- filterByExpr(y)
    y <- y[keep, , keep.lib.sizes=FALSE]
    
    # 4. Normalize library sizes
    y <- normLibSizes(y)
    
    # 5. Define design matrix
    design <- model.matrix(~group)
    
    # 6. Fit QL GLM model
    fit <- glmQLFit(y, design)
    
    # 7. Perform quasi-likelihood F-test
    qlf <- glmQLFTest(fit, coef=2)
    
    # 8. Extract top differentially expressed genes
    top_tags_all <- topTags(qlf, n=Inf)
    
    # Print the default top tags to console as in the documented code
    print(topTags(qlf))
    
    # Write outputs to files
    # Save the complete table of differential expression results
    write.csv(as.data.frame(top_tags_all), file="differential_expression_results.csv", row.names=TRUE)
    
    # Save the QL F-test object as an RDS file for downstream analysis
    saveRDS(qlf, file="qlf_results.rds")
    
    # Generate and save a Mean-Difference (MD) plot
    pdf("md_plot.pdf", width=7, height=7)
    plotMD(qlf)
    dev.off()

    writeLines(c(
        '"BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE":',
        paste0('    edgeR: ', as.character(packageVersion('edgeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quasi_likelihood_pipeline.csv versions.yml
    """
}

workflow BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TableOfCounts.txt ] ]

    main:
    BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.tables
    plots    = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.plots
    objects  = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.objects
    versions = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.versions
}
