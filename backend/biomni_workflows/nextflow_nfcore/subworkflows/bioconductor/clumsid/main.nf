#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clumsid — di_ms2_highres
// Extract, merge, and cluster MS2 spectra from high-resolution Direct Infusion (DI-MS/MS) data.
// Input: PA14_maxis_DI.mzXML
// Container: quay.io/biocontainers/bioconductor-clumsid:1.26.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUMSID_DI_MS2_HIGHRES {
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
    .bm_deps <- c("clumsid", "clumsiddata", "magrittr", "metams", "metamsdata")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(CluMSID)
    
    # Define the input file from the working directory
    DIfile <- "PA14_maxis_DI.mzXML"
    
    # Check if the input file exists
    if (!file.exists(DIfile)) {
      stop(paste("Required input file missing:", DIfile))
    }
    
    # 1. Extract MS2 spectra
    message("Extracting MS2 spectra...")
    ms2list <- extractMS2spectra(DIfile)
    
    # 2. Merge redundant spectra with a tight retention time tolerance
    message("Merging MS2 spectra...")
    featlist <- mergeMS2spectra(ms2list, rt_tolerance = 1)
    
    # 3. Generate a spectral similarity distance matrix
    message("Generating distance matrix...")
    distmat <- distanceMatrix(featlist)
    
    # Save the distance matrix and feature list to disk
    message("Saving results to disk...")
    saveRDS(featlist, "merged_features.rds")
    saveRDS(distmat, "distance_matrix.rds")
    
    # Export distance matrix as a CSV table
    write.csv(as.matrix(distmat), "distance_matrix.csv", row.names = TRUE)
    
    # 4. Visualize similarities with a circularized dendrogram
    message("Generating circularized dendrogram plot...")
    pdf("HCplot_dendrogram.pdf", width = 10, height = 10)
    HCplot(distmat, cex = 0.5)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: 'merged_features.rds', 'distance_matrix.rds', 'distance_matrix.csv', and 'HCplot_dendrogram.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CLUMSID_DI_MS2_HIGHRES":
        clumsid: \$(Rscript -e 'cat(as.character(packageVersion("clumsid")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_di_ms2_highres.csv versions.yml
    """
}

workflow BIOC_CLUMSID_DI_MS2_HIGHRES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PA14_maxis_DI.mzXML ] ]

    main:
    BIOC_CLUMSID_DI_MS2_HIGHRES(ch_input)

    emit:
    tables   = BIOC_CLUMSID_DI_MS2_HIGHRES.out.tables
    plots    = BIOC_CLUMSID_DI_MS2_HIGHRES.out.plots
    objects  = BIOC_CLUMSID_DI_MS2_HIGHRES.out.objects
    versions = BIOC_CLUMSID_DI_MS2_HIGHRES.out.versions
}
