#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fmcsr — batch_search_and_clustering
// Perform batch FMCS searches against a compound collection and cluster them based on structural similarity.
// Input: sdfsample.sdf
// Container: quay.io/biocontainers/bioconductor-fmcsr:1.52.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

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
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library("ChemmineR")
    library("fmcsR")
    
    # 1. Load a collection of compounds from the user-provided SDF file
    input_file <- "sdfsample.sdf"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    sdf <- read.SDFset(input_file)
    
    # 2. Perform batch FMCS search of a query compound against the collection
    # (Using the exact documented call)
    batch_result <- fmcsBatch(sdf[1], sdf[1:30], au=0, bu=0)
    write.csv(batch_result, "batch_fmcs_result.csv", row.names = TRUE)
    
    # 3. Compute an all-against-all similarity matrix
    # (Using the exact documented call on the first 7 compounds)
    sdf <- sdf[1:7]
    d <- sapply(cid(sdf), function(x) fmcsBatch(sdf[x], sdf, au=0, bu=0, matching.mode="aromatic")[,"Overlap_Coefficient"])
    write.csv(d, "similarity_matrix.csv", row.names = TRUE)
    saveRDS(d, "similarity_matrix.rds")
    
    # 4. Perform hierarchical clustering and plot the dendrogram
    hc <- hclust(as.dist(1-d), method="complete")
    saveRDS(hc, "hc_model.rds")
    
    pdf("dendrogram.pdf", width = 8, height = 6)
    plot(as.dendrogram(hc), edgePar=list(col=4, lwd=2), horiz=TRUE)
    dev.off()
    
    # 5. Visualize the MCS of the two most similar compounds (sdf[3] and sdf[7])
    pdf("mcs_plot.pdf", width = 10, height = 8)
    plotMCS(fmcs(sdf[3], sdf[7], au=0, bu=0, matching.mode="aromatic"))
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_FMCSR_BATCH_SEARCH_AND_CLUSTERING":
        fmcsr: \$(Rscript -e 'cat(as.character(packageVersion("fmcsr")))')
    END_VERSIONS
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
