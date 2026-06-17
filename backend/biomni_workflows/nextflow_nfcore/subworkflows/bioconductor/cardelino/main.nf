#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cardelino — clone_id_with_tree
// Assign cells to clones using scRNA-seq variant counts and a pre-defined clonal tree configuration.
// Input: cellSNP.cells.vcf.gz, canopy_results.coveraged.rds
// Container: quay.io/biocontainers/bioconductor-cardelino:1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cardelino, ggplot2, pheatmap
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load scRNA-seq variant data using load_cellSNP_vcf
//  * 2. [Input & Preparation] Load clonal tree configuration and align variant IDs
//  * 3. [Core Analysis] Run Bayesian clustering using clone_id with the configuration matrix
//  * 4. [Core Analysis] Assign cells to clones using assign_cells_to_clones
//  * 5. [Visualization & Output] Visualize results using prob_heatmap, heat_matrix, and vc_heatmap

nextflow.enable.dsl = 2

process BIOC_CARDELINO_CLONE_ID_WITH_TREE {
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
    .bm_deps <- c("ggplot2", "cardelino")
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
        library(ggplot2)
        library(cardelino)
        
        # 1. Load scRNA-seq variant data using load_cellSNP_vcf
        vcf_file <- "cellSNP.cells.vcf.gz"
        if (!file.exists(vcf_file)) {
          stop(paste("Required input file missing:", vcf_file))
        }
        input_data <- load_cellSNP_vcf(vcf_file)
        
        # Calculate allele frequency
        AF <- as.matrix(input_data\$A / input_data\$D)
        
        # Save allele frequency heatmap
        pdf("allele_frequency_heatmap.pdf", width = 8, height = 6)
        p <- pheatmap::pheatmap(AF, cluster_rows=FALSE, cluster_cols=FALSE, 
                                show_rownames = TRUE, show_colnames = TRUE, 
                                labels_row=paste(nrow(AF), 'SNVs'), labels_col=paste(ncol(AF), 'cells'), 
                                angle_col=0, angle_row=0)
        dev.off()
        
        # 2. Load clonal tree configuration and align variant IDs
        rds_file <- "canopy_results.coveraged.rds"
        if (!file.exists(rds_file)) {
          stop(paste("Required input file missing:", rds_file))
        }
        canopy_res <- readRDS(rds_file)
        Config <- canopy_res\$tree\$Z
        rownames(Config) <- gsub(":", "_", rownames(Config))
        
        # Save clonal tree plot
        pdf("clonal_tree_plot.pdf", width = 6, height = 6)
        plot_tree(canopy_res\$tree, orient = "v")
        dev.off()
        
        # 3. Run Bayesian clustering using clone_id with the configuration matrix
        set.seed(7)
        assignments <- clone_id(input_data\$A, input_data\$D, Config = Config)
        
        # Save assignments object
        saveRDS(assignments, "cardelino_assignments.rds")
        
        # Save assignment probability heatmap
        pdf("assignment_probability_heatmap.pdf", width = 6, height = 5)
        prob_heatmap(assignments\$prob)
        dev.off()
        
        # 4. Assign cells to clones using assign_cells_to_clones
        df <- assign_cells_to_clones(assignments\$prob)
        write.csv(df, "cell_clone_assignments.csv", row.names = FALSE)
        
        # Print summary to console
        cat("First few cell assignments:\n")
        print(head(df))
        cat("\nClone assignment table:\n")
        print(table(df\$clone))
        
        # 5. Visualize results using prob_heatmap, heat_matrix, and vc_heatmap
        pdf("clonal_config_changes.pdf", width = 7, height = 5)
        p_config <- heat_matrix(t(assignments\$Config_prob - Config)) + 
          scale_fill_gradient2() + 
          ggtitle('Changes of clonal Config') + 
          labs(x='Clones', y=paste(nrow(Config), 'SNVs')) + 
          theme(axis.text.y = element_blank(), legend.position = "right")
        print(p_config)
        dev.off()
        
        # Save final variant-cell heatmap
        pdf("variant_cell_heatmap.pdf", width = 8, height = 6)
        AF <- as.matrix(input_data\$A / input_data\$D)
        cardelino::vc_heatmap(AF, assignments\$prob, Config, show_legend=TRUE)
        dev.off()
        
        cat("\nPipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_CARDELINO_CLONE_ID_WITH_TREE":',
        paste0('    cardelino: ', as.character(packageVersion('cardelino')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clone_id_with_tree.csv versions.yml
    """
}

workflow BIOC_CARDELINO_CLONE_ID_WITH_TREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cellSNP.cells.vcf.gz, canopy_results.coveraged.rds ] ]

    main:
    BIOC_CARDELINO_CLONE_ID_WITH_TREE(ch_input)

    emit:
    tables   = BIOC_CARDELINO_CLONE_ID_WITH_TREE.out.tables
    plots    = BIOC_CARDELINO_CLONE_ID_WITH_TREE.out.plots
    objects  = BIOC_CARDELINO_CLONE_ID_WITH_TREE.out.objects
    versions = BIOC_CARDELINO_CLONE_ID_WITH_TREE.out.versions
}
