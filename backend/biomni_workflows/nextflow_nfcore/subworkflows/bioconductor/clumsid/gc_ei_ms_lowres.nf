#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clumsid — gc_ei_ms_lowres
// Extract, annotate, and cluster MS1 pseudospectra from low-resolution GC-EI-MS data using CAMERA and metaMS.
// Input: 1800802_TD_pool_total_1.cdf, GC_post.csv
// Container: quay.io/biocontainers/bioconductor-clumsid:1.26.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUMSID_GC_EI_MS_LOWRES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-clumsid:1.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("CluMSID", "metaMS", "metaMSdata", "xcms")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(CluMSID)
    library(metaMS)
    library(metaMSdata)
    library(xcms)
    
    # Define input files from the working directory
    pool <- "1800802_TD_pool_total_1.cdf"
    annolist_file <- "GC_post.csv"
    
    # Verify that the required input files exist
    if (!file.exists(pool)) {
      stop(paste("Required input file missing:", pool))
    }
    if (!file.exists(annolist_file)) {
      stop(paste("Required input file missing:", annolist_file))
    }
    
    # 1. Run peak picking and CAMERA annotation using metaMS::runCAMERA()
    # TSQXLS.GC is lazy-loaded from the metaMSdata package
    xA <- metaMS::runCAMERA(xcms::xcmsSet(pool), chrom = "GC", settings = metaMS::metaSetting(TSQXLS.GC, "CAMERA"))
    
    # 2. Extract pseudospectra using extractPseudospectra()
    pslist <- extractPseudospectra(xA, min_peaks = 0)
    saveRDS(pslist, "pslist.rds")
    
    # 3. Export feature list for manual annotation using writeFeaturelist()
    writeFeaturelist(pslist, "GC_pre.csv")
    
    # 4. Plot individual pseudospectra using specplot()
    pdf("specplot_27.pdf")
    specplot(pslist[[27]])
    dev.off()
    
    # 5. Add external annotations using addAnnotations()
    apslist <- addAnnotations(featlist = pslist, annolist = annolist_file)
    saveRDS(apslist, "apslist.rds")
    
    # 6. Generate a distance matrix with low-resolution mass tolerance using distanceMatrix()
    pseudodistmat <- distanceMatrix(apslist, mz_tolerance = 0.02)
    saveRDS(pseudodistmat, "pseudodistmat.rds")
    
    # 7. Visualize similarities using heatmaps, dendrograms, and correlation networks using HCplot() and networkplot()
    pdf("HCplot_heatmap.pdf")
    HCplot(pseudodistmat, type = "heatmap", cexRow = 0.4, cexCol = 0.4, margins = c(7, 7))
    dev.off()
    
    pdf("networkplot_default.pdf")
    networkplot(pseudodistmat, highlight_annotated = TRUE, show_labels = TRUE, exclude_singletons = TRUE)
    dev.off()
    
    pdf("networkplot_min_sim_0.4.pdf")
    networkplot(pseudodistmat, highlight_annotated = TRUE, show_labels = TRUE, exclude_singletons = TRUE, min_similarity = 0.4)
    dev.off()
    
    pdf("HCplot_dendrogram.pdf")
    HCplot(pseudodistmat, h = 0.7, cex = 0.5)
    dev.off()
    
    # 8. Search for specific diagnostic fragment ions using findFragment()
    fragmentlist <- findFragment(apslist, mz = 315, tolerance = 0.5 / 315)
    saveRDS(fragmentlist, "fragmentlist.rds")
    
    fragment_ids <- vapply(X = fragmentlist, FUN = accessID, FUN.VALUE = integer(1))
    write.csv(data.frame(Fragment_IDs = fragment_ids), "fragment_ids.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CLUMSID_GC_EI_MS_LOWRES":
        clumsid: \$(Rscript -e 'cat(as.character(packageVersion("clumsid")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gc_ei_ms_lowres.csv versions.yml
    """
}

workflow BIOC_CLUMSID_GC_EI_MS_LOWRES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 1800802_TD_pool_total_1.cdf, GC_post.csv ] ]

    main:
    BIOC_CLUMSID_GC_EI_MS_LOWRES(ch_input)

    emit:
    tables   = BIOC_CLUMSID_GC_EI_MS_LOWRES.out.tables
    plots    = BIOC_CLUMSID_GC_EI_MS_LOWRES.out.plots
    objects  = BIOC_CLUMSID_GC_EI_MS_LOWRES.out.objects
    versions = BIOC_CLUMSID_GC_EI_MS_LOWRES.out.versions
}
