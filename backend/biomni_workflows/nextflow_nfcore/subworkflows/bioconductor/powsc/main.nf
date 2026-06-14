#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: POWSC — two_group_power_analysis
// Perform power and sample size analysis for a two-group comparison (within cell type) using pilot/template scRNA-seq data
// Input: pilot_data.rds
// Container: quay.io/biocontainers/bioconductor-powsc:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: POWSC, SingleCellExperiment
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter template data for a specific cell type
//  * 2. [Core Analysis] Estimate parameters using Est2Phase
//  * 3. [Core Analysis] Simulate two-group SingleCellExperiment datasets using Simulate2SCE
//  * 4. [Core Analysis] Run differential expression analysis using runDE
//  * 5. [Core Analysis] Evaluate discrete and continuous power using Power_Disc and Power_Cont

nextflow.enable.dsl = 2

process BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("POWSC", "MAST", "SummarizedExperiment")
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
    suppressPackageStartupMessages({
      library(POWSC)
      library(SummarizedExperiment)
      library(MAST)
    })
    
    # 1. Read the user input file
    if (!file.exists("pilot_data.rds")) {
      stop("Error: 'pilot_data.rds' not found in the working directory.")
    }
    
    es_mef_sce <- readRDS("pilot_data.rds")
    
    # Ensure colData has cellTypes; if not, create a dummy column
    if (!"cellTypes" %in% colnames(colData(es_mef_sce))) {
      colData(es_mef_sce)\$cellTypes <- "fibro"
    }
    
    # Determine target cell type (default to "fibro", fallback to first available)
    target_celltype <- "fibro"
    available_celltypes <- unique(colData(es_mef_sce)\$cellTypes)
    if (!target_celltype %in% available_celltypes) {
      target_celltype <- available_celltypes[1]
    }
    
    # Filter template data for the specific cell type
    sce <- es_mef_sce[, colData(es_mef_sce)\$cellTypes == target_celltype]
    
    # Downsample genes to 500 (or maximum available) as in the documented code
    set.seed(12)
    n_genes <- min(500, nrow(sce))
    rix <- sample(1:nrow(sce), n_genes)
    sce <- sce[rix, ]
    
    # 2. Estimate parameters using Est2Phase
    est_Paras <- Est2Phase(sce)
    
    # 3. Simulate two-group SingleCellExperiment datasets using Simulate2SCE
    simData <- Simulate2SCE(n=100, estParas1 = est_Paras, estParas2 = est_Paras)
    
    # 4. Run differential expression analysis using runDE
    de <- runDE(simData\$sce, DE_Method = "MAST")
    
    # 5. Evaluate discrete and continuous power using Power_Disc and Power_Cont
    estPower1 <- Power_Disc(de, simData = simData)
    estPower2 <- Power_Cont(de, simData = simData)
    
    # Save results to RDS files
    saveRDS(estPower1, "estPower1_discrete.rds")
    saveRDS(estPower2, "estPower2_continuous.rds")
    
    # Save power tables to CSV if available
    if (!is.null(estPower1\$power)) {
      write.csv(as.data.frame(estPower1\$power), "power_discrete_table.csv", row.names = TRUE)
    }
    if (!is.null(estPower2\$power)) {
      write.csv(as.data.frame(estPower2\$power), "power_continuous_table.csv", row.names = TRUE)
    }
    
    # Save marginal power summary
    summary_df <- data.frame(
      Metric = c("Discrete_Marginal_Power", "Continuous_Marginal_Power"),
      Value = c(
        ifelse(is.null(estPower1\$power.marginal), NA, estPower1\$power.marginal),
        ifelse(is.null(estPower2\$power.marginal), NA, estPower2\$power.marginal)
      )
    )
    write.csv(summary_df, "power_marginal_summary.csv", row.names = FALSE)
    
    # Generate diagnostic plots
    pdf("power_analysis_plots.pdf", width = 7, height = 5)
    if (!is.null(estPower1\$power)) {
      tryCatch({
        barplot(estPower1\$power, main = "Discrete Power by Stratum", 
                xlab = "Stratum", ylab = "Power", col = "skyblue")
      }, error = function(e) {
        message("Could not plot discrete power: ", e\$message)
      })
    }
    if (!is.null(estPower2\$power)) {
      tryCatch({
        barplot(estPower2\$power, main = "Continuous Power by Stratum", 
                xlab = "Stratum", ylab = "Power", col = "coral")
      }, error = function(e) {
        message("Could not plot continuous power: ", e\$message)
      })
    }
    dev.off()
    
    message("POWSC workflow completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS":',
        paste0('    POWSC: ', as.character(packageVersion('POWSC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_group_power_analysis.csv versions.yml
    """
}

workflow BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pilot_data.rds ] ]

    main:
    BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS.out.tables
    plots    = BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS.out.plots
    objects  = BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS.out.objects
    versions = BIOC_POWSC_TWO_GROUP_POWER_ANALYSIS.out.versions
}
