#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: plgem — wrapper_mode
// Run the entire PLGEM pipeline in a single step using the wrapper function to identify differentially expressed genes or proteins.
// Input: ExpressionSet object
// Container: quay.io/biocontainers/bioconductor-plgem:1.82.0--r45hdfd78af_0
// R packages: Biobase, plgem
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, plgem
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and dataset
//  * 2. [Core Analysis] Set the random seed for reproducibility
//  * 3. [Core Analysis] Run the wrapper function run.plgem to identify differentially expressed genes/proteins

nextflow.enable.dsl = 2

process BIOC_PLGEM_WRAPPER_MODE {
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
    .bm_deps <- c("Biobase", "plgem")
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
    
    # 1. Load the package and dataset
    library(plgem)
    library(Biobase)
    
    # Read the user-provided ExpressionSet object from the working directory
    LPSeset <- readRDS("expression_set.rds")
    
    # 2. Set the random seed for reproducibility
    set.seed(123)
    
    # 3. Run the wrapper function run.plgem to identify differentially expressed genes/proteins
    LPSdegList <- run.plgem(esdata=LPSeset)
    
    # 4. Write named output files for the meaningful results
    saveRDS(LPSdegList, "plgem_deg_list.rds")
    
    # Export significant genes to CSV files for each comparison and significance level
    if (!is.null(LPSdegList\$significant) && length(LPSdegList\$significant) > 0) {
      for (delta_val in names(LPSdegList\$significant)) {
        comparisons <- LPSdegList\$significant[[delta_val]]
        for (comp_name in names(comparisons)) {
          deg_data <- comparisons[[comp_name]]
          df_out <- data.frame(
            GeneID = names(deg_data),
            Observed_STN = as.numeric(deg_data),
            stringsAsFactors = FALSE
          )
          # Clean comparison name for filename safety
          safe_comp_name <- gsub("[^A-Za-z0-9_]", "_", comp_name)
          output_filename <- paste0("significant_genes_", safe_comp_name, "_delta_", delta_val, ".csv")
          write.csv(df_out, output_filename, row.names = FALSE)
        }
      }
    }

    writeLines(c(
        '"BIOC_PLGEM_WRAPPER_MODE":',
        paste0('    plgem: ', as.character(packageVersion('plgem')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wrapper_mode.csv versions.yml
    """
}

workflow BIOC_PLGEM_WRAPPER_MODE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet object ] ]

    main:
    BIOC_PLGEM_WRAPPER_MODE(ch_input)

    emit:
    tables   = BIOC_PLGEM_WRAPPER_MODE.out.tables
    plots    = BIOC_PLGEM_WRAPPER_MODE.out.plots
    objects  = BIOC_PLGEM_WRAPPER_MODE.out.objects
    versions = BIOC_PLGEM_WRAPPER_MODE.out.versions
}
