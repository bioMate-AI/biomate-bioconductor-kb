#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: POWSC — multiple_group_power_analysis
// Perform power and sample size analysis for multiple-group comparisons (between cell types) using pilot/template scRNA-seq data with multiple cell types and pati
// Input: multi_cell_pilot_data.rds
// Container: quay.io/biocontainers/bioconductor-powsc:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: POWSC, RColorBrewer, SingleCellExperiment, pheatmap
// Visualizations: heatmap, heatmap (ComplexHeatmap)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract expression matrix and metadata
//  * 2. [Core Analysis] Estimate parameters for each cell type using Est2Phase
//  * 3. [Core Analysis] Simulate multiple-group SingleCellExperiment datasets using SimulateMultiSCEs with specified cell type proportions
//  * 4. [Core Analysis] Run pairwise differential expression analysis using runDE
//  * 5. [Core Analysis] Evaluate discrete and continuous power for each comparison using Power_Disc and Power_Cont
//  * 6. [Visualization & Output] Visualize power results using a heatmap

nextflow.enable.dsl = 2

process BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS {
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
    .bm_deps <- c("POWSC", "RColorBrewer", "pheatmap")
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
            library(POWSC)
            library(RColorBrewer)
            library(pheatmap)
            
            # 1. Extract expression matrix and metadata from user input
            sce <- readRDS("multi_cell_pilot_data.rds")
            col <- colData(sce)
            exprs <- assays(sce)\$counts
            
            # Dynamically identify patient and cell type columns
            patient_col <- grep("patient|sample", colnames(col), ignore.case = TRUE, value = TRUE)[1]
            if (is.na(patient_col)) patient_col <- colnames(col)[1]
            
            celltype_col <- grep("cell.*type|cluster", colnames(col), ignore.case = TRUE, value = TRUE)[1]
            if (is.na(celltype_col)) celltype_col <- colnames(col)[2]
            
            # Print table of Patients vs cellTypes for user reference
            print(table(col[[patient_col]], col[[celltype_col]]))
            
            # Define simulation parameters
            sim_size = 200 # use a large sample is preferable
            cell_per = c(0.2, 0.3, 0.5)
            
            # Determine patient ID and cell types to use (with fallback to ensure robustness)
            patient_id <- "AB_S7"
            if (!(patient_id %in% col[[patient_col]])) {
                patient_id <- unique(col[[patient_col]])[1]
            }
            
            celltypes = c("oligodendrocytes", "hybrid", "neurons")
            if (!all(celltypes %in% col[[celltype_col]])) {
                # Fallback to top most abundant cell types in the selected patient (up to 3)
                patient_cells <- col[[celltype_col]][which(col[[patient_col]] == patient_id)]
                sorted_cells <- names(sort(table(patient_cells), decreasing = TRUE))
                celltypes <- sorted_cells[1:min(3, length(sorted_cells))]
            }
            
            # Adjust cell_per to match the number of available cell types
            cell_per <- cell_per[1:length(celltypes)]
            cell_per <- cell_per / sum(cell_per)
            
            # 2. Estimate parameters for each cell type using Est2Phase
            estParas_set = NULL
            for (cp in celltypes){
                print(paste("Estimating parameters for cell type:", cp))
                ix = intersect(which(col[[celltype_col]] == cp), which(col[[patient_col]] == patient_id))
                tmp_mat = exprs[, ix, drop = FALSE]
                tmp_paras = Est2Phase(tmp_mat)
                estParas_set[[cp]] = tmp_paras
            }
            
            # 3. Simulate multiple-group SingleCellExperiment datasets using SimulateMultiSCEs
            sim = SimulateMultiSCEs(n = sim_size, estParas_set = estParas_set, multiProb = cell_per)
            
            # 4. Run pairwise differential expression analysis using runDE
            DE_rslt = NULL
            for (comp in names(sim)){
                print(paste("Running DE for comparison:", comp))
                tmp = runDE(sim[[comp]]\$sce, DE_Method = "MAST")
                DE_rslt[[comp]] = tmp
            }
            
            # 5. Evaluate discrete and continuous power for each comparison using Power_Disc and Power_Cont
            pow_rslt = pow1 = pow2 = pow1_marg = pow2_marg = NULL
            TD = CD = NULL
            for (comp in names(sim)){
                print(paste("Evaluating power for comparison:", comp))
                tmp1 = Power_Disc(DE_rslt[[comp]], sim[[comp]])
                tmp2 = Power_Cont(DE_rslt[[comp]], sim[[comp]])
                TD = c(TD, tmp2\$TD); CD = c(CD, tmp2\$CD)
                pow1_marg = c(pow1_marg, tmp1\$power.marginal)
                pow2_marg = c(pow2_marg, tmp2\$power.marginal)
                pow_rslt[[comp]] = list(pow1 = tmp1, pow2 = tmp2)
                pow1 = rbind(pow1, tmp1\$power)
                pow2 = rbind(pow2, tmp2\$power)
            }
            
            # Set dimension names for the power matrices
            dimnames(pow1) = list(names(sim), names(tmp1\$CD))
            dimnames(pow2) = list(names(sim), names(tmp2\$CD))
            
            # 6. Visualize power results using a heatmap and save outputs
            breaksList = seq(0, 1, by = 0.01)
            colors = colorRampPalette(rev(brewer.pal(n = 7, name = "RdYlBu")))(length(breaksList))
            
            # Save heatmap to PDF
            pdf("power_heatmap.pdf", width = 8, height = 6)
            pheatmap(pow2, display_numbers = TRUE, color=colors, show_rownames = TRUE,
                     cellwidth = 30, cellheight = 40, legend = TRUE,
                     border_color = "grey96", na_col = "grey",
                     cluster_row = FALSE, cluster_cols = FALSE,
                     breaks = seq(0, 1, 0.01),
                     main = "Power Analysis Heatmap (Continuous)")
            dev.off()
            
            # Save tabular results
            write.csv(pow1, "power_discrete_results.csv", row.names = TRUE)
            write.csv(pow2, "power_continuous_results.csv", row.names = TRUE)
            
            # Save complete power results object
            saveRDS(pow_rslt, "power_analysis_results.rds")
            
            print("Workflow completed successfully. Outputs saved: power_heatmap.pdf, power_discrete_results.csv, power_continuous_results.csv, power_analysis_results.rds")

    writeLines(c(
        '"BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS":',
        paste0('    POWSC: ', as.character(packageVersion('POWSC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_group_power_analysis.csv versions.yml
    """
}

workflow BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_cell_pilot_data.rds ] ]

    main:
    BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS.out.tables
    plots    = BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS.out.plots
    objects  = BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS.out.objects
    versions = BIOC_POWSC_MULTIPLE_GROUP_POWER_ANALYSIS.out.versions
}
