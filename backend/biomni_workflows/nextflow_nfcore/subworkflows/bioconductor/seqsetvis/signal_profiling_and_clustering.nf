#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqsetvis — signal_profiling_and_clustering
// Fetch continuous genomic signal from bigwig files over a set of regions, visualize signal profiles, perform clustering, and recenter regions at maximum signal.
// Input: bw_files, olaps
// Container: quay.io/biocontainers/bioconductor-seqsetvis:1.30.0--r45hdfd78af_0
// Requires: GenomicRanges, data.table, ggplot2, seqsetvis
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Resize query regions to a uniform fixed width
//  * 2. [Input & Preparation] Fetch signal from bigwig files
//  * 3. [Core Analysis] Factorize membership tables for grouping/coloring
//  * 4. [Visualization & Output] Plot individual or aggregated signal profiles
//  * 5. [Visualization & Output] Plot scatterplots comparing samples
//  * 6. [Visualization & Output] Plot banded quantiles
//  * 7. [Visualization & Output] Perform k-means clustering and plot heatmaps
//  * 8. [Core Analysis] Recenter regions at maximum signal and re-cluster

nextflow.enable.dsl = 2

process BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GenomicRanges", "data.table", "ggplot2", "seqsetvis")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(seqsetvis)
        library(GenomicRanges)
        library(data.table)
        library(ggplot2)
        
        # ==========================================
        # 1. Read User Inputs from Working Directory
        # ==========================================
        # The pipeline expects 'olaps.rds' (a GRanges object) and 'bw_files.rds' 
        # (a named vector of bigwig file paths) to be present in the working directory.
        if (!file.exists("olaps.rds") || !file.exists("bw_files.rds")) {
          stop("Required input files 'olaps.rds' and/or 'bw_files.rds' not found in the working directory.")
        }
        
        olaps <- readRDS("olaps.rds")
        bw_files <- readRDS("bw_files.rds")
        
        # ==========================================
        # 2. Prepare Variables for Documented Code
        # ==========================================
        # Calculate width_q75 as described in the vignette
        window_size <- 50
        width_q75 <- quantile(width(olaps), .75)
        width_q75 <- ceiling(width_q75 / window_size) * window_size
        
        # ==========================================
        # 3. Execute Documented Code Workflow
        # ==========================================
        olaps_fixedSize = centerFixedSizeGRanges(olaps, width_q75)
        bw_gr = ssvFetchBigwig(file_paths = bw_files, qgr = olaps_fixedSize, win_size = 50)
        
        # Define olap_gr and facet_label to ensure downstream compatibility
        olap_gr = olaps_fixedSize
        bw_gr\$facet_label = sub("_", "\n", bw_gr\$sample)
        
        olap_groups = ssvFactorizeMembTable(mcols(olap_gr))
        
        # Open PDF device to save all generated plots
        pdf("seqsetvis_pipeline_plots.pdf", width = 10, height = 8)
        
        p1 = ssvSignalLineplot(bw_data = subset(bw_gr, id %in% 1:12), facet_ = "facet_label")
        print(p1)
        
        p2 = ssvSignalLineplotAgg(bw_data = bw_gr)
        print(p2)
        
        p3 = ssvSignalScatterplot(bw_gr, x_name = names(bw_files)[1], y_name = names(bw_files)[2], color_table = olap_groups)
        print(p3)
        
        p4 = ssvSignalBandedQuantiles(bw_gr, by_ = "sample", hsv_grayscale = TRUE, hsv_symmetric = TRUE, hsv_reverse = TRUE)
        print(p4)
        
        clust_gr = ssvSignalClustering(bw_gr, nclust = 3, facet_ = "facet_label")
        
        p5 = ssvSignalHeatmap(clust_gr, facet_ = "facet_label")
        print(p5)
        
        center_gr = centerAtMax(clust_gr, view_size = 150, by_ = "id", check_by_dupes = FALSE)
        
        clust_center_gr = ssvSignalClustering(center_gr, nclust = 3)
        
        p6 = ssvSignalHeatmap(clust_center_gr, facet_ = "facet_label")
        print(p6)
        
        dev.off()
        
        # ==========================================
        # 4. Save Meaningful Results to Disk
        # ==========================================
        saveRDS(clust_gr, "clustered_regions.rds")
        saveRDS(clust_center_gr, "recentered_clustered_regions.rds")
        
        write.csv(as.data.frame(clust_gr), "clustered_regions.csv", row.names = FALSE)
        write.csv(as.data.frame(clust_center_gr), "recentered_clustered_regions.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING":',
        paste0('    seqsetvis: ', as.character(packageVersion('seqsetvis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signal_profiling_and_clustering.csv versions.yml
    """
}

workflow BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bw_files, olaps ] ]

    main:
    BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING.out.tables
    plots    = BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING.out.plots
    objects  = BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING.out.objects
    versions = BIOC_SEQSETVIS_SIGNAL_PROFILING_AND_CLUSTERING.out.versions
}
