#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spatialHeatmap
// The spatialHeatmap package offers the primary functionality for visualizing cell-, tissue- and organ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spatialHeatmap/inst/doc/covisualize.R
// Upstream  : BiocParallel, ExpressionAtlas, GEOquery, Seurat, SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("spatialHeatmap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALHEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialheatmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialheatmap:2.12.1--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialheatmap:2.12.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialheatmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialheatmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialheatmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spatialHeatmap)
    library(jsonlite)


    # --- Css [] ---
    # Key functions: markdown, include_graphics, readRDS, process_cell_meta, rowData, colData, cell_mouse_brain.rds, spatialHeatmap
    BiocStyle::markdown(css.files=c('file/custom.css'))
    include_graphics('img/data_str.jpg')
    include_graphics('img/group_color.jpg')
    cache.pa <- '~/.cache/shm' # Set path of the cache directory
    sce.pa <- system.file("extdata/shinyApp/data", "cell_mouse_brain.rds", package="spatialHeatmap")
    sce <- readRDS(sce.pa)
    sce.dimred.quick <- process_cell_meta(sce, qc.metric=list(subsets=list(Mt=rowData(sce)$featureType=='mito'), threshold=1))
    colData(sce.dimred.quick)[1:3, 1:2]
    sce.aggr.quick <- aggr_rep(sce.dimred.quick, assay.na='logcounts', sam.factor='label', aggr='mean')
    svg.mus.brain.pa <- system.file("extdata/shinyApp/data", "mus_musculus.brain.svg", package="spatialHeatmap")
    svg.mus.brain <- read_svg(svg.mus.brain.pa)
    tail(attribute(svg.mus.brain)[[1]])[, 1:4]
    lis.match.quick <- list(hypothalamus=c('hypothalamus'), cortex.S1=c('cerebral.cortex', 'nose'))
    dat.quick <- SPHM(svg=svg.mus.brain, bulk=sce.aggr.quick, cell=sce.dimred.quick, match=lis.match.quick)

    # --- Eval=true [] ---
    # Key functions: covis, colData, readRDS, assay, bulk_mouse_cocluster.rds, spatialHeatmap, read_cache, norm_cell
    shm.res.quick <- covis(data=dat.quick, ID=c('Apod'), dimred='UMAP', cell.group='label', tar.cell=names(lis.match.quick), assay.na='logcounts', bar.width=0.09, dim.lgd.nrow=2, legend.r=1.5, legend.key.size=0.02, legend.text.size=10, legend.nrow=4, h=0.6, verbose=FALSE)
    colData(sce)[1:3, 1:2]
    blk.mus.pa <- system.file("extdata/shinyApp/data", "bulk_mouse_cocluster.rds", package="spatialHeatmap") 
    blk.mus <- readRDS(blk.mus.pa)
    assay(blk.mus)[1:3, 1:5]
    colData(blk.mus)[1:3, , drop=FALSE]
    mus.ann.nor <- read_cache(cache.pa, 'mus.ann.nor') 
    if (is.null(mus.ann.nor)) {
      # Joint normalization.
      mus.lis.nor <- norm_cell(sce=sce, bulk=blk.mus, quick.clus=list(min.size = 100, d=15), com=FALSE)
      save_cache(dir=cache.pa, overwrite=TRUE, mus.ann.nor)
    }
    # Separate bulk and cell data.
    blk.mus.nor <- mus.lis.nor$bulk
    cell.mus.nor <- mus.lis.nor$cell
    colData(cell.mus.nor) <- colData(sce)
    cell.dim <- reduce_dim(cell.mus.nor, min.dim=5)
    plot_dim(cell.dim, color.by="label", dim='UMAP')
    # Aggregation.
    blk.mus.aggr <- aggr_rep(blk.mus.nor, sam.factor='sample', aggr='mean')

    # --- Eval=true [] ---
    # Key functions: covis, include_graphics, dimensionReduction, topDimensions, graphBuilding, clusterDetection, write.table, kable_styling
    covis(data=dat.ann.tocell, ID=c('Cacnb4'), profile=FALSE, dimred='UMAP', cell.group='label', tar.bulk=names(lis.match.blk), bar.width=0.09, dim.lgd.nrow=2, dim.lgd.text.size=12, h=0.8, legend.r=1.5, legend.key.size=0.02, legend.text.size=10, legend.nrow=3)
    covis(data=dat.ann.tocell, ID=c('Cacnb4'), col.idp=TRUE, dimred='UMAP', cell.group='label', tar.bulk=names(lis.match.blk), bar.width=0.08, dim.lgd.nrow=2, dim.lgd.text.size=10, h=0.6, legend.r=0.1, legend.key.size=0.01, legend.text.size=10, legend.nrow=2)
    include_graphics('img/coclustering.jpg')
    # --- Eval=true [] ---
    # Key functions: filter_asg, plot_dim, SPHM, covis, readRDS, assay, read_cache, gzcon
    coclus.mus <- filter_asg(coclus.mus, min.sim=0.1)
    plot_dim(coclus.mus, dim='PCA', color.by='cluster', cocluster.only=TRUE, group.sel=NULL)
    # Separate bulk data.
    coclus.blk <- subset(coclus.mus, , bulkCell=='bulk')
    # Separate single cell data.
    coclus.sc <- subset(coclus.mus, , bulkCell=='cell')
    # Store data objects in an SPHM container. 
    dat.auto.idp <- SPHM(svg=svg.mus.brain, bulk=coclus.blk, cell=coclus.sc)
    covis(data=dat.auto.idp, ID=c('Atp2b1'), dimred='TSNE', tar.cell=c('hippocampus', 'hypothalamus', 'cerebellum', 'cerebral.cortex'), col.idp=TRUE, dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.08, legend.nrow=3, h=0.6, legend.key.size=0.01, legend.text.size=10, legend.r=0.27)
    # Importing bulk data.
    blk.sp <- readRDS(system.file("extdata/shinyApp/data", "bulk_sp.rds", package="spatialHeatmap"))
    # Bulk assay data are partially shown.
    assay(blk.sp)[1:3, ]
    # Importing SRSC data.
    srt.sc <- read_cache(cache.pa, 'srt.sc') 
    if (is.null(srt.sc)) {
      srt.sc <- readRDS(gzcon(url("https://zenodo.org/record/8240964/files/srt_sc.rds?download=1")))
      save_cache(dir=cache.pa, overwrite=TRUE, srt.sc)
    }
    # SRSC metadata of cells are partially shown.

    # --- Eval=true [] ---
    # Key functions: SPHM, covis, cerebral.cortex, readRDS, colData, shiny_covis_bulk_cell_mouse_brain.rds, spatialHeatmap, read.table
    # Association between "cerebral.cortex" and clusters.
    lis.match <- list(cerebral.cortex=c('clus1', 'clus2', 'clus3', 'clus5'))   
    dat.srsc <- SPHM(svg=svg.mus.sp, bulk=blk.sp, cell=srt.sc, match=lis.match)
    covis(data=dat.srsc, ID='Epha4', assay.na='logcounts', dimred='TSNE', cell.group='seurat_clusters', tar.bulk=c('cerebral.cortex'), col.idp=TRUE, bar.width=0.07, dim.lgd.nrow=2, dim.lgd.text.size=8, legend.r=0.1, legend.key.size=0.013, legend.text.size=10, legend.nrow=3, h=0.6, profile=TRUE, ncol=3, vjust=5, dim.lgd.key.size=3, size.r=0.97, dim.axis.font.size=8, size.pt=1.5, lgd.plots.size=c(0.35, 0.25, 0.35), verbose=FALSE)
    shiny.dat.pa <- system.file("extdata/shinyApp/data", "shiny_covis_bulk_cell_mouse_brain.rds", package="spatialHeatmap")
    shiny.dat <- readRDS(shiny.dat.pa)
    colData(shiny.dat)
    manual.clus.mus.sc.pa <- system.file("extdata/shinyApp/data", "manual_cluster_mouse_brain.txt", package="spatialHeatmap")
    manual.clus.mus.sc <- read.table(manual.clus.mus.sc.pa, header=TRUE, sep='\t')
    manual.clus.mus.sc[1:3, ]
    sce.clus <- cell_group(sce=sce.dimred.quick, df.group=manual.clus.mus.sc, cell='cell', cell.group='cluster')
    colData(sce.clus)[1:3, c('cluster', 'label', 'variable')]
    plot_dim(sce.clus, color.by="cluster", dim='TSNE')
    tail(attribute(svg.mus.brain)[[1]])[1:3, 1:4]
    lis.match.clus <- list(clus1=c('cerebral.cortex'), clus3=c('brainstem', 'medulla.oblongata'))
    sce.clus.aggr <- aggr_rep(sce.clus, assay.na='logcounts', sam.factor='cluster', con.factor='variable', aggr='mean')
    colData(sce.clus.aggr)[1:3, c('cluster', 'label', 'variable')]
    # Store data objects in an SPHM container. 
    dat.man.tobulk <- SPHM(svg=svg.mus.brain, bulk=sce.clus.aggr, cell=sce.clus, match=lis.match.clus)
    covis(data=dat.man.tobulk, ID=c('Tcea1'), dimred='TSNE', cell.group='cluster', assay.na='logcounts', tar.cell=names(lis.match.clus), bar.width=0.09, dim.lgd.nrow=1, h=0.6, legend.r=1.5, legend.key.size=0.02, legend.text.size=12, legend.nrow=4, verbose=FALSE)

    # --- Eval=true [] ---
    # Key functions: SPHM, covis, attribute, plot_dim, refine_asg
    # Store data objects in an SPHM container. 
    dat.auto.tobulk <- SPHM(svg=svg.mus.brain, bulk=sc.aggr.coclus, cell=coclus.sc)
    covis(data=dat.auto.tobulk, ID=c('Atp2b1'), dimred='TSNE', tar.cell=c('hippocampus', 'hypothalamus', 'cerebellum', 'cerebral.cortex'), dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.09, legend.nrow=5, h=0.6, legend.key.size=0.02, legend.text.size=12, legend.r=1.5)
    coclus.blk <- subset(coclus.mus, , bulkCell=='bulk')
    colnames(coclus.blk) %in% attribute(svg.mus.brain)[[1]]$feature
    # Store data objects in an SPHM container. 
    dat.auto.tocell <- SPHM(svg=svg.mus.brain, bulk=coclus.blk, cell=coclus.sc)
    covis(data=dat.auto.tocell, ID=c('Atp2b1'), dimred='TSNE', tar.bulk=colnames(coclus.blk), assay.na='logcounts', legend.nrow=5, dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.08, h=0.6, legend.key.size=0.02, legend.text.size=12, legend.r=1.5)
    covis(data=dat.auto.tocell, ID=c('Atp2b1'), dimred='TSNE', profile=FALSE, assay.na='logcounts', legend.nrow=4, dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.09)
    plot_dim(coclus.mus, dim='PCA', color.by='sample', x.break=seq(-10, 10, 1), y.break=seq(-10, 10, 1), panel.grid=TRUE, lgd.ncol=2)
    df.desired.bulk <- data.frame(x.min=c(-8), x.max=c(5), y.min=c(1), y.max=c(5), desiredBulk=c('hippocampus'), dimred='PCA') 
    df.desired.bulk
    # Incorporate desired bulk
    coclus.mus.tailor <- refine_asg(sce.all=coclus.mus, df.desired.bulk=df.desired.bulk)
    # Separate cells from bulk
    coclus.sc.tailor <- subset(coclus.mus.tailor, , bulkCell=='cell')
    # Store data objects in an SPHM container. 
    dat.auto.tocell.tailor <- SPHM(svg=svg.mus.brain, bulk=coclus.blk, cell=coclus.sc.tailor)
    covis(data=dat.auto.tocell.tailor, ID=c('Atp2b1'), dimred='PCA', tar.bulk=c('hippocampus'), assay.na='logcounts', legend.nrow=4, dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.08, legend.r=1.5)
    covis(data=dat.auto.tocell, ID=c('Atp2b1'), dimred='PCA', tar.bulk=c('hippocampus'), assay.na='logcounts', legend.nrow=4, dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.08, legend.r=1.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialheatmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialheatmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialheatmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALHEATMAP:", paste0("    spatialheatmap: ", packageVersion("spatialHeatmap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialheatmap_results.csv
    touch ${prefix}_spatialheatmap_output.rds
    echo "BIOC_SPATIALHEATMAP:" > versions.yml
    echo "    spatialheatmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALHEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALHEATMAP(ch_input)

    emit:
    results  = BIOC_SPATIALHEATMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALHEATMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALHEATMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALHEATMAP.out.versions  // channel: path(versions.yml)
}
