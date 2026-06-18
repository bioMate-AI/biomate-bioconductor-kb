#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpeCond — stepwise_specond_analysis
// Perform condition-specific gene detection step-by-step to allow saving of intermediate fits and efficient parameter tuning.
// Input: expression_matrix.txt
// Container: quay.io/biocontainers/bioconductor-specond:1.64.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpeCond
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the mixture model with a prior on variance (Step 1)
//  * 2. [Core Analysis] Detect single outliers from Step 1
//  * 3. [Core Analysis] Fit the mixture model excluding Step 1 outliers (Step 2)
//  * 4. [Core Analysis] Detect final condition-specific genes and obtain the specific results

nextflow.enable.dsl = 2

process BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS {
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
    .bm_deps <- c("SpeCond")
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
    
    # Load the required Bioconductor library
    library(SpeCond)
    
    # Read the user input file from the working directory
    if (!file.exists("expression_matrix.txt")) {
      stop("Error: 'expression_matrix.txt' not found in the working directory.")
    }
    
    # Read the expression matrix (log2 values, genes as rows, conditions as columns)
    Mexp_df <- read.table("expression_matrix.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    Mexp <- as.matrix(Mexp_df)
    
    # Stepwise SpeCond Analysis
    # 1. Get default parameters
    param.detection=getDefaultParameter()
    
    # 2. Fit the mixture model with a prior on variance (Step 1)
    fit1=fitPrior(Mexp, param.detection=param.detection)
    
    # 3. Detect single outliers from Step 1
    specificOutlierStep1=getSpecificOutliersStep1(Mexp, fit=fit1\$fit1,param.detection, multitest.correction.method="BY", prefix.file="run1_Step1", print.hist.pv=FALSE)
    
    # 4. Fit the mixture model excluding Step 1 outliers (Step 2)
    fit2=fitNoPriorWithExclusion(Mexp, specificOutlierStep1=specificOutlierStep1, param.detection=param.detection)
    
    # 5. Detect final condition-specific genes and obtain the specific results
    specificResult=getSpecificResult(Mexp, fit=fit2, specificOutlierStep1=specificOutlierStep1, param.detection, multitest.correction.method="BY", prefix.file="run1_Step2", print.hist.pv=FALSE)
    
    # Save intermediate and final R objects as RDS files
    saveRDS(fit1, file = "fit1.rds")
    saveRDS(specificOutlierStep1, file = "specificOutlierStep1.rds")
    saveRDS(fit2, file = "fit2.rds")
    saveRDS(specificResult, file = "specificResult.rds")
    
    # Write meaningful text outputs if condition-specific genes are detected
    if (!is.null(specificResult\$L.specific.result\$M.specific)) {
      writeSpeCondResult(
        specificResult\$L.specific.result,
        file.name.profile = "specific_profile.txt",
        file.specific.gene = "list_specific_gene.txt",
        file.name.unique.profile = "specific_unique_profile.txt"
      )
    } else {
      message("No condition-specific genes were detected with the current parameters.")
    }

    writeLines(c(
        '"BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS":',
        paste0('    SpeCond: ', as.character(packageVersion('SpeCond')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stepwise_specond_analysis.csv versions.yml
    """
}

workflow BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.txt ] ]

    main:
    BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS.out.tables
    plots    = BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS.out.plots
    objects  = BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS.out.objects
    versions = BIOC_SPECOND_STEPWISE_SPECOND_ANALYSIS.out.versions
}
