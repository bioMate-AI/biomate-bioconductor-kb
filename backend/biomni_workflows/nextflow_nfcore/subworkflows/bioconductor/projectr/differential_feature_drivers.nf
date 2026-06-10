#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: projectR — differential_feature_drivers
// Identify and visualize differential features (genes) between two cell groups weighted by their loadings in a specific latent space.
// Input: group1_expression.csv, group2_expression.csv, pattern_loadings.csv
// Container: quay.io/biocontainers/bioconductor-projectr:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cowplot, dplyr, ggplot2, ggrepel, projectR
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run projectionDriveR in Confidence Interval ("CI") mode to identify significantly different features
//  * 2. [Visualization & Output] Run projectionDriveR in P-value ("PV") mode to perform Welch t-tests and generate volcano plot data
//  * 3. [Visualization & Output] Plot confidence intervals of the estimates using plotConfidenceIntervals
//  * 4. [Visualization & Output] Customize volcano plots and adjust fold-change/p-value thresholds using pdVolcano

nextflow.enable.dsl = 2

process BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        library(projectR)
        library(dplyr)
        library(ggplot2)
        library(cowplot)
        library(ggrepel)
        
        # Read user input files from the working directory
        microglial_counts <- as.matrix(read.csv("group1_expression.csv", row.names = 1, check.names = FALSE))
        glial_counts <- as.matrix(read.csv("group2_expression.csv", row.names = 1, check.names = FALSE))
        microglial_fl <- read.csv("pattern_loadings.csv", row.names = 1, check.names = FALSE)
        
        # Identify the pattern to weight (defaulting to the first pattern column in the loadings matrix)
        pattern_to_weight <- colnames(microglial_fl)[1]
        
        # 1. Run projectionDriveR in Confidence Interval ("CI") mode
        drivers_ci <- projectionDriveR(microglial_counts, #expression matrix
                                               glial_counts, #expression matrix
                                               loadings = microglial_fl, #feature x pattern dataframe
                                               loadingsNames = NULL,
                                               pattern_name = pattern_to_weight, #column name
                                               pvalue = 1e-5, #pvalue before bonferroni correction
                                               display = T,
                                               normalize_pattern = T, #normalize feature weights
                                               mode = "CI") #confidence interval mode
        
        # Extract confidence intervals for significantly shared genes
        conf_intervals <- drivers_ci\$mean_ci[drivers_ci\$sig_genes\$significant_shared_genes, , drop = FALSE]
        
        # 2. Run projectionDriveR in P-value ("PV") mode
        drivers_pv <- projectionDriveR(microglial_counts, #expression matrix
                                               glial_counts, #expression matrix
                                               loadings = microglial_fl, #feature x pattern dataframe
                                               loadingsNames = NULL,
                                               pattern_name = pattern_to_weight, #column name
                                               pvalue = 1e-5, #pvalue before bonferroni correction
                                               display = T,
                                               normalize_pattern = T, #normalize feature weights
                                               mode = "PV") #confidence interval mode
        
        difexp <- drivers_pv\$difexpgenes
        
        # 3. Plot confidence intervals of the estimates using plotConfidenceIntervals
        if (nrow(conf_intervals) > 0) {
            # Order in ascending order of estimates while preserving rownames
            conf_intervals\$rn_save <- rownames(conf_intervals)
            conf_intervals <- conf_intervals %>% mutate(mid = (high+low)/2) %>% arrange(mid)
            rownames(conf_intervals) <- conf_intervals\$rn_save
            conf_intervals\$rn_save <- NULL
            gene_order <- rownames(conf_intervals)
        
            # Add text labels for top and bottom n genes
            conf_intervals\$label_name <- NA_character_
            n <- min(2, nrow(conf_intervals))
            if (n > 0) {
                idx <- c(1:n, (dim(conf_intervals)[1]-(n-1)):dim(conf_intervals)[1])
                idx <- unique(idx[idx > 0 & idx <= nrow(conf_intervals)])
                gene_ids <- gene_order[idx]
                conf_intervals\$label_name[idx] <- gene_ids
            }
        
            # Generate confidence interval plots
            plots_list <- plotConfidenceIntervals(conf_intervals, #mean difference in expression confidence intervals
                                                  sort = F, #should genes be sorted by estimates
                                                  weights = drivers_ci\$normalized_weights[rownames(conf_intervals)],
                                                  pattern_name = pattern_to_weight,
                                                  weights_clip = 0.99,
                                                  weights_vis_norm = "none")
        
            pl1 <- plots_list[["ci_estimates_plot"]]
            if ("label_name" %in% colnames(conf_intervals) && any(!is.na(conf_intervals\$label_name))) {
                pl1 <- pl1 + ggrepel::geom_label_repel(aes(label = label_name), max.overlaps = 20, force = 50)
            }
            pl2 <- plots_list[["weights_heatmap"]]
        
            # Plot the weighted differences
            weighted_conf_intervals <- drivers_ci\$weighted_mean_ci[gene_order, , drop = FALSE]
            plots_list_weighted <- plotConfidenceIntervals(weighted_conf_intervals,
                                                           sort = F,
                                                           weighted = T)
        
            pl3 <- plots_list_weighted[["ci_estimates_plot"]] +
              xlab("Difference in weighted group means") +
              theme(axis.title.y = element_blank(), axis.ticks.y = element_blank(), axis.text.y = element_blank())
        
            # Save confidence intervals plot
            pdf("confidence_intervals_plot.pdf", width = 12, height = 6)
            print(cowplot::plot_grid(pl1, pl2, pl3, align = "h", rel_widths = c(1, .4, 1), ncol = 3))
            dev.off()
        } else {
            message("No significant shared genes found; skipping confidence interval plot generation.")
        }
        
        # 4. Customize volcano plots and adjust fold-change/p-value thresholds using pdVolcano
        drivers_pv_mod <- pdVolcano(drivers_pv, FC = 0.5, pvalue = 1e-7)
        
        # Save customized volcano plot if available
        if (!is.null(drivers_pv_mod\$plt)) {
            pdf("volcano_plot.pdf", width = 8, height = 8)
            print(drivers_pv_mod\$plt)
            dev.off()
        }
        
        # Write output tables and RDS objects
        write.csv(conf_intervals, "conf_intervals.csv", row.names = TRUE)
        write.csv(difexp, "difexp.csv", row.names = TRUE)
        write.csv(drivers_pv_mod\$difexpgenes, "difexp_modified.csv", row.names = TRUE)
        
        saveRDS(drivers_ci, "drivers_ci.rds")
        saveRDS(drivers_pv, "drivers_pv.rds")
        saveRDS(drivers_pv_mod, "drivers_pv_mod.rds")
        
        message("Pipeline completed successfully. Outputs written to the working directory.")

    writeLines(c(
        '"BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS":',
        paste0('    projectR: ', as.character(packageVersion('projectR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_feature_drivers.csv versions.yml
    """
}

workflow BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ group1_expression.csv, group2_expression.csv, pattern_loadings.csv ] ]

    main:
    BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS(ch_input)

    emit:
    tables   = BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS.out.tables
    plots    = BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS.out.plots
    objects  = BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS.out.objects
    versions = BIOC_PROJECTR_DIFFERENTIAL_FEATURE_DRIVERS.out.versions
}
