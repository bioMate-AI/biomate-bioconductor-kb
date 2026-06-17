#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: heatmaps — genomic_coverage_heatmaps
// Plot heatmaps and meta-region profiles of functional genomics coverage data (e.g., ChIP-seq) over genomic windows, with optional row clustering.
// Input: genomic_intervals.bed, coverage_data.rds
// Container: quay.io/biocontainers/bioconductor-heatmaps:1.34.0--r45hdfd78af_0
// R packages: GenomicRanges, heatmaps, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, heatmaps, rtracklayer
// Visualizations: heatmap (ComplexHeatmap), image plot, heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import genomic intervals and define centered genomic windows, trimming out-of-bound ranges
//  * 2. [Input & Preparation] Load coverage data
//  * 3. [Visualization & Output] Create a heatmap object using CoverageHeatmap
//  * 4. [Visualization & Output] Plot the heatmap using plotHeatmapList or meta-region plot using plotHeatmapMeta
//  * 5. [Visualization & Output] (Optional) Extract the raw matrix, cluster rows using kmeans, and plot the partitioned heatmap

nextflow.enable.dsl = 2

process BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "heatmaps", "rtracklayer")
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
    library(heatmaps)
    library(rtracklayer)
    library(GenomicRanges)
    
    # 1. Import genomic intervals and define centered genomic windows
    zf_30p_promoters = import("genomic_intervals.bed")
    
    # 2. Load coverage data
    coverage_data = readRDS("coverage_data.rds")
    
    # Handle single RleList or list of RleLists (e.g. pos/neg strands)
    if (is.list(coverage_data) && all(c("pos", "neg") %in% names(coverage_data))) {
        h3k4me3_30p_pos = coverage_data\$pos
        h3k4me3_30p_neg = coverage_data\$neg
        h3k4me3_30p = h3k4me3_30p_pos + h3k4me3_30p_neg
        h3k4me3_30p_subtracted = h3k4me3_30p_pos - h3k4me3_30p_neg
    } else {
        h3k4me3_30p = coverage_data
        h3k4me3_30p_subtracted = coverage_data
    }
    
    # Set seqlengths to allow proper trimming of out-of-bound ranges
    seq_lens = sapply(h3k4me3_30p, length)
    common_seqs = intersect(seqlevels(zf_30p_promoters), names(seq_lens))
    seqlengths(zf_30p_promoters)[common_seqs] = seq_lens[common_seqs]
    
    coords = c(-500, 500)
    
    # Define windows and trim out-of-bound ranges
    windows_30p = promoters(zf_30p_promoters, -coords[1], coords[2])
    windows_30p = windows_30p[width(trim(windows_30p)) == 1000]
    
    # 3. Create a heatmap object using CoverageHeatmap
    h3k4me3_30p_heatmap = CoverageHeatmap(
        windows_30p,
        h3k4me3_30p,
        coords=coords,
        label="H3K4me3 30p")
    
    # 4. Plot the heatmap and meta-region profile
    pdf("coverage_heatmap_plots.pdf", width=6, height=8)
    plotHeatmapList(h3k4me3_30p_heatmap, cex.label=1, color="Greens")
    plotHeatmapMeta(h3k4me3_30p_heatmap)
    dev.off()
    
    # 5. Create subtracted heatmap
    h3k4me3_30p_subtracted_hm = CoverageHeatmap(
        windows_30p,
        h3k4me3_30p_subtracted,
        coords=coords,
        label="Phase")
    
    # Set scale dynamically based on the actual data range to avoid saturation/washout
    current_scale = scale(h3k4me3_30p_subtracted_hm)
    max_val = max(abs(current_scale), na.rm = TRUE)
    hm_scale = c(-max_val, max_val)
    scale(h3k4me3_30p_subtracted_hm) = hm_scale
    
    pdf("subtracted_heatmap_plot.pdf", width=6, height=8)
    plotHeatmapList(h3k4me3_30p_subtracted_hm, cex.label=1.5, color=c("red", "white", "blue"), legend=TRUE, legend.width=0.3)
    dev.off()
    
    # 6. Extract raw matrix, cluster rows using kmeans, and plot partitioned heatmap
    raw_matrix = image(h3k4me3_30p_subtracted_hm)
    
    # Run kmeans clustering
    set.seed(42) # For reproducibility
    clusters = kmeans(raw_matrix, 2)\$cluster
    
    mat = raw_matrix[order(clusters),]
    
    h3k4me3_30p_subtracted_kmeans = Heatmap(
      mat,
      coords=coords,
      label="kmeans",
      scale=hm_scale)
    
    pdf("kmeans_clustered_heatmap.pdf", width=6, height=8)
    plotHeatmapList(h3k4me3_30p_subtracted_kmeans,
                    cex.label=1.5,
                    color=c("red", "white", "blue"),
                    partition=c(sum(clusters==1), sum(clusters==2)),
                    partition.legend=TRUE,
                    partition.lines=TRUE,
                    legend=TRUE,
                    legend.pos="r",
                    legend.width=0.3)
    dev.off()
    
    # Save outputs
    saveRDS(h3k4me3_30p_heatmap, "h3k4me3_30p_heatmap.rds")
    saveRDS(h3k4me3_30p_subtracted_kmeans, "h3k4me3_30p_subtracted_kmeans.rds")
    
    # Export cluster assignments
    cluster_df = data.frame(
        region_index = order(clusters),
        cluster = clusters[order(clusters)]
    )
    write.csv(cluster_df, "kmeans_clusters.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS":',
        paste0('    heatmaps: ', as.character(packageVersion('heatmaps')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_coverage_heatmaps.csv versions.yml
    """
}

workflow BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_intervals.bed, coverage_data.rds ] ]

    main:
    BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS(ch_input)

    emit:
    tables   = BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS.out.tables
    plots    = BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS.out.plots
    objects  = BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS.out.objects
    versions = BIOC_HEATMAPS_GENOMIC_COVERAGE_HEATMAPS.out.versions
}
