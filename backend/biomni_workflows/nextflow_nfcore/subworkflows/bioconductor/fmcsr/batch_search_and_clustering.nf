#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fmcsr — batch_search_and_clustering
// Perform batch FMCS searches against a compound collection and cluster them based on structural similarity.
// Input: sdfsample.sdf
// Container: quay.io/biocontainers/bioconductor-fmcsr:1.52.0--r45ha27e39d_0
// R packages: ChemmineR, fmcsR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: dendrogram

nextflow.enable.dsl = 2

process BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-fmcsr:1.52.0--r45ha27e39d_0"

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
    .bm_deps <- c("ChemmineR", "fmcsR")
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
    library("ChemmineR")
    library("fmcsR")
    
    # --- Load a collection of compounds from the user-provided SDF ---
    input_file <- "sdfsample.sdf"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    sdf <- read.SDFset(input_file)
    
    # --- Perform batch FMCS search of a query compound against the ---
    # (Using the exact documented call)
    batch_result <- fmcsBatch(sdf[1], sdf[1:30], au=0, bu=0)
    write.csv(batch_result, "batch_fmcs_result.csv", row.names = TRUE)
    
    # --- Compute an all-against-all similarity matrix ---
    # (Using the exact documented call on the first 7 compounds)
    sdf <- sdf[1:7]
    d <- sapply(cid(sdf), function(x) fmcsBatch(sdf[x], sdf, au=0, bu=0, matching.mode="aromatic")[,"Overlap_Coefficient"])
    write.csv(d, "similarity_matrix.csv", row.names = TRUE)
    saveRDS(d, "similarity_matrix.rds")
    
    # --- Perform hierarchical clustering and plot the dendrogram ---
    hc <- hclust(as.dist(1-d), method="complete")
    saveRDS(hc, "hc_model.rds")
    
    pdf("dendrogram.pdf", width = 8, height = 6)
    plot(as.dendrogram(hc), edgePar=list(col=4, lwd=2), horiz=TRUE)
    dev.off()
    
    # --- Visualize the MCS of the two most similar compounds ---
    pdf("mcs_plot.pdf", width = 10, height = 8)
    plotMCS(fmcs(sdf[3], sdf[7], au=0, bu=0, matching.mode="aromatic"))
    dev.off()

    writeLines(c(
        '"BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING":',
        paste0('        fmcsr: ', as.character(packageVersion("fmcsr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_search_and_clustering.csv versions.yml
    """
}

workflow BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sdfsample.sdf ] ]

    main:
    BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING.out.tables
    plots    = BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING.out.plots
    objects  = BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING.out.objects
    versions = BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING.out.versions
}
