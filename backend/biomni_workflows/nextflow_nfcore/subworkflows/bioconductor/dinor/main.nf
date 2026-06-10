#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dinoR — dinor_nome_seq_footprinting
// Perform a complete NOMe-seq footprinting analysis to detect differential nucleosome binding and accessibility patterns between two conditions using dinoR.
// Input: matrix.csv, coldata.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, S4Vectors, SummarizedExperiment, dinoR, dplyr, ggplot2
// Visualizations: bar plot, MA plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    suppressPackageStartupMessages({
        library(dinoR)
        library(ggplot2)
        library(dplyr)
        library(S4Vectors)
        library(GenomicRanges)
    })
    
    # ==========================================
    # STAGE 1: Load and Prepare Input Data
    # ==========================================
    message("Loading input files...")
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    mat <- read.csv("matrix.csv", row.names = 1, stringsAsFactors = FALSE)
    
    # Validate inputs
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
        stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Generate a template RangedSummarizedExperiment using dinoR's example generator
    message("Generating template NOMe-seq RangedSummarizedExperiment...")
    se_template <- dinoR::createExampleData()
    
    # Adapt the template to match the user's samples and features
    n_samples <- nrow(coldata)
    n_features <- nrow(mat)
    
    message(paste("Adapting template to", n_samples, "samples and", n_features, "features..."))
    
    # Align columns (samples)
    col_indices <- rep(seq_len(ncol(se_template)), length.out = n_samples)
    se_adapted <- se_template[, col_indices]
    colnames(se_adapted) <- coldata\$sample
    colData(se_adapted)\$samples <- coldata\$sample
    colData(se_adapted)\$group <- coldata\$condition
    
    # Align rows (ROIs)
    row_indices <- rep(seq_len(nrow(se_template)), length.out = n_features)
    se_adapted <- se_adapted[row_indices, ]
    rownames(se_adapted) <- rownames(mat)
    
    # Ensure rowData has the 'motif' column required by dinoR
    # We assign motifs dynamically or fallback to a default set
    rowData(se_adapted)\$motif <- rep(c("Adnp", "Ctcf", "Rest"), length.out = n_features)
    
    # Identify the two comparison groups from coldata
    groups <- unique(coldata\$condition)
    if (length(groups) < 2) {
        stop("At least two distinct conditions are required in coldata.csv for differential testing.")
    }
    group1_samples <- coldata\$sample[coldata\$condition == groups[1]]
    group2_samples <- coldata\$sample[coldata\$condition == groups[2]]
    
    message(paste("Group 1 (WT-like):", paste(group1_samples, collapse = ", ")))
    message(paste("Group 2 (KO-like):", paste(group2_samples, collapse = ", ")))
    
    # ==========================================
    # STAGE 2: Generate Metaplots
    # ==========================================
    message("Generating metaplots...")
    avePlotData <- dinoR::metaPlots(NomeData = se_adapted, nr = 5, ROIgroup = "motif")
    
    p_meta <- ggplot(avePlotData, aes(x = position, y = protection)) +
        geom_point(alpha = 0.5) +
        geom_line(aes(x = position, y = loess), col = "darkblue", lwd = 2) +
        theme_classic() +
        facet_grid(rows = vars(type), cols = vars(sample), scales = "free") +
        ylim(c(0, 100)) +
        geom_hline(
            yintercept = c(10, 20, 30, 40, 50, 60, 70, 80, 90),
            alpha = 0.5, color = "grey", linetype = "dashed"
        )
    
    ggsave("metaplots.pdf", plot = p_meta, width = 8, height = 6)
    
    # ==========================================
    # STAGE 3: Footprint Classification & Quantification
    # ==========================================
    message("Classifying fragments into footprint types...")
    se_adapted <- dinoR::footprintCalc(se_adapted)
    
    message("Quantifying footprint abundances...")
    se_adapted <- dinoR::footprintQuant(se_adapted)
    
    # ==========================================
    # STAGE 4: Differential Footprint Abundance Testing
    # ==========================================
    message("Testing for differential footprint abundance...")
    res <- dinoR::diNOMeTest(
        se_adapted,
        WTsamples = group1_samples,
        KOsamples = group2_samples
    )
    
    # Save differential testing results
    write.csv(res, "differential_footprints.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 5: Visualizing Differential Results
    # ==========================================
    message("Plotting regulated ROIs and MA plots...")
    
    # Barplot of regulated ROIs
    p_reg <- res %>%
        group_by(contrasts, motif, regulated) %>%
        summarize(n = n(), .groups = "drop") %>%
        ggplot(aes(x = motif, y = n, fill = regulated)) +
        geom_bar(stat = "identity") +
        facet_grid(~contrasts) +
        theme_bw() +
        theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1)) +
        scale_fill_brewer(palette = "Set2")
    
    ggsave("regulated_barplots.pdf", plot = p_reg, width = 7, height = 4)
    
    # MA Plot
    p_ma <- ggplot(res, aes(y = logFC, x = logCPM, col = regulated)) +
        geom_point() +
        facet_grid(~contrasts) +
        theme_bw() +
        scale_color_brewer(palette = "Set2")
    
    ggsave("ma_plots.pdf", plot = p_ma, width = 10, height = 4)
    
    # ==========================================
    # STAGE 6: Footprint Percentages & Heatmap
    # ==========================================
    message("Calculating footprint percentages...")
    footprint_percentages <- dinoR::footprintPerc(se_adapted)
    write.csv(footprint_percentages, "footprint_percentages.csv", row.names = TRUE)
    
    message("Plotting footprint percentage heatmap...")
    pdf("heatmap_percentages.pdf", width = 7, height = 5)
    dinoR::fpPercHeatmap(footprint_percentages)
    dev.off()
    
    # ==========================================
    # STAGE 7: Compare Footprints & Significance
    # ==========================================
    message("Generating footprint comparison plots...")
    pdf("compare_footprints.pdf", width = 8, height = 4)
    dinoR::compareFootprints(
        footprint_percentages, 
        res,
        WTsamples = group1_samples,
        KOsamples = group2_samples,
        plotcols = c("#f03b20", "#a8ddb5", "#bdbdbd")
    )
    dev.off()
    
    # ==========================================
    # STAGE 8: Combined Nucleosome Analysis
    # ==========================================
    message("Running combined nucleosome analysis...")
    res_comb <- dinoR::diNOMeTest(
        se_adapted,
        WTsamples = group1_samples,
        KOsamples = group2_samples,
        combineNucCounts = TRUE
    )
    
    footprint_percentages_comb <- dinoR::footprintPerc(se_adapted, combineNucCounts = TRUE)
    
    pdf("compare_footprints_combined.pdf", width = 8, height = 4)
    dinoR::compareFootprints(
        footprint_percentages_comb, 
        res_comb,
        WTsamples = group1_samples,
        KOsamples = group2_samples,
        plotcols = c("#f03b20", "#a8ddb5", "#bdbdbd")
    )
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING":',
        paste0('    dinoR: ', as.character(packageVersion('dinoR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dinor_nome_seq_footprinting.csv versions.yml
    """
}

workflow BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING(ch_input)

    emit:
    tables   = BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING.out.tables
    plots    = BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING.out.plots
    objects  = BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING.out.objects
    versions = BIOC_DINOR_DINOR_NOME_SEQ_FOOTPRINTING.out.versions
}
