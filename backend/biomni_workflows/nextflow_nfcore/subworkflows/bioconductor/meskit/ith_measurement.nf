#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MesKit — ith_measurement
// Quantify and visualize intra-tumor heterogeneity (ITH) within tumors and genetic divergence between regions.
// Input: maf
// Container: quay.io/biocontainers/bioconductor-meskit:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MesKit, cowplot, ggplot2
// Visualizations: density plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate mutant-allele tumor heterogeneity (MATH) scores
//  * 2. [Core Analysis] Calculate the area under the curve (AUC) of the
//  * 3. [Core Analysis] Cluster mutations in one dimension by VAFs or CCFs
//  * 4. [Core Analysis] Calculate Wright's fixation index (Fst) between regions
//  * 5. [Core Analysis] Calculate Nei's genetic distance between regions

nextflow.enable.dsl = 2

process BIOC_MESKIT_ITH_MEASUREMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(MesKit)
    library(cowplot)
    library(ggplot2)
    
    # ==========================================
    # 1. Read User Input
    # ==========================================
    # The pipeline expects a pre-constructed Maf object saved as an RDS file named 'maf' or 'maf.rds'
    if (file.exists("maf")) {
      maf <- readRDS("maf")
    } else if (file.exists("maf.rds")) {
      maf <- readRDS("maf.rds")
    } else {
      stop("Error: Input Maf object file ('maf' or 'maf.rds') not found in the working directory.")
    }
    
    # ==========================================
    # 2. Execute ITH Measurement Workflow
    # ==========================================
    
    # --- Estimate mutant-allele tumor heterogeneity (MATH) scores ---
    message("Calculating MATH scores...")
    math_scores <- mathScore(maf)
    math_scores_df <- do.call(rbind, math_scores)
    write.csv(math_scores_df, file = "math_scores.csv", row.names = FALSE)
    
    # --- Calculate the area under the curve (AUC) of the ---
    message("Calculating CCF AUC...")
    AUC <- ccfAUC(maf, use.tumorSampleLabel = TRUE)
    print(names(AUC))
    
    # Save AUC values
    if (!is.null(AUC\$AUC.value)) {
      write.csv(AUC\$AUC.value, file = "auc_values.csv", row.names = FALSE)
    }
    
    # Save cumulative density plot of CCF
    if (!is.null(AUC\$CCF.density.plot)) {
      ggsave(filename = "ccf_density_plot.pdf", plot = AUC\$CCF.density.plot, width = 7, height = 6)
    }
    
    # --- Cluster mutations in one dimension by VAFs or CCFs ---
    message("Clustering mutations...")
    mut.cluster <- mutCluster(maf, use.ccf = TRUE, use.tumorSampleLabel = TRUE)
    clusterPlots <- mut.cluster\$cluster.plot
    
    # Save mutation clustering plot grid
    # Ensure we do not exceed the available number of plots
    num_plots <- min(6, length(clusterPlots))
    if (num_plots > 0) {
      p_grid <- cowplot::plot_grid(plotlist = clusterPlots[1:num_plots])
      ggsave(filename = "mutation_clusters_plot.pdf", plot = p_grid, width = 12, height = 8)
    }
    
    # --- Calculate Wright's fixation index (Fst) between regions ---
    message("Calculating Fst...")
    fst_all <- calFst(maf, plot = TRUE, use.tumorSampleLabel = TRUE, 
                      withinTumor  = TRUE, number.cex = 10)
    fst_bm <- if (length(fst_all) > 0) fst_all[[1]] else NULL
    
    # Save Fst results
    saveRDS(fst_all, file = "fst_results.rds")
    if (!is.null(fst_bm)) {
      if (!is.null(fst_bm\$Fst.pair)) {
        write.csv(as.data.frame(fst_bm\$Fst.pair), file = "fst_pairwise_matrix.csv")
      }
      if (!is.null(fst_bm\$Fst.plot)) {
        ggsave(filename = "fst_plot.pdf", plot = fst_bm\$Fst.plot, width = 7, height = 6)
      }
    }
    
    # --- Calculate Nei's genetic distance between regions ---
    message("Calculating Nei's genetic distance...")
    nei_all <- calNeiDist(maf, use.tumorSampleLabel = TRUE, 
                          withinTumor  = TRUE, number.cex = 10)
    nei_bm <- if (length(nei_all) > 0) nei_all[[1]] else NULL
    
    # Save Nei's genetic distance results
    saveRDS(nei_all, file = "nei_distance_results.rds")
    if (!is.null(nei_bm)) {
      if (!is.null(nei_bm\$Nei.dist)) {
        write.csv(as.data.frame(nei_bm\$Nei.dist), file = "nei_distance_matrix.csv")
      }
      if (!is.null(nei_bm\$Nei.plot)) {
        ggsave(filename = "nei_distance_plot.pdf", plot = nei_bm\$Nei.plot, width = 7, height = 6)
      }
    }
    
    message("Workflow completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MESKIT_ITH_MEASUREMENT":',
        paste0('    MesKit: ', as.character(packageVersion('MesKit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ith_measurement.csv versions.yml
    """
}

workflow BIOC_MESKIT_ITH_MEASUREMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ maf ] ]

    main:
    BIOC_MESKIT_ITH_MEASUREMENT(ch_input)

    emit:
    tables   = BIOC_MESKIT_ITH_MEASUREMENT.out.tables
    plots    = BIOC_MESKIT_ITH_MEASUREMENT.out.plots
    objects  = BIOC_MESKIT_ITH_MEASUREMENT.out.objects
    versions = BIOC_MESKIT_ITH_MEASUREMENT.out.versions
}
