#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASSET — meta_analysis_heterogeneous_traits
// Perform subset-based meta-analysis of summary-level association statistics across multiple studies or traits.
// Input: vdata.rda
// Container: quay.io/biocontainers/bioconductor-asset:2.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ASSET
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load summary data and calculate betas, standard errors (sigmas), case counts, and control counts from individual studies
//  * 2. [Core Analysis] Run subset-based meta-analysis using h.traits
//  * 3. [Input & Preparation] Define a custom subset search function and run h.traits with restricted subset search
//  * 4. [Visualization & Output] Summarize results using h.summary

nextflow.enable.dsl = 2

process BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ASSET")
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
    
    # Load required library
    library(ASSET)
    
    # 1. Load summary data and calculate betas, standard errors (sigmas), case counts, and control counts from individual studies
    # Read the user input file from the working directory
    load("vdata.rda")
    
    SNPs    <- paste("SNP", 1:3, sep="")
    nSNP    <- length(SNPs)
    studies <- paste("STUDY", 1:4, sep="") 
    nStudy  <- length(studies)
    
    case    <- matrix(data=NA, nrow=nSNP, ncol=nStudy) 
    control <- matrix(data=NA, nrow=nSNP, ncol=nStudy) 
    
    for (i in 1:nStudy) {
      data <- eval(parse(text=paste("data", i, sep="")))
      caseVec <- data[, "CC"] == 1
      controlVec <- !caseVec
      for (j in 1:nSNP) {
        temp <- !is.na(data[, SNPs[j]])
        case[j, i] <- sum(caseVec & temp, na.rm=TRUE)
        control[j, i] <- sum(controlVec & temp, na.rm=TRUE)
      }
    }
    
    beta  <- matrix(data=NA, nrow=nSNP, ncol=nStudy) 
    sigma <- matrix(data=NA, nrow=nSNP, ncol=nStudy) 
    
    for (i in 1:nStudy) {
      data <- eval(parse(text=paste("data", i, sep="")))
      for (j in 1:nSNP) {
        data[, "SNP"] <- data[, SNPs[j]]
        fit <- glm(CC ~ AGE + SNP, data=data, family=binomial())
        coef <- summary(fit)\$coefficients
        beta[j, i] <- coef["SNP", 1]
        sigma[j, i] <- coef["SNP", 2]
      }
    }
    
    # 2. Run subset-based meta-analysis using h.traits (unrestricted search)
    res1 <- h.traits(SNPs, studies, beta, sigma, case, control, meta=TRUE)
    sum1 <- h.summary(res1)
    
    # 3. Define a custom subset search function and run h.traits with restricted subset search
    sub.def <- function(logicalVec) {
      sum <- sum(logicalVec)  
      ret <- all(logicalVec[1:sum])
      ret
    }
    
    res2 <- h.traits(SNPs, studies, beta, sigma, case, control, meta=TRUE, 
             zmax.args=list(sub.def=sub.def), pval.args=list(sub.def=sub.def))
    sum2 <- h.summary(res2)
    
    # 4. Save results to output files
    # Save RDS objects of the analysis results
    saveRDS(res1, file="asset_results_unrestricted.rds")
    saveRDS(res2, file="asset_results_restricted.rds")
    
    # Save CSV tables of the summaries
    write.csv(sum1\$Meta, file="unrestricted_meta.csv", row.names=FALSE)
    write.csv(sum1\$Subset.1sided, file="unrestricted_subset_1sided.csv", row.names=FALSE)
    write.csv(sum1\$Subset.2sided, file="unrestricted_subset_2sided.csv", row.names=FALSE)
    
    write.csv(sum2\$Meta, file="restricted_meta.csv", row.names=FALSE)
    write.csv(sum2\$Subset.1sided, file="restricted_subset_1sided.csv", row.names=FALSE)
    write.csv(sum2\$Subset.2sided, file="restricted_subset_2sided.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS":',
        paste0('    ASSET: ', as.character(packageVersion('ASSET')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meta_analysis_heterogeneous_traits.csv versions.yml
    """
}

workflow BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vdata.rda ] ]

    main:
    BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS(ch_input)

    emit:
    tables   = BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS.out.tables
    plots    = BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS.out.plots
    objects  = BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS.out.objects
    versions = BIOC_ASSET_META_ANALYSIS_HETEROGENEOUS_TRAITS.out.versions
}
