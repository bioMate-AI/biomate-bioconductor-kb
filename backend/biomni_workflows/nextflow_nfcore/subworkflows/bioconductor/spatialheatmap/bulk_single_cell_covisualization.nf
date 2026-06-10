#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialHeatmap — bulk_single_cell_covisualization
// Co-visualize single-cell embedding plots with tissue-level spatial heatmaps using annotation labels or automated co-clustering.
// Input: single_cell_data.rds, bulk_data.rds, anatomical_map.svg
// Container: quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0
// R packages: SingleCellExperiment, SummarizedExperiment, ggplot2, spatialHeatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0"

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
    .bm_deps <- c("SingleCellExperiment", "SummarizedExperiment", "ggplot2", "spatialHeatmap")
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
    library(spatialHeatmap)
    library(SingleCellExperiment)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # 1. Read the declared user input files from the working directory
    sce <- readRDS("single_cell_data.rds")
    blk.mus <- readRDS("bulk_data.rds")
    svg.mus.brain <- read_svg("anatomical_map.svg")
    
    # 2. Jointly normalize bulk and single-cell data
    mus.lis.nor <- norm_cell(sce=sce, bulk=blk.mus, com=FALSE)
    blk.mus.nor <- mus.lis.nor\$bulk
    cell.mus.nor <- mus.lis.nor\$cell
    colData(cell.mus.nor) <- colData(sce)
    
    # 3. Perform dimension reduction on single-cell data
    cell.dim <- reduce_dim(cell.mus.nor)
    
    # 4. Aggregate bulk replicates
    blk.mus.aggr <- aggr_rep(blk.mus.nor, sam.factor='sample', aggr='mean')
    
    # Define the list container expected by the documented cocluster call
    blk.sc.mus.fil <- list(bulk = blk.mus.aggr, cell = cell.dim)
    
    # 5. Perform automated co-clustering to assign cells to tissues
    coclus.mus <- cocluster(bulk=blk.sc.mus.fil\$bulk, cell=blk.sc.mus.fil\$cell, min.dim=14, dimred='PCA', graph.meth='knn', cluster='fg')
    coclus.mus <- filter_asg(coclus.mus, min.sim=0.1)
    
    # Subset co-clustering results for bulk and single-cell
    coclus.blk <- subset(coclus.mus, , bulkCell=='bulk')
    coclus.sc <- subset(coclus.mus, , bulkCell=='cell')
    
    # Save intermediate co-clustering results
    saveRDS(coclus.mus, "cocluster_results.rds")
    
    # 6. Define cell-to-tissue mappings and store in an SPHM container
    dat.auto.idp <- SPHM(svg=svg.mus.brain, bulk=coclus.blk, cell=coclus.sc)
    saveRDS(dat.auto.idp, "sphm_container.rds")
    
    # 7. Generate the co-visualization plot
    cov.plot <- covis(data=dat.auto.idp, ID=c('Atp2b1'), dimred='TSNE', tar.cell=c('hippocampus', 'hypothalamus', 'cerebellum', 'cerebral.cortex'), col.idp=TRUE, dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.08, legend.nrow=3, h=0.6, legend.key.size=0.01, legend.text.size=10, legend.r=0.27)
    
    # Save the generated plot to a PDF file
    pdf("covisualization_plot.pdf", width = 12, height = 10)
    print(cov.plot)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION":
        spatialHeatmap: \$(Rscript -e 'cat(as.character(packageVersion("spatialHeatmap")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_single_cell_covisualization.csv versions.yml
    """
}

workflow BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single_cell_data.rds, bulk_data.rds, anatomical_map.svg ] ]

    main:
    BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION.out.tables
    plots    = BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION.out.plots
    objects  = BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION.out.objects
    versions = BIOC_SPATIALHEATMAP_BULK_SINGLE_CELL_COVISUALIZATION.out.versions
}
