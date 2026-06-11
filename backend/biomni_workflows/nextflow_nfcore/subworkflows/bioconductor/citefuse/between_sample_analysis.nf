#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CiteFuse — between_sample_analysis
// Compare gene/protein expression and perform differential expression across different samples or conditions.
// Input: sce_control.rds, sce_disease.rds
// Container: quay.io/biocontainers/bioconductor-citefuse:1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CiteFuse, SingleCellExperiment, ggplot2, scater
// Visualizations: box plot
// QC: missing-value handling, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compare expression across samples using visualiseExprsList()
//  * 2. [Core Analysis] Perform cross-sample differential expression using DEgenesCross()
//  * 3. [Core Analysis] Select significant cross-sample DE genes using selectDEgenes()

nextflow.enable.dsl = 2

process BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS {
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
        library(CiteFuse)
        library(scater)
        library(ggplot2)
        
        # 1. Load User Input Files
        if (!file.exists("sce_control.rds") || !file.exists("sce_disease.rds")) {
          stop("Error: Required input files 'sce_control.rds' and/or 'sce_disease.rds' not found in the working directory.")
        }
        
        sce_citeseq <- readRDS("sce_control.rds")
        sce_ctcl_subset <- readRDS("sce_disease.rds")
        
        # Dynamically determine features to plot
        rna_features <- head(intersect(rownames(sce_citeseq), rownames(sce_ctcl_subset)), 2)
        adt_features <- head(intersect(rownames(altExp(sce_citeseq, "ADT")), rownames(altExp(sce_ctcl_subset, "ADT"))), 2)
        
        # Dynamically determine grouping columns (using the last column in colData as the default clustering)
        group_col_c <- tail(colnames(colData(sce_citeseq)), 1)
        group_col_d <- tail(colnames(colData(sce_ctcl_subset)), 1)
        
        # Dynamically determine groups to test
        group_c <- as.character(na.omit(unique(colData(sce_citeseq)[[group_col_c]])))[1]
        group_d <- as.character(na.omit(unique(colData(sce_ctcl_subset)[[group_col_d]])))[1]
        
        # 2. Compare expression across samples using visualiseExprsList()
        # RNA expression comparison
        p_rna <- visualiseExprsList(
          sce_list = list(control = sce_citeseq, ctcl = sce_ctcl_subset), 
          plot = "boxplot", 
          altExp_name = "none", 
          exprs_value = "logcounts", 
          feature_subset = rna_features, 
          group_by = c(group_col_c, group_col_d)
        )
        
        # ADT expression comparison
        p_adt <- visualiseExprsList(
          sce_list = list(control = sce_citeseq, ctcl = sce_ctcl_subset), 
          plot = "boxplot", 
          altExp_name = "ADT", 
          feature_subset = adt_features, 
          group_by = c(group_col_c, group_col_d)
        )
        
        # Save the visualization plots to a PDF file
        pdf("between_sample_expression_boxplots.pdf", width = 10, height = 8)
        if (!is.null(p_rna)) print(p_rna)
        if (!is.null(p_adt)) print(p_adt)
        dev.off()
        
        # 3. Perform cross-sample differential expression using DEgenesCross()
        de_res <- DEgenesCross(
          sce_list = list(control = sce_citeseq, ctcl = sce_ctcl_subset), 
          colData_name = c(group_col_c, group_col_d), 
          group_to_test = c(group_c, group_d)
        )
        
        # Save raw DE results
        saveRDS(de_res, "de_res_raw.rds")
        
        # 4. Select significant cross-sample DE genes using selectDEgenes()
        de_res_filter <- selectDEgenes(de_res = de_res)
        
        # Save filtered DE results as RDS
        saveRDS(de_res_filter, "de_res_filtered.rds")
        
        # Export filtered DE results to CSV tables
        if (is.list(de_res_filter)) {
          for (sample_name in names(de_res_filter)) {
            df <- de_res_filter[[sample_name]]
            if (!is.null(df) && nrow(df) > 0) {
              write.csv(df, file = paste0("de_res_filter_", sample_name, ".csv"), row.names = TRUE)
            }
          }
        }
        
        message("Pipeline completed successfully. Outputs saved to 'between_sample_expression_boxplots.pdf', 'de_res_raw.rds', 'de_res_filtered.rds', and corresponding CSV files.")

    writeLines(c(
        '"BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS":',
        paste0('    CiteFuse: ', as.character(packageVersion('CiteFuse')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_between_sample_analysis.csv versions.yml
    """
}

workflow BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_control.rds, sce_disease.rds ] ]

    main:
    BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.tables
    plots    = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.plots
    objects  = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.objects
    versions = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.versions
}
