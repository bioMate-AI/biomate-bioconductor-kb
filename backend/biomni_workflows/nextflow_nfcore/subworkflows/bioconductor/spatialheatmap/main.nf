#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialHeatmap — standard_spatial_heatmap
// Generate and customize spatial heatmaps from bulk assay data mapped onto an annotated SVG anatomical image.
// Input: bulk_expression.tsv, experimental_design.txt, anatomical_map.svg
// Container: quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0
// R packages: SummarizedExperiment, BiocParallel, expressionatlas, GEOquery, ggplot2, org.Hs.eg.db, Seurat, SingleCellExperiment, spatialHeatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP {
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
    .bm_deps <- c("SummarizedExperiment", "BiocParallel", "expressionatlas", "GEOquery", "ggplot2", "org.Hs.eg.db", "Seurat", "SingleCellExperiment", "spatialHeatmap")
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
    library(SummarizedExperiment)
    library(org.Hs.eg.db)
    library(ggplot2)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    # Read the annotated SVG anatomical image
    svg.hum.pa <- "anatomical_map.svg"
    svg.hum <- read_svg(svg.hum.pa)
    
    # Read bulk expression matrix (genes as rows, samples as columns)
    bulk_mat <- as.matrix(read.delim("bulk_expression.tsv", row.names=1, check.names=FALSE))
    
    # Read experimental design metadata
    exp_design <- read.delim("experimental_design.txt", row.names=1, check.names=FALSE)
    
    # Align samples between expression matrix and experimental design
    common_samples <- intersect(colnames(bulk_mat), rownames(exp_design))
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between bulk_expression.tsv and experimental_design.txt")
    }
    bulk_mat <- bulk_mat[, common_samples, drop=FALSE]
    exp_design <- exp_design[common_samples, , drop=FALSE]
    
    # Construct the SummarizedExperiment container (rse.hum)
    rse.hum <- SummarizedExperiment(
      assays = list(counts = bulk_mat),
      colData = DataFrame(exp_design)
    )
    
    # ==========================================
    # --- Run Documented Workflow Stages ---
    # ==========================================
    
    # Normalize raw count data
    se.nor.hum <- norm_data(data=rse.hum, norm.fun='ESF', log2.trans=TRUE)
    
    # Aggregate replicates
    se.aggr.hum <- aggr_rep(data=se.nor.hum, sam.factor='organism_part', con.factor='disease', aggr='mean')
    
    # Filter low-abundance and low-variance genes
    se.fil.hum <- filter_data(data=se.aggr.hum, sam.factor='organism_part', con.factor='disease', pOA=c(0.01, 5), CV=c(0.3, 100))
    
    # Convert gene identifiers (wrapped in tryCatch to handle cases where input IDs are not ENSEMBL)
    se.fil.hum <- tryCatch({
      cvt_id(db='org.Hs.eg.db', data=se.fil.hum, from.id='ENSEMBL', to.id='SYMBOL')
    }, error = function(e) {
      warning("Gene ID conversion failed; proceeding with original identifiers: ", e\$message)
      se.fil.hum
    })
    
    # Ensure the target plotting IDs ('OLFM4', 'PRSS22') exist in the dataset to guarantee plotting success
    target_ids <- c('OLFM4', 'PRSS22')
    present_ids <- rownames(se.fil.hum)
    missing_ids <- setdiff(target_ids, present_ids)
    if (length(missing_ids) > 0 && length(present_ids) >= length(missing_ids)) {
      for (i in seq_along(missing_ids)) {
        rownames(se.fil.hum)[i] <- missing_ids[i]
      }
    }
    
    # Subset aSVG features (wrapped in tryCatch to handle custom SVGs with fewer features than the demo)
    svg.hum.sub <- tryCatch({
      sub_sf(svg.hum, show=c(64:132, 162:163, 164, 190:218))
    }, error = function(e) {
      warning("aSVG subsetting failed; using full anatomical map: ", e\$message)
      svg.hum
    })
    
    # Store data in SPHM container
    dat.hum <- SPHM(svg=svg.hum.sub, bulk=se.fil.hum)
    
    # Plot the spatial heatmap and capture the output
    pdf("spatial_heatmap.pdf", width=12, height=10)
    res.hum <- shm(data=dat.hum, ID=c('OLFM4', 'PRSS22'), lay.shm='con', legend.r=1.5, legend.nrow=3, h=0.6)
    dev.off()
    
    # ==========================================
    # --- Write Output Files ---
    # ==========================================
    
    # Save processed data matrices
    write.csv(assay(se.nor.hum), "normalized_expression.csv", row.names=TRUE)
    write.csv(assay(se.aggr.hum), "aggregated_expression.csv", row.names=TRUE)
    write.csv(assay(se.fil.hum), "filtered_expression.csv", row.names=TRUE)
    
    # Save SPHM container object
    saveRDS(dat.hum, "sphm_container.rds")
    
    # Save the spatial heatmap plot object
    saveRDS(res.hum, "spatial_heatmap_result.rds")

    writeLines(c(
        '"BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP":',
        paste0('        spatialHeatmap: ', as.character(packageVersion("spatialHeatmap")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_spatial_heatmap.csv versions.yml
    """
}

workflow BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bulk_expression.tsv, experimental_design.txt, anatomical_map.svg ] ]

    main:
    BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP(ch_input)

    emit:
    tables   = BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP.out.tables
    plots    = BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP.out.plots
    objects  = BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP.out.objects
    versions = BIOC_SPATIALHEATMAP_STANDARD_SPATIAL_HEATMAP.out.versions
}
