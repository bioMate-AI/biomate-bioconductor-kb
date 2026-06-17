#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rtpca — single_condition_tpca
// Run TPCA on a single condition to evaluate how well TPP data captures known protein-protein interactions or protein complexes.
// Input: tpp_data.RData, ppi_annotations.csv, complex_annotations.csv
// Container: quay.io/biocontainers/bioconductor-rtpca:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Rtpca
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run TPCA for protein-protein interactions using runTPCA
//  * 2. [Core Analysis] Run TPCA for protein complexes using runTPCA
//  * 3. [Visualization & Output] Plot ROC curve for protein-protein interactions using plotPPiRoc
//  * 4. [Visualization & Output] Plot ROC curve for protein complexes using plotComplexRoc

nextflow.enable.dsl = 2

process BIOC_RTPCA_SINGLE_CONDITION_TPCA {
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
    .bm_deps <- c("Rtpca")
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
        library(Rtpca)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files
        # -----------------------------------------------------------------------------
        
        # Load the TPP dataset (list of ExpressionSet objects or matrices)
        env <- new.env()
        load("tpp_data.RData", envir = env)
        loaded_objects <- ls(env)
        
        if ("trData" %in% loaded_objects) {
            trData <- env\$trData
        } else {
            # Fallback: take the first loaded object
            trData <- env[[loaded_objects[1]]]
        }
        
        # Read protein-protein interactions annotations
        string_ppi_cs_950_df <- read.csv("ppi_annotations.csv", stringsAsFactors = FALSE)
        
        # If the input contains a combined_score column, apply the >= 950 filter as in the vignette
        if ("combined_score" %in% colnames(string_ppi_cs_950_df)) {
            string_ppi_cs_950_df <- string_ppi_cs_950_df[string_ppi_cs_950_df\$combined_score >= 950, ]
        }
        
        # Read protein complex annotations
        ori_et_al_complexes_df <- read.csv("complex_annotations.csv", stringsAsFactors = FALSE)
        
        
        # -----------------------------------------------------------------------------
        # 2. Run TPCA for Protein-Protein Interactions
        # -----------------------------------------------------------------------------
        vehTPCA <- runTPCA(
            objList = trData,
            ppiAnno = string_ppi_cs_950_df
        )
        
        
        # -----------------------------------------------------------------------------
        # 3. Run TPCA for Protein Complexes
        # -----------------------------------------------------------------------------
        vehComplexTPCA <- runTPCA(
            objList = trData,
            complexAnno = ori_et_al_complexes_df,
            minCount = 2
        )
        
        
        # -----------------------------------------------------------------------------
        # 4. Plot ROC Curves and Save Outputs
        # -----------------------------------------------------------------------------
        
        # Plot and save PPI ROC curve
        pdf("ppi_roc_plot.pdf", width = 6, height = 6)
        print(plotPPiRoc(vehTPCA, computeAUC = TRUE))
        dev.off()
        
        # Plot and save Complex ROC curve
        pdf("complex_roc_plot.pdf", width = 6, height = 6)
        print(plotComplexRoc(vehComplexTPCA, computeAUC = TRUE))
        dev.off()
        
        # Save the TPCA results as RDS objects for downstream analysis
        saveRDS(vehTPCA, "vehTPCA.rds")
        saveRDS(vehComplexTPCA, "vehComplexTPCA.rds")

    writeLines(c(
        '"BIOC_RTPCA_SINGLE_CONDITION_TPCA":',
        paste0('    Rtpca: ', as.character(packageVersion('Rtpca')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_condition_tpca.csv versions.yml
    """
}

workflow BIOC_RTPCA_SINGLE_CONDITION_TPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tpp_data.RData, ppi_annotations.csv, complex_annotations.csv ] ]

    main:
    BIOC_RTPCA_SINGLE_CONDITION_TPCA(ch_input)

    emit:
    tables   = BIOC_RTPCA_SINGLE_CONDITION_TPCA.out.tables
    plots    = BIOC_RTPCA_SINGLE_CONDITION_TPCA.out.plots
    objects  = BIOC_RTPCA_SINGLE_CONDITION_TPCA.out.objects
    versions = BIOC_RTPCA_SINGLE_CONDITION_TPCA.out.versions
}
