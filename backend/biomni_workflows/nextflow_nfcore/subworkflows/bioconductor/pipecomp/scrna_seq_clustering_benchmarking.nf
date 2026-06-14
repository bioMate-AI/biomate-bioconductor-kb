#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pipeComp — scrna_seq_clustering_benchmarking
// Benchmark and evaluate single-cell RNA-seq clustering pipelines (doublet detection, filtering, normalization, feature selection, dimensional reduction, and clus
// Input: dataset1.SCE.rds, dataset2.SCE.rds
// Container: quay.io/biocontainers/bioconductor-pipecomp:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, pipeComp
// Visualizations: heatmap, cluster plot
// QC: doublet detection QC, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the scRNA-seq pipeline definition using scrna_pipeline
//  * 2. [Input & Preparation] Load alternative wrapper functions
//  * 3. [Input & Preparation] Define alternative parameter values
//  * 4. [Core Analysis] Run the pipeline using runPipeline
//  * 5. [Visualization & Output] Evaluate and plot filtering bias using scrna_evalPlot_filtering
//  * 6. [Visualization & Output] Evaluate and plot reduced space metrics using scrna_evalPlot_silh and evalHeatmap
//  * 7. [Visualization & Output] Evaluate and plot clustering accuracy using evalHeatmap and scrna_evalPlot_overall
//  * 8. [Visualization & Output] Plot computing times using plotElapsed

nextflow.enable.dsl = 2

process BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING {
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
    .bm_deps <- c("pipeComp", "ComplexHeatmap")
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
        
    library(pipeComp)
    library(ComplexHeatmap)
    
    # 1. Load the scRNA-seq pipeline definition using scrna_pipeline
    pipDef <- scrna_pipeline(pipeClass = "seurat")
    
    # 2. Load alternative wrapper functions (avoiding system.file)
    scrna_alt_path <- file.path(find.package("pipeComp"), "extdata", "scrna_alternatives.R")
    source(scrna_alt_path)
    
    # Read and prepare the user input datasets from the working directory
    datasets_files <- c(
      dataset1 = "dataset1.SCE.rds",
      dataset2 = "dataset2.SCE.rds"
    )
    
    datasets <- lapply(datasets_files, function(f) {
      sce <- readRDS(f)
      sce <- add_meta(sce)
      sce <- compute_all_gene_info(sce)
      sce
    })
    
    # 3. Define alternative parameter values
    alternatives <- list(
      doubletmethod=c("none"),
      filt=c("filt.lenient", "filt.stringent"),
      norm=c("norm.seurat", "norm.sctransform", "norm.scran"),
      sel=c("sel.vst"),
      selnb=2000,
      dr=c("seurat.pca"),
      clustmethod=c("clust.seurat"),
      dims=c(10, 15, 20, 30),
      resolution=c(0.01, 0.1, 0.2, 0.3, 0.5, 0.8, 1, 1.2, 2)
    )
    
    # 4. Run the pipeline using runPipeline
    res <- runPipeline(datasets, alternatives, pipDef, nthreads=3)
    
    # Save the pipeline results object
    saveRDS(res, "pipeline_results.rds")
    
    # Save evaluation tables to CSV
    if (!is.null(res\$evaluation\$filtering)) {
      write.csv(res\$evaluation\$filtering, "filtering_evaluation.csv", row.names = FALSE)
    }
    if (!is.null(res\$evaluation\$clustering)) {
      write.csv(res\$evaluation\$clustering, "clustering_evaluation.csv", row.names = FALSE)
    }
    
    # 5. Evaluate and plot filtering bias using scrna_evalPlot_filtering
    pdf("filtering_bias_plot.pdf", width = 8, height = 6)
    print(scrna_evalPlot_filtering(res))
    dev.off()
    
    # 6. Evaluate and plot reduced space metrics using scrna_evalPlot_silh and evalHeatmap
    pdf("silhouette_plots.pdf", width = 10, height = 8)
    scrna_evalPlot_silh(res)
    h <- scrna_evalPlot_silh(res, heatmap_legend_param=list(direction="horizontal"))
    draw(h, heatmap_legend_side="bottom", annotation_legend_side = "bottom", merge_legend=TRUE)
    dev.off()
    
    pdf("dimreduction_heatmaps.pdf", width = 12, height = 8)
    p1 <- evalHeatmap(res, step="dimreduction", what="log10_total_features", what2="meanAbsCorr.covariate2")
    draw(p1)
    
    p2 <- evalHeatmap(res, step="dimreduction", what="log10_total_features", what2="meanAbsCorr.covariate2") + 
          evalHeatmap(res, step="dimreduction", what="log10_total_counts", what2="meanAbsCorr.covariate2")
    draw(p2)
    
    p3 <- evalHeatmap(res, step="dimreduction", what2="meanAbsCorr.covariate2", 
                      what=c("log10_total_features","log10_total_counts"), 
                      row_title="mean(abs(correlation))\nwith covariate")
    draw(p3)
    dev.off()
    
    # 7. Evaluate and plot clustering accuracy using evalHeatmap and scrna_evalPlot_overall
    pdf("clustering_heatmaps.pdf", width = 12, height = 8)
    c1 <- evalHeatmap(res, step="clustering", what=c("MI","ARI"), agg.by=c("filt","norm"))
    draw(c1)
    
    c2 <- evalHeatmap(res, step = "clustering", what=c("MI","ARI"), agg.by=c("norm", "dims"), row_split=norm)
    draw(c2)
    
    c3 <- evalHeatmap(res, step = "clustering", what=c("MI","ARI"), agg.by=c("filt","norm")) + 
          evalHeatmap(res, step = "clustering", what="ARI", agg.by=c("filt", "norm"), 
                      filter=n_clus==true.nbClusts, title="ARI at\ntrue k")
    draw(c3)
    dev.off()
    
    pdf("overall_evaluation_heatmap.pdf", width = 12, height = 10)
    h_overall <- scrna_evalPlot_overall(res)
    draw(h_overall, heatmap_legend_side="bottom")
    dev.off()
    
    # 8. Plot computing times using plotElapsed
    pdf("elapsed_time_plot.pdf", width = 8, height = 6)
    print(plotElapsed(res, agg.by="norm"))
    dev.off()

    writeLines(c(
        '"BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING":',
        paste0('    pipeComp: ', as.character(packageVersion('pipeComp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_seq_clustering_benchmarking.csv versions.yml
    """
}

workflow BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset1.SCE.rds, dataset2.SCE.rds ] ]

    main:
    BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING(ch_input)

    emit:
    tables   = BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING.out.tables
    plots    = BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING.out.plots
    objects  = BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING.out.objects
    versions = BIOC_PIPECOMP_SCRNA_SEQ_CLUSTERING_BENCHMARKING.out.versions
}
