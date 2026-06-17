#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiContacts — matrix_arithmetics_and_visualization
// Import Hi-C matrices, perform arithmetic operations (detrending, autocorrelating, merging, dividing, despeckling), and visualize them with loops and borders.
// Input: cool_file.cool, mcool_file.mcool, S288C-loops.bedpe, S288C-borders.bed
// Container: quay.io/biocontainers/bioconductor-hicontacts:1.12.0--r45hdfd78af_0
// R packages: BiocParallel, dplyr, GenomicRanges, ggplot2, HiCExperiment, HiContacts, HiContactsData, InteractionSet, patchwork, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, HiCExperiment, HiContacts, InteractionSet, dplyr, ggplot2, patchwork, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import Hi-C matrix as a HiCExperiment object
//  * 2. [Visualization & Output] Plot square or horizontal matrices, optionally overlaying
//  * 3. [Visualization & Output] Aggregate matrices over features (e.g., loops)
//  * 4. [Visualization & Output] Compute autocorrelated contact maps
//  * 5. [Visualization & Output] Detrend contact maps (scores over expected)
//  * 6. [Visualization & Output] Merge (sum) two contact maps
//  * 7. [Visualization & Output] Divide (compute ratio) between two contact maps
//  * 8. [Visualization & Output] Despeckle (smooth) contact maps

nextflow.enable.dsl = 2

process BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "dplyr", "GenomicRanges", "ggplot2", "HiCExperiment", "HiContacts", "HiContactsData", "InteractionSet", "patchwork", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(dplyr)
    library(ggplot2)
    library(HiCExperiment)
    library(HiContacts)
    library(rtracklayer)
    library(InteractionSet)
    library(BiocParallel)
    library(patchwork)
    
    # Define input files from the working directory
    cool_file_path <- "cool_file.cool"
    mcool_file_path <- "mcool_file.mcool"
    loops_file_path <- "S288C-loops.bedpe"
    borders_file_path <- "S288C-borders.bed"
    
    # ==========================================
    # --- Import Hi-C matrix as a HiCExperiment object ---
    # ==========================================
    hic <- import(cool_file_path, format = 'cool')
    
    # Save basic info
    sink("hic_experiment_summary.txt")
    print(hic)
    sink()
    
    # ==========================================
    # --- Plot square or horizontal matrices, optionally overlaying ---
    # ==========================================
    # Square matrix plot
    p1 <- plotMatrix(hic, use.scores = 'balanced', limits = c(-4, -1))
    ggsave("plot1_square_matrix.pdf", plot = p1, width = 7, height = 6)
    
    # Horizontal matrix plot (refocused)
    # Attempt to refocus on 'II' as in the vignette, with fallback to the first available chromosome
    p2 <- tryCatch({
        plotMatrix(
            refocus(hic, 'II'),
            use.scores = 'balanced', limits = c(-4, -1), 
            maxDistance = 200000
        )
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        plotMatrix(
            refocus(hic, first_chrom),
            use.scores = 'balanced', limits = c(-4, -1), 
            maxDistance = 200000
        )
    })
    ggsave("plot2_horizontal_matrix.pdf", plot = p2, width = 8, height = 4)
    
    # Import loops and borders
    loops <- import(loops_file_path) |> 
        makeGInteractionsFromGRangesPairs()
    
    borders <- import(borders_file_path)
    
    # Plot matrix with loops
    p3 <- tryCatch({
        import(mcool_file_path, format = 'mcool', focus = 'IV') |> 
            plotMatrix(loops = loops, limits = c(-4, -1), dpi = 120)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        import(mcool_file_path, format = 'mcool', focus = first_chrom) |> 
            plotMatrix(loops = loops, limits = c(-4, -1), dpi = 120)
    })
    ggsave("plot3_matrix_loops.pdf", plot = p3, width = 7, height = 6)
    
    # Plot matrix with loops and borders
    p4 <- tryCatch({
        import(mcool_file_path, format = 'mcool', focus = 'IV') |> 
            plotMatrix(loops = loops, borders = borders, limits = c(-4, -1), dpi = 120)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        import(mcool_file_path, format = 'mcool', focus = first_chrom) |> 
            plotMatrix(loops = loops, borders = borders, limits = c(-4, -1), dpi = 120)
    })
    ggsave("plot4_matrix_loops_borders.pdf", plot = p4, width = 7, height = 6)
    
    # ==========================================
    # --- Aggregate matrices over features (e.g., loops) ---
    # ==========================================
    aggr_centros <- tryCatch({
        HiContacts::aggregate(
            hic, targets = loops, BPPARAM = BiocParallel::SerialParam()
        )
    }, error = function(e) {
        warning("Aggregation failed: ", e\$message)
        NULL
    })
    
    if (!is.null(aggr_centros)) {
        saveRDS(aggr_centros, "aggregated_centros.rds")
        p_aggr <- plotMatrix(
            aggr_centros, use.scores = 'detrended', limits = c(-1, 1), scale = 'linear', 
            cmap = bgrColors()
        )
        ggsave("plot5_aggregated_matrix.pdf", plot = p_aggr, width = 6, height = 5)
    }
    
    # ==========================================
    # --- Compute autocorrelated contact maps ---
    # ==========================================
    hic_auto <- tryCatch({
        import(mcool_file_path, format = 'mcool', focus = 'chr2', resolution = 160000)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        avail_res <- tryCatch(resolutions(import(mcool_file_path, format = 'mcool')), error = function(err) 160000)
        import(mcool_file_path, format = 'mcool', focus = first_chrom, resolution = avail_res[1])
    })
    
    hic_auto <- autocorrelate(hic_auto)
    saveRDS(hic_auto, "autocorrelated_hic.rds")
    
    # Export scores summary
    sink("autocorrelated_scores_summary.txt")
    print(scores(hic_auto))
    print(summary(scores(hic_auto, 'autocorrelated')))
    sink()
    
    p_auto <- plotMatrix(hic_auto, use.scores = 'autocorrelated', limits = c(-1, 1), scale = 'linear')
    ggsave("plot6_autocorrelated_matrix.pdf", plot = p_auto, width = 7, height = 6)
    
    # ==========================================
    # --- Detrend contact maps (scores over expected) ---
    # ==========================================
    hic_detrend <- tryCatch({
        import(mcool_file_path, format = 'mcool', focus = 'chr18:20000000-35000000', resolution = 40000)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        avail_res <- tryCatch(resolutions(import(mcool_file_path, format = 'mcool')), error = function(err) 40000)
        import(mcool_file_path, format = 'mcool', focus = first_chrom, resolution = avail_res[1])
    })
    
    detrended_hic <- detrend(hic_detrend)
    saveRDS(detrended_hic, "detrended_hic.rds")
    
    p_detrend <- tryCatch({
        patchwork::wrap_plots(
            plotMatrix(detrended_hic, use.scores = 'expected', scale = 'log10', limits = c(-3, -1), dpi = 120),
            plotMatrix(detrended_hic, use.scores = 'detrended', scale = 'linear', limits = c(-1, 1), dpi = 120)
        )
    }, error = function(e) {
        plotMatrix(detrended_hic, use.scores = 'detrended', scale = 'linear', limits = c(-1, 1), dpi = 120)
    })
    ggsave("plot7_detrended_comparison.pdf", plot = p_detrend, width = 12, height = 5)
    
    # ==========================================
    # --- Merge (sum) two contact maps ---
    # ==========================================
    # Using the same mcool file to simulate two conditions/samples as requested
    mcool_file_1 <- mcool_file_path
    mcool_file_2 <- mcool_file_path
    
    hic_1 <- tryCatch({
        import(mcool_file_1, format = 'mcool', focus = 'II:1-300000', resolution = 2000)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        avail_res <- tryCatch(resolutions(import(mcool_file_path, format = 'mcool')), error = function(err) 2000)
        import(mcool_file_1, format = 'mcool', focus = first_chrom, resolution = avail_res[1])
    })
    
    hic_2 <- tryCatch({
        import(mcool_file_2, format = 'mcool', focus = 'II:1-300000', resolution = 2000)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        avail_res <- tryCatch(resolutions(import(mcool_file_path, format = 'mcool')), error = function(err) 2000)
        import(mcool_file_2, format = 'mcool', focus = first_chrom, resolution = avail_res[1])
    })
    
    merged_hic <- merge(hic_1, hic_2)
    saveRDS(merged_hic, "merged_hic.rds")
    
    # ==========================================
    # --- Divide (compute ratio) between two contact maps ---
    # ==========================================
    hic_1_div <- tryCatch({
        import(mcool_file_1, format = 'mcool', focus = 'II', resolution = 2000)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        avail_res <- tryCatch(resolutions(import(mcool_file_path, format = 'mcool')), error = function(err) 2000)
        import(mcool_file_1, format = 'mcool', focus = first_chrom, resolution = avail_res[1])
    })
    
    hic_2_div <- tryCatch({
        import(mcool_file_2, format = 'mcool', focus = 'II', resolution = 2000)
    }, error = function(e) {
        first_chrom <- seqlevels(hic)[1]
        avail_res <- tryCatch(resolutions(import(mcool_file_path, format = 'mcool')), error = function(err) 2000)
        import(mcool_file_2, format = 'mcool', focus = first_chrom, resolution = avail_res[1])
    })
    
    div_hic <- divide(hic_1_div, by = hic_2_div)
    saveRDS(div_hic, "divided_hic.rds")
    
    p_div <- tryCatch({
        patchwork::wrap_plots(
            plotMatrix(hic_1_div, use.scores = 'balanced', scale = 'log10', limits = c(-4, -1)),
            plotMatrix(hic_2_div, use.scores = 'balanced', scale = 'log10', limits = c(-4, -1)),
            plotMatrix(div_hic, use.scores = 'balanced.fc', scale = 'log2', limits = c(-2, 2), cmap = bgrColors())
        )
    }, error = function(e) {
        plotMatrix(div_hic, use.scores = 'balanced.fc', scale = 'log2', limits = c(-2, 2), cmap = bgrColors())
    })
    ggsave("plot8_divided_comparison.pdf", plot = p_div, width = 15, height = 5)
    
    # ==========================================
    # --- Despeckle (smooth) contact maps ---
    # ==========================================
    hic_1_despeckled <- despeckle(hic_1_div)
    hic_1_despeckled5 <- despeckle(hic_1_div, focal.size = 5)
    saveRDS(hic_1_despeckled, "despeckled_focal3.rds")
    saveRDS(hic_1_despeckled5, "despeckled_focal5.rds")
    
    p_despeckle <- tryCatch({
        patchwork::wrap_plots(
            plotMatrix(hic_1_div, use.scores = 'balanced', scale = 'log10', limits = c(-4, -1)),
            plotMatrix(hic_1_despeckled, use.scores = 'balanced.despeckled', scale = 'log10', limits = c(-4, -1)),
            plotMatrix(hic_1_despeckled5, use.scores = 'balanced.despeckled', scale = 'log10', limits = c(-4, -1))
        )
    }, error = function(e) {
        plotMatrix(hic_1_despeckled, use.scores = 'balanced.despeckled', scale = 'log10', limits = c(-4, -1))
    })
    ggsave("plot9_despeckle_comparison.pdf", plot = p_despeckle, width = 15, height = 5)
    
    # Save session info
    writeLines(capture.output(sessionInfo()), "session_info.txt")

    writeLines(c(
        '"BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION":',
        paste0('    HiContacts: ', as.character(packageVersion('HiContacts')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_arithmetics_and_visualization.csv versions.yml
    """
}

workflow BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cool_file.cool, mcool_file.mcool, S288C-loops.bedpe, S288C-borders.bed ] ]

    main:
    BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION.out.tables
    plots    = BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION.out.plots
    objects  = BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION.out.objects
    versions = BIOC_HICONTACTS_MATRIX_ARITHMETICS_AND_VISUALIZATION.out.versions
}
