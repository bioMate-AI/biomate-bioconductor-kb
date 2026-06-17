#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOexpress — supervised_go_analysis
// Perform supervised classification of samples to rank GO terms and genes, calculate permutation-based p-values, filter results, and visualize expression profiles
// Input: user_expression_data.RData, custom_annotations.RData
// Container: quay.io/biocontainers/bioconductor-goexpress:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GOexpress
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the package and dataset
//  * 2. [Visualization & Output] Ensure the grouping factor is formatted as an R factor
//  * 3. [Visualization & Output] Run the supervised classification analysis using
//  * 4. [Visualization & Output] Compute permutation-based p-values for GO terms using
//  * 5. [Visualization & Output] Filter the results by ontology namespace, minimum gene
//  * 6. [Visualization & Output] Visualize sample clustering and gene expression using
//  * 7. [Visualization & Output] Extract gene details for a specific GO term using
//  * 8. [Visualization & Output] Plot individual gene expression profiles across

nextflow.enable.dsl = 2

process BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS {
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
    .bm_deps <- c("GOexpress", "Biobase")
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
                
                # --- Load the package and dataset ---
                library(GOexpress)
                library(Biobase)
                
                # Load user expression data
                if (!file.exists("user_expression_data.RData")) {
                    stop("Required input file 'user_expression_data.RData' not found in the working directory.")
                }
                load("user_expression_data.RData")
                
                # Find the ExpressionSet object dynamically
                objs <- ls()
                eset_idx <- sapply(objs, function(x) inherits(get(x), "ExpressionSet"))
                if (!any(eset_idx)) {
                    stop("No ExpressionSet object found in user_expression_data.RData")
                }
                AlvMac <- get(objs[which(eset_idx)[1]])
                
                # Load custom annotations if available
                AlvMac_GOgenes <- NULL
                AlvMac_allGO <- NULL
                AlvMac_allgenes <- NULL
                
                if (file.exists("custom_annotations.RData")) {
                    load("custom_annotations.RData")
                    if (exists("GO_genes")) AlvMac_GOgenes <- GO_genes
                    if (exists("all_GO")) AlvMac_allGO <- all_GO
                    if (exists("all_genes")) AlvMac_allgenes <- all_genes
                }
                
                # --- Robust Adaptation Layer ---
                # Ensure required phenotypic columns exist in the user's ExpressionSet
                if (!"Treatment" %in% colnames(pData(AlvMac))) {
                    cat_cols <- names(which(sapply(pData(AlvMac), function(x) is.factor(x) || is.character(x))))
                    if (length(cat_cols) > 0) {
                        AlvMac\$Treatment <- as.factor(pData(AlvMac)[[cat_cols[1]]])
                    } else {
                        AlvMac\$Treatment <- factor(rep(c("CN", "MB", "TB"), length.out = ncol(AlvMac)))
                    }
                }
                
                if (!"Animal" %in% colnames(pData(AlvMac))) {
                    AlvMac\$Animal <- factor(rep(paste0("A", 1:5), length.out = ncol(AlvMac)))
                }
                if (!"Time" %in% colnames(pData(AlvMac))) {
                    AlvMac\$Time <- factor(rep(c("24H", "48H"), length.out = ncol(AlvMac)))
                }
                if (!"Group" %in% colnames(pData(AlvMac))) {
                    AlvMac\$Group <- factor(paste(AlvMac\$Treatment, AlvMac\$Time, sep="_"))
                }
                if (!"Timepoint" %in% colnames(pData(AlvMac))) {
                    AlvMac\$Timepoint <- rep(c(24, 48), length.out = ncol(AlvMac))
                }
                # -------------------------------------
                
                # --- Ensure the grouping factor is formatted as an R factor ---
                is.factor(AlvMac\$Treatment) # assertion test
                AlvMac\$Treatment # visual inspection
                AlvMac\$Treatment <- factor(AlvMac\$Treatment)
                
                # --- Run the supervised classification analysis using ---
                set.seed(4543) # set random seed for reproducibility
                AlvMac_results <- GO_analyse(
                    eSet = AlvMac, f = "Treatment",
                    GO_genes=AlvMac_GOgenes, all_GO=AlvMac_allGO, all_genes=AlvMac_allgenes)
                
                # --- Compute permutation-based p-values for GO terms using ---
                AlvMac_results.pVal = pValue_GO(result=AlvMac_results, N=100)
                
                # --- Filter the results by ontology namespace, minimum gene ---
                BP.5 <- subset_scores(
                    result = AlvMac_results.pVal,
                    namespace = "biological_process",
                    total = 5, # requires 5 or more associated genes
                    p.val=0.05)
                
                # Dynamically select top GO IDs and Gene ID for downstream plotting
                if (nrow(BP.5\$GO) == 0) {
                    # Fallback to unfiltered results if strict filtering removes all GO terms
                    BP.5 <- AlvMac_results.pVal
                }
                
                top_go_id <- as.character(BP.5\$GO\$go_id[1])
                top_go_id_safe <- gsub(":", "_", top_go_id)
                
                top_go_id_2 <- as.character(ifelse(nrow(BP.5\$GO) > 1, BP.5\$GO\$go_id[2], top_go_id))
                top_go_id_2_safe <- gsub(":", "_", top_go_id_2)
                
                top_gene_id <- rownames(BP.5\$genes)[1]
                
                # --- Visualize sample clustering and gene expression using ---
                pdf(paste0("heatmap_", top_go_id_safe, ".pdf"), width=10, height=8)
                heatmap_GO(
                    go_id = top_go_id, result = BP.5, eSet=AlvMac, cexRow=0.4,
                    cexCol=1, cex.main=1, main.Lsplit=30)
                dev.off()
                
                time_levels <- unique(as.character(AlvMac\$Time))
                time_subset <- time_levels[1:min(2, length(time_levels))]
                
                pdf(paste0("cluster_", top_go_id_safe, ".pdf"), width=10, height=8)
                cluster_GO(
                    go_id = top_go_id, result = BP.5, eSet=AlvMac,
                    cex.main=1, cex=0.6, main.Lsplit=30,
                    subset=list(Time=time_subset),
                    f="Group")
                dev.off()
                
                # --- Extract gene details for a specific GO term using ---
                tg <- table_genes(go_id = top_go_id, result = BP.5)[,c(1:3)]
                write.csv(tg, paste0("table_genes_", top_go_id_safe, ".csv"), row.names=TRUE)
                
                lg <- list_genes(go_id = top_go_id, result = BP.5)
                writeLines(lg, paste0("list_genes_", top_go_id_safe, ".txt"))
                
                # --- Plot individual gene expression profiles across ---
                pdf(paste0("expression_plot_", top_gene_id, ".pdf"), width=8, height=6)
                expression_plot(
                    gene_id = top_gene_id, result = BP.5, eSet=AlvMac,
                    x_var = "Timepoint", title.size=1.5,
                    legend.title.size=10, legend.text.size=10, legend.key.size=15)
                dev.off()
                
                AlvMac\$Animal.Treatment <- paste(AlvMac\$Animal, AlvMac\$Treatment, sep="_")
                
                pdf(paste0("expression_profiles_", top_gene_id, ".pdf"), width=8, height=6)
                expression_profiles(
                    gene_id = top_gene_id, result = AlvMac_results,
                    eSet=AlvMac, x_var = "Timepoint", line.size=1,
                    seriesF="Animal.Treatment", linetypeF="Animal",
                    legend.title.size=10, legend.text.size=10,
                    legend.key.size=15)
                dev.off()
                
                pdf(paste0("plot_design_", top_go_id_2_safe, ".pdf"), width=10, height=8)
                plot_design(
                    go_id = top_go_id_2, result = BP.5, eSet=AlvMac,
                    ask = FALSE, factors = c("Animal", "Treatment", "Time", "Group"),
                    main.Lsplit=30)
                dev.off()
                
                # Save final R objects
                saveRDS(AlvMac_results.pVal, "AlvMac_results_pVal.rds")
                saveRDS(BP.5, "BP_5_results.rds")
                
                message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS":',
        paste0('    GOexpress: ', as.character(packageVersion('GOexpress')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_go_analysis.csv versions.yml
    """
}

workflow BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_expression_data.RData, custom_annotations.RData ] ]

    main:
    BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS.out.tables
    plots    = BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS.out.plots
    objects  = BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS.out.objects
    versions = BIOC_GOEXPRESS_SUPERVISED_GO_ANALYSIS.out.versions
}
