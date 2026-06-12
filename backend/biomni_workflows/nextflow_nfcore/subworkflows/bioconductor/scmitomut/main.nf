#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMitoMut — sc_mitochondrial_mutation_calling
// Identify, filter, visualize, and export lineage-informative mitochondrial mutations from single-cell allele count data.
// Input: mini_dataset.tsv.gz, mini_dataset_cell_ann.csv
// Container: quay.io/biocontainers/bioconductor-scmitomut:1.6.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, ggplot2, rhdf5, scMitoMut
// Visualizations: heatmap
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse the allele count table into an H5 database file using parse_table
//  * 2. [Core Analysis] Open the H5 file as a mtmutObj using open_h5_file
//  * 3. [Core Analysis] Subset cells to keep only high-quality annotated cells using subset_cell
//  * 4. [Core Analysis] Fit the beta-binomial model to calculate mutation p-values using run_model_fit
//  * 5. [Core Analysis] Filter mutations based on cell count and FDR thresholds using filter_loc
//  * 6. [Visualization & Output] Visualize mutations using plot_heatmap
//  * 7. [Visualization & Output] Export mutation data using export_df, export_af, export_pval, or export_binary

nextflow.enable.dsl = 2

process BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING {
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
    .bm_deps <- c("scMitoMut", "data.table", "ggplot2", "rhdf5")
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
    library(scMitoMut)
    library(data.table)
    library(ggplot2)
    library(rhdf5)
    
    # Define input file paths (must be exactly these in the working directory)
    input_tsv <- "mini_dataset.tsv.gz"
    input_ann <- "mini_dataset_cell_ann.csv"
    
    # Check if input files exist
    if (!file.exists(input_tsv)) {
      stop(paste("Required input file missing:", input_tsv))
    }
    if (!file.exists(input_ann)) {
      stop(paste("Required input file missing:", input_ann))
    }
    
    # 1. Parse the allele count table into an H5 database file
    f_h5_tmp <- tempfile(fileext = ".h5")
    f_h5 <- parse_table(input_tsv, h5_file = f_h5_tmp)
    
    # 2. Open the H5 file as a mtmutObj
    x <- open_h5_file(f_h5)
    str(x)
    
    # Show what's in the h5 file
    h5ls(x\$h5f, recursive = FALSE)
    
    # 3. Subset cells to keep only high-quality annotated cells
    cell_ann <- read.csv(input_ann, row.names = 1)
    x <- subset_cell(x, rownames(cell_ann))
    head(x\$cell_selected)
    
    # 4. Fit the beta-binomial model to calculate mutation p-values
    run_model_fit(x, mc.cores = 1)
    
    # Show what's in the h5 file after model fitting
    h5ls(x\$h5f, recursive = FALSE)
    
    # 5. Filter mutations based on cell count and FDR thresholds
    x <- filter_loc(
      mtmutObj = x,
      min_cell = 2,
      model = "bb",
      p_threshold = 0.01,
      p_adj_method = "fdr"
    )
    x\$loc_pass
    
    # 6. Visualize mutations using plot_heatmap
    # Prepare the color for cell annotation dynamically
    ann_col <- colnames(cell_ann)[1]
    unique_cell_types <- na.omit(unique(cell_ann[[ann_col]]))
    colors <- rainbow(length(unique_cell_types))
    names(colors) <- unique_cell_types
    ann_colors <- list()
    ann_colors[[ann_col]] <- colors
    
    # Save heatmaps to a PDF file
    pdf("mutation_heatmaps.pdf", width = 12, height = 8)
    
    # binary heatmap with interpolation
    plot_heatmap(x,
      cell_ann = cell_ann, ann_colors = ann_colors, type = "binary",
      percent_interp = 0.2, n_interp = 3
    )
    
    # binary heatmap without interpolation
    plot_heatmap(x,
      cell_ann = cell_ann, ann_colors = ann_colors, type = "binary",
      percent_interp = 1, n_interp = 3
    )
    
    # p value heatmap
    plot_heatmap(x,
      cell_ann = cell_ann, ann_colors = ann_colors, type = "p",
      percent_interp = 0.2, n_interp = 3
    )
    
    # allele frequency heatmap
    plot_heatmap(x,
      cell_ann = cell_ann, ann_colors = ann_colors, type = "af",
      percent_interp = 0.2, n_interp = 3
    )
    
    dev.off()
    
    # 7. Export mutation data
    m_df <- export_df(x)
    write.csv(m_df, "mutation_df.csv", row.names = FALSE)
    
    af_matrix <- export_af(x)
    write.csv(af_matrix, "allele_frequency_matrix.csv")
    
    pval_matrix <- export_pval(x)
    write.csv(pval_matrix, "p_value_matrix.csv")
    
    binary_matrix <- export_binary(x)
    write.csv(binary_matrix, "binary_mutation_matrix.csv")
    
    # 8. Show the p value, af plot versus cell types
    m_dt <- data.table(m_df)
    m_dt[, cell_type := cell_ann[as.character(m_dt\$cell_barcode), ann_col]]
    
    # Select a locus dynamically for diagnostic plots
    target_loc <- x\$loc_pass[1]
    if (length(target_loc) == 0 || is.na(target_loc)) {
      target_loc <- m_dt\$loc[1]
    }
    m_dt_sub <- m_dt[loc == target_loc]
    
    # Save diagnostic plots to a PDF file
    pdf("mutation_plots.pdf", width = 7, height = 6)
    
    # The p value versus cell types
    p1 <- ggplot(m_dt_sub) +
      aes(x = cell_type, y = -log10(pval), color = cell_type) +
      geom_jitter() +
      scale_color_manual(values = colors) +
      theme_bw() +
      geom_hline(yintercept = -log10(0.01), linetype = "dashed") +
      ylab("-log10(FDR)")
    print(p1)
    
    # The allele frequency versus cell types
    p2 <- ggplot(m_dt_sub) +
      aes(x = cell_type, y = 1 - af, color = factor(cell_type)) +
      geom_jitter() +
      scale_color_manual(values = colors) +
      theme_bw() +
      geom_hline(yintercept = 0.05, linetype = "dashed") +
      ylab("1 - Dominant Allele Frequency")
    print(p2)
    
    # The p value versus allele frequency
    p3 <- ggplot(m_dt_sub) +
      aes(x = -log10(pval), y = 1 - af, color = factor(cell_type)) +
      geom_point() +
      scale_color_manual(values = colors) +
      theme_bw() +
      geom_hline(yintercept = 0.05, linetype = "dashed") +
      geom_vline(xintercept = -log10(0.01), linetype = "dashed") +
      xlab("-log10(FDR)") +
      ylab("1 - Dominant Allele Frequency")
    print(p3)
    
    dev.off()
    
    # Clean up resources
    rm_mtmutObj(x)
    unlink(f_h5_tmp)

    writeLines(c(
        '"BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING":',
        paste0('    scMitoMut: ', as.character(packageVersion('scMitoMut')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_mitochondrial_mutation_calling.csv versions.yml
    """
}

workflow BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mini_dataset.tsv.gz, mini_dataset_cell_ann.csv ] ]

    main:
    BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING(ch_input)

    emit:
    tables   = BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING.out.tables
    plots    = BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING.out.plots
    objects  = BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING.out.objects
    versions = BIOC_SCMITOMUT_SC_MITOCHONDRIAL_MUTATION_CALLING.out.versions
}
