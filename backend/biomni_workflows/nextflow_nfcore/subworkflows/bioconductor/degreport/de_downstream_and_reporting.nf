#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEGreport — de_downstream_and_reporting
// Extract contrasts, identify significant genes, visualize differential expression results (MA, Volcano, Gene plots), and generate reports.
// Input: dds_object.rds, res_object.rds
// Container: quay.io/biocontainers/bioconductor-degreport:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEGreport, DESeq2, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Inputs
//  * 2. [Visualization & Output] Extract multiple contrasts using degComps
//  * 3. [Visualization & Output] Retrieve results tables using deg
//  * 4. [Visualization & Output] Identify significant genes using significants
//  * 5. [Visualization & Output] Plotting and saving visualizations
//  * 6. [Visualization & Output] Generate a full report using degResults

nextflow.enable.dsl = 2

process BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING {
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
    .bm_deps <- c("DEGreport", "DESeq2", "ggplot2", "SummarizedExperiment")
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
    library(DEGreport)
    library(SummarizedExperiment)
    library(DESeq2)
    library(ggplot2)
    
    # --- Load User Inputs ---
    if (!file.exists("dds_object.rds") || !file.exists("res_object.rds")) {
      stop("Error: 'dds_object.rds' and/or 'res_object.rds' must exist in the working directory.")
    }
    
    dds <- readRDS("dds_object.rds")
    res <- readRDS("res_object.rds")
    
    # Dynamically determine the main covariate from the DESeqDataSet design
    group_var <- rev(all.vars(design(dds)))[1]
    group_levels <- levels(factor(colData(dds)[[group_var]]))
    if (length(group_levels) < 2) {
      group_levels <- unique(as.character(colData(dds)[[group_var]]))
    }
    contrast_to_use <- c(group_var, group_levels[1], group_levels[2])
    
    # --- Extract multiple contrasts using degComps ---
    message("Extracting contrasts...")
    degs <- degComps(dds, combs = group_var,
                     contrast = list(contrast_to_use))
    saveRDS(degs, "degs_output.rds")
    
    # Print names of contrasts
    print(names(degs))
    
    # --- Retrieve results tables using deg ---
    message("Retrieving results tables...")
    deg_default <- deg(degs[[1]])
    deg_raw_tibble <- deg(degs[[1]], "raw", "tibble")
    
    # Save retrieved tables
    write.csv(as.data.frame(deg_default), "deg_default_results.csv", row.names = TRUE)
    write.csv(as.data.frame(deg_raw_tibble), "deg_raw_tibble_results.csv", row.names = FALSE)
    
    # --- Identify significant genes using significants ---
    message("Identifying significant genes...")
    sig_single <- significants(degs[[1]], fc = 0, fdr = 0.05)
    sig_list <- significants(degs, fc = 0, fdr = 0.05)
    sig_list_full <- significants(degs, fc = 0, fdr = 0.05, full = TRUE)
    
    # Save significant gene lists
    write.csv(data.frame(gene = sig_single), "significant_genes_single.csv", row.names = FALSE)
    write.csv(data.frame(gene = sig_list), "significant_genes_list.csv", row.names = FALSE)
    write.csv(as.data.frame(sig_list_full), "significant_genes_full.csv", row.names = FALSE)
    
    # --- Plotting and saving visualizations ---
    message("Generating plots...")
    pdf("deg_report_plots.pdf", width = 10, height = 8)
    
    # MA plots
    p1 <- degMA(degs[[1]], diff = 2, limit = 3)
    print(p1)
    
    p2 <- degMA(degs[[1]], diff = 2, limit = 3, raw = TRUE)
    print(p2)
    
    p3 <- degMA(degs[[1]], limit = 3, correlation = TRUE)
    print(p3)
    
    # Volcano plot
    res[["id"]] <- row.names(res)
    show <- as.data.frame(res[1:10, c("log2FoldChange", "padj", "id")])
    p4 <- degVolcano(res[,c("log2FoldChange", "padj")], plot_text = show)
    print(p4)
    
    # Gene plots
    p5 <- degPlot(dds = dds, res = res, n = 6, xs = group_var)
    print(p5)
    
    # Wide gene plot
    p6 <- degPlotWide(dds, rownames(dds)[1:5], group = group_var)
    print(p6)
    
    dev.off()
    
    # --- Generate a full report using degResults ---
    message("Generating full report...")
    resreport <- degResults(dds = dds, name = "test", org = NULL,
                            do_go = FALSE, group = group_var, xs = group_var,
                            path_results = NULL)
    
    saveRDS(resreport, "resreport_output.rds")
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING":',
        paste0('    DEGreport: ', as.character(packageVersion('DEGreport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_downstream_and_reporting.csv versions.yml
    """
}

workflow BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds_object.rds, res_object.rds ] ]

    main:
    BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING(ch_input)

    emit:
    tables   = BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING.out.tables
    plots    = BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING.out.plots
    objects  = BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING.out.objects
    versions = BIOC_DEGREPORT_DE_DOWNSTREAM_AND_REPORTING.out.versions
}
