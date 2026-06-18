#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: omicRexposome — integration_analysis
// Integrate multiple datasets (exposome and multiple omics datasets) to find latent relationships using MCIA or MCCA after resolving missing values.
// Input: brge_expo, brge_gexp, brge_prot
// Container: quay.io/biocontainers/bioconductor-omicrexposome:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiDataSet, omicRexposome, rexposome
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load exposome and multiple omic datasets
//  * 2. [Visualization & Output] Check for missing values in the exposome dataset using plotMissings()
//  * 3. [Core Analysis] Impute missing values in the exposome dataset using imputation()
//  * 4. [Input & Preparation] Create a MultiDataSet object and add all datasets using createMultiDataSet(), add_genexp(), add_eset(), and add_exp()
//  * 5. [Core Analysis] Perform integration analysis using crossomics() with method = "mcia" or method = "mcca"
//  * 6. [Visualization & Output] Define colors for visualization
//  * 7. [Visualization & Output] Visualize the integrated datasets using plotIntegration()

nextflow.enable.dsl = 2

process BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS {
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
    .bm_deps <- c("omicRexposome", "MultiDataSet", "rexposome")
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
        library(omicRexposome)
        library(MultiDataSet)
        library(rexposome)
        
        # Helper function to load input files robustly (handles RDS or RData formats)
        load_input <- function(name) {
          if (file.exists(name)) {
            return(readRDS(name))
          } else if (file.exists(paste0(name, ".rds"))) {
            return(readRDS(paste0(name, ".rds")))
          } else if (file.exists(paste0(name, ".RData"))) {
            env <- new.env()
            load(paste0(name, ".RData"), envir = env)
            return(env[[ls(env)[1]]])
          } else {
            stop(paste("Input file not found:", name))
          }
        }
        
        # 1. Load exposome and multiple omic datasets
        brge_expo <- load_input("brge_expo")
        brge_gexp <- load_input("brge_gexp")
        brge_prot <- load_input("brge_prot")
        
        # 2. Check for missing values in the exposome dataset using plotMissings()
        pdf("missing_values_plot.pdf", width = 8, height = 6)
        print(plotMissings(brge_expo, set = "exposures"))
        dev.off()
        
        # 3. Impute missing values in the exposome dataset using imputation()
        brge_expo <- imputation(brge_expo)
        
        # 4. Create a MultiDataSet object and add all datasets
        mds <- createMultiDataSet()
        mds <- add_genexp(mds, brge_gexp)
        mds <- add_eset(mds, brge_prot, dataset.type = "proteome")
        mds <- add_exp(mds, brge_expo)
        
        # 5. Perform integration analysis using crossomics()
        cr_mcia <- crossomics(mds, method = "mcia", verbose = TRUE)
        saveRDS(cr_mcia, "cr_mcia_results.rds")
        
        cr_mcca <- crossomics(mds, method = "mcca", permute = c(4, 2))
        saveRDS(cr_mcca, "cr_mcca_results.rds")
        
        # 6. Define colors for visualization
        colors <- c("green", "blue", "red")
        names(colors) <- names(mds)
        
        # 7. Visualize the integrated datasets using plotIntegration()
        pdf("mcia_integration_plot.pdf", width = 10, height = 8)
        print(plotIntegration(cr_mcia, colors = colors))
        dev.off()
        
        pdf("mcca_integration_plot.pdf", width = 10, height = 8)
        print(plotIntegration(cr_mcca, colors = colors))
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS":',
        paste0('    omicRexposome: ', as.character(packageVersion('omicRexposome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integration_analysis.csv versions.yml
    """
}

workflow BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brge_expo, brge_gexp, brge_prot ] ]

    main:
    BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS.out.tables
    plots    = BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS.out.plots
    objects  = BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS.out.objects
    versions = BIOC_OMICREXPOSOME_INTEGRATION_ANALYSIS.out.versions
}
