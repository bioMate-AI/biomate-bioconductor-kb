#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spicyR — survival_analysis
// Assess whether changes in co-localization between cell types are associated with patient survival probability.
// Input: kerenSPE
// Container: quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0
// R packages: SpatialExperiment, SummarizedExperiment, spicyR, survival
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPICYR_SURVIVAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("SpatialExperiment", "SummarizedExperiment", "spicyR", "survival")
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
    
    # Load required packages
    library(SummarizedExperiment)
    library(SpatialExperiment)
    library(survival)
    
    # Workaround for S4 method dispatch bug in spicyR
    methods::setClassUnion("ExpData", c("matrix", "dgCMatrix", "ExpressionSet", "SummarizedExperiment"))
    
    library(spicyR)
    
    # Read user input
    if (file.exists("kerenSPE")) {
      kerenSPE <- readRDS("kerenSPE")
    } else if (file.exists("kerenSPE.rds")) {
      kerenSPE <- readRDS("kerenSPE.rds")
    } else {
      stop("Input file 'kerenSPE' or 'kerenSPE.rds' not found in the working directory.")
    }
    
    # --- Create a Surv object and store it in the "survival" ---
    kerenSPE\$event = 1 - kerenSPE\$Censored
    kerenSPE\$survival = Surv(kerenSPE\$`Survival_days_capped*`, kerenSPE\$event)
    
    # --- Run spicy() with condition set to "survival" ---
    spicySurvival = spicy(kerenSPE,
                          condition = "survival")
    
    # --- Access the survival analysis results from the ---
    survival_results_head <- head(spicySurvival\$survivalResults, 10)
    print(survival_results_head)
    
    # Write named output files for the meaningful results
    write.csv(spicySurvival\$survivalResults, "spicy_survival_results.csv", row.names = FALSE)
    saveRDS(spicySurvival, "spicySurvival.rds")

    writeLines(c(
        '"BIOC_SPICYR_SURVIVAL_ANALYSIS":',
        paste0('        spicyR: ', as.character(packageVersion("spicyR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_analysis.csv versions.yml
    """
}

workflow BIOC_SPICYR_SURVIVAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kerenSPE ] ]

    main:
    BIOC_SPICYR_SURVIVAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPICYR_SURVIVAL_ANALYSIS.out.tables
    plots    = BIOC_SPICYR_SURVIVAL_ANALYSIS.out.plots
    objects  = BIOC_SPICYR_SURVIVAL_ANALYSIS.out.objects
    versions = BIOC_SPICYR_SURVIVAL_ANALYSIS.out.versions
}
