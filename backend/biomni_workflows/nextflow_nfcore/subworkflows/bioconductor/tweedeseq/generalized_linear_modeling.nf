#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tweeDEseq — generalized_linear_modeling
// Fit generalized linear models using the Poisson-Tweedie distribution to test for differential expression with covariates or offsets.
// Input: countsNigerianNorm, genderNigerian, cqn.subset$offset
// Container: quay.io/biocontainers/bioconductor-tweedeseq:1.56.0--r45ha27e39d_0
// R packages: tweeDEseq
// Bioconductor: 3.20 | R: 4.4
// Requires: tweeDEseq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit a GLM for a single gene using glmPT
//  * 2. [Visualization & Output] Summarize and test the model using summary and anova
//  * 3. [Core Analysis] Fit GLMs for multiple genes simultaneously using tweeDEglm
//  * 4. [Core Analysis] (Optional) Incorporate CQN offsets into the GLM using the offset argument in tweeDEglm

nextflow.enable.dsl = 2

process BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING {
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
        
    # Load required libraries
    library(tweeDEseq)
    
    # Read user input files from the working directory
    countsNigerianNorm <- readRDS("countsNigerianNorm.rds")
    genderNigerian <- readRDS("genderNigerian.rds")
    
    # Handle optional CQN offsets
    cqn.subset <- list()
    if (file.exists("cqn.subset.rds")) {
      cqn.subset <- readRDS("cqn.subset.rds")
    } else if (file.exists("cqn.subset_offset.rds")) {
      cqn.subset\$offset <- readRDS("cqn.subset_offset.rds")
    }
    
    # Define geneSubset based on the input counts matrix
    geneSubset <- rownames(countsNigerianNorm)
    
    # Ensure cqn.subset\$offset is initialized if missing, matching the dimensions of the subset
    if (is.null(cqn.subset\$offset)) {
      cqn.subset\$offset <- matrix(0, nrow = length(geneSubset), ncol = ncol(countsNigerianNorm))
      rownames(cqn.subset\$offset) <- geneSubset
      colnames(cqn.subset\$offset) <- colnames(countsNigerianNorm)
    }
    
    # 1. Fit a GLM for a single gene using glmPT
    single_gene <- geneSubset[1]
    mod <- glmPT(countsNigerianNorm[single_gene,] ~ genderNigerian)
    
    # 2. Summarize and test the model using summary and anova
    mod_summary <- summary(mod)
    mod_anova <- anova(mod)
    
    # Save single-gene model outputs
    sink("glm_summary.txt")
    print(mod_summary)
    sink()
    
    sink("glm_anova.txt")
    print(mod_anova)
    sink()
    
    # 3. Fit GLMs for multiple genes simultaneously using tweeDEglm
    resPTglm <- tweeDEglm( ~ genderNigerian, counts = countsNigerianNorm[geneSubset,])
    
    # Display the top significant genes
    top_genes <- head(resPTglm[sort(resPTglm\$pval.adjust, index.return = TRUE)\$ix,])
    
    # Save multi-gene GLM results
    write.csv(resPTglm, file = "resPTglm_results.csv", row.names = TRUE)
    saveRDS(resPTglm, file = "resPTglm_results.rds")
    
    # 4. Incorporate CQN offsets into the GLM using the offset argument in tweeDEglm
    resPTglm_offset <- tweeDEglm(~ genderNigerian, counts = countsNigerianNorm[geneSubset,], offset = cqn.subset\$offset)
    
    # Save offset GLM results
    write.csv(resPTglm_offset, file = "resPTglm_offset_results.csv", row.names = TRUE)
    saveRDS(resPTglm_offset, file = "resPTglm_offset_results.rds")

    writeLines(c(
        '"BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING":',
        paste0('    tweeDEseq: ', as.character(packageVersion('tweeDEseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generalized_linear_modeling.csv versions.yml
    """
}

workflow BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsNigerianNorm, genderNigerian, cqn.subset$offset ] ]

    main:
    BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING(ch_input)

    emit:
    tables   = BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING.out.tables
    plots    = BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING.out.plots
    objects  = BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING.out.objects
    versions = BIOC_TWEEDESEQ_GENERALIZED_LINEAR_MODELING.out.versions
}
