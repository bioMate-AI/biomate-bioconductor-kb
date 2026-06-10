#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAST — gene_set_enrichment_analysis
// Perform competitive gene set enrichment analysis (GSEA) on Hurdle model coefficients using bootstrapping to account for intergene correlation.
// Input: fitted_zlm_model.rds, gene_sets.gmt
// Container: quay.io/biocontainers/bioconductor-mast:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, MAST, data.table, ggplot2, limma
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Bootstrap the variance-covariance matrix of the fit using bootVcov1. 2. Load gene sets from a GMT file using getGmt and map to ind

nextflow.enable.dsl = 2

process BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(MAST)
        library(GSEABase)
        library(limma)
        library(data.table)
        library(ggplot2)
        
        # -----------------------------------------------------------------------------
        # 1. Load User Inputs
        # -----------------------------------------------------------------------------
        if (!file.exists("fitted_zlm_model.rds")) {
            stop("Error: 'fitted_zlm_model.rds' not found in the working directory.")
        }
        if (!file.exists("gene_sets.gmt")) {
            stop("Error: 'gene_sets.gmt' not found in the working directory.")
        }
        
        # Read the fitted Hurdle model
        zlmCond <- readRDS("fitted_zlm_model.rds")
        
        # Identify the target coefficient for hypothesis testing
        coef_names <- colnames(zlmCond@coefC)
        target_coef <- "conditionStim"
        if (!"conditionStim" %in% coef_names) {
            non_intercept_idx <- which(coef_names != "(Intercept)")
            if (length(non_intercept_idx) > 0) {
                target_coef <- coef_names[non_intercept_idx[1]]
            } else {
                stop("Error: The fitted model does not contain any valid non-intercept coefficients.")
            }
        }
        
        # Extract gene names from the fitted model
        gene_names <- colnames(zlmCond)
        if (is.null(gene_names)) {
            gene_names <- rownames(coef(zlmCond, "C"))
        }
        
        # Define parameters for the documented code
        module_file <- "gene_sets.gmt"
        min_gene_in_module <- 5
        
        # -----------------------------------------------------------------------------
        # 2. Documented Code Execution
        # -----------------------------------------------------------------------------
        boots <- bootVcov1(zlmCond, R = 4)
        gene_set <- getGmt(module_file)
        gene_ids <- geneIds(gene_set)
        sets_indices <- limma::ids2indices(gene_ids, gene_names)
        sets_indices <- sets_indices[sapply(sets_indices, length) >= min_gene_in_module]
        gsea <- gseaAfterBoot(zlmCond, boots, sets_indices, CoefficientHypothesis(target_coef))
        z_stat_comb <- summary(gsea, testType='normal')
        
        # -----------------------------------------------------------------------------
        # 3. Save Outputs and Generate Plots
        # -----------------------------------------------------------------------------
        # Save the GSEA summary table
        fwrite(z_stat_comb, "gsea_results.csv")
        
        # Save the raw GSEA object
        saveRDS(gsea, "gsea_object.rds")
        
        # Generate and save the GSEA visualization plot
        tryCatch({
            p_col <- if ("combined_adj" %in% colnames(z_stat_comb)) "combined_adj" else "combined_P"
            sigModules <- z_stat_comb[get(p_col) < 0.05]
            if (nrow(sigModules) == 0) {
                # Fallback to top 15 modules by p-value if none are significant at 0.05
                sigModules <- z_stat_comb[order(combined_P)][1:min(15, nrow(z_stat_comb))]
            }
            
            if (nrow(sigModules) > 0) {
                gseaTable <- melt(sigModules[, .(set, disc_Z, cont_Z, combined_Z)], id.vars = 'set')
                p <- ggplot(gseaTable, aes(y = set, x = variable, fill = value)) +
                    geom_raster() +
                    scale_fill_distiller(palette = "PiYG") +
                    theme_minimal() +
                    labs(
                        title = "Gene Set Enrichment Analysis (GSEA)",
                        subtitle = "Top modules based on Hurdle model bootstrapping",
                        x = "Component / Statistic",
                        y = "Gene Set",
                        fill = "Z-score"
                    ) +
                    theme(axis.text.y = element_text(size = 8))
                
                ggsave("gsea_plot.pdf", plot = p, width = 8, height = 6)
            } else {
                warning("No modules available to plot.")
            }
        }, error = function(e) {
            warning("Plotting failed: ", e\$message)
        })
        
        message("Pipeline completed successfully. Outputs saved to 'gsea_results.csv', 'gsea_object.rds', and 'gsea_plot.pdf'.")

    writeLines(c(
        '"BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS":',
        paste0('    MAST: ', as.character(packageVersion('MAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_set_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fitted_zlm_model.rds, gene_sets.gmt ] ]

    main:
    BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_MAST_GENE_SET_ENRICHMENT_ANALYSIS.out.versions
}
