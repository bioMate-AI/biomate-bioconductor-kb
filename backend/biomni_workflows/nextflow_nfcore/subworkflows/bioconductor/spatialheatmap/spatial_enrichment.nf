#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialHeatmap — spatial_enrichment
// Identify and visualize biomolecules that are significantly enriched or depleted in specific spatial regions.
// Input: bulk_expression.rds, anatomical_map.svg
// Container: quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0
// R packages: SummarizedExperiment, spatialHeatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: enrichment plot, UpSet plot, heatmap

nextflow.enable.dsl = 2

process BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT {
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
    .bm_deps <- c("SummarizedExperiment", "spatialHeatmap")
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
    library(spatialHeatmap)
    library(SummarizedExperiment)
    
    # Verify that the required user input files exist in the working directory
    input_expression <- "bulk_expression.rds"
    input_svg <- "anatomical_map.svg"
    
    if (!file.exists(input_expression)) {
      stop(paste("Required input file missing:", input_expression))
    }
    if (!file.exists(input_svg)) {
      stop(paste("Required input file missing:", input_svg))
    }
    
    # --- Load User Input Data ---
    message("Loading input expression data and anatomical map...")
    rse.mus <- readRDS(input_expression)
    svg.mus <- read_svg(input_svg)
    
    # --- Subset spatial features and variables of interest using ---
    message("Subsetting spatial features and variables...")
    sub.mus <- sf_var(
      data = rse.mus, 
      feature = 'organism_part', 
      ft.sel = c('brain', 'lung', 'colon', 'kidney', 'liver'), 
      variable = 'strain', 
      var.sel = c('DBA.2J', 'C57BL.6', 'CD1'), 
      com.by = 'ft'
    )
    
    # --- Filter low-expression data using filter_data ---
    message("Filtering low-expression data...")
    sub.mus.fil <- filter_data(
      data = sub.mus, 
      pOA = c(0.5, 15), 
      CV = c(0.8, 100), 
      verbose = FALSE
    )
    
    # --- Perform spatial enrichment analysis using spatial_enrich ---
    message("Performing spatial enrichment analysis...")
    enr.res <- spatial_enrich(
      sub.mus.fil, 
      method = c('edgeR'), 
      norm = 'TMM', 
      log2.fc = 1, 
      fdr = 0.05, 
      outliers = 1
    )
    
    # Save enrichment results object
    saveRDS(enr.res, "spatial_enrichment_results.rds")
    
    # --- Visualize enrichment overlaps across features using ---
    message("Visualizing enrichment overlaps...")
    pdf("enrichment_overlap_upset.pdf", width = 10, height = 8)
    tryCatch({
      ovl_enrich(enr.res, type = 'up', plot = 'upset')
    }, error = function(e) {
      message("Warning: ovl_enrich failed to plot. Continuing pipeline. Error: ", e\$message)
    })
    dev.off()
    
    # --- Query enriched/depleted genes for a target tissue using ---
    message("Querying enriched genes for brain...")
    en.brain <- query_enrich(enr.res, 'brain')
    
    # Save queried brain enrichment results and export to CSV
    saveRDS(en.brain, "brain_enrichment_query.rds")
    write.csv(as.data.frame(rowData(en.brain)), "brain_enrichment_table.csv", row.names = TRUE)
    
    # --- Plot enrichment spatial heatmaps using shm ---
    message("Generating spatial heatmaps...")
    dat.enrich <- SPHM(svg = svg.mus, bulk = en.brain)
    
    pdf("spatial_heatmap_enrichment.pdf", width = 12, height = 10)
    shm(
      data = dat.enrich, 
      ID = c('Kif5c', 'Cdhr5'), 
      legend.r = 1, 
      legend.nrow = 7, 
      sub.title.size = 15, 
      ncol = 3, 
      bar.width = 0.09, 
      lay.shm = 'gene'
    )
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT":',
        paste0('        spatialHeatmap: ', as.character(packageVersion("spatialHeatmap")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_enrichment.csv versions.yml
    """
}

workflow BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bulk_expression.rds, anatomical_map.svg ] ]

    main:
    BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT.out.tables
    plots    = BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT.out.plots
    objects  = BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT.out.objects
    versions = BIOC_SPATIALHEATMAP_SPATIAL_ENRICHMENT.out.versions
}
