#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clumsid — lc_ms2_lowres
// Extract, merge, and cluster MS2 spectra from low-resolution LC-MS/MS data.
// Input: PA14_amazon_lowres.mzXML
// Container: quay.io/biocontainers/bioconductor-clumsid:1.26.0--r45hdfd78af_0
// R packages: CluMSID
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: MDS plot, heatmap

nextflow.enable.dsl = 2

process BIOC_CLUMSID_LC_MS2_LOWRES {
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
    .bm_deps <- c("CluMSID")
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
    library(CluMSID)
    
    # Define the input file from the working directory
    lowresfile <- "PA14_amazon_lowres.mzXML"
    
    # Check if the input file exists
    if (!file.exists(lowresfile)) {
      stop(paste("Required input file missing:", lowresfile))
    }
    
    # --- Extract MS2 spectra ---
    message("Extracting MS2 spectra...")
    ms2list <- extractMS2spectra(lowresfile)
    
    # Save the extracted MS2 spectra list
    saveRDS(ms2list, "extracted_ms2_spectra.rds")
    
    # --- Merge redundant spectra with a low-resolution mass ---
    message("Merging MS2 spectra...")
    featlist <- mergeMS2spectra(ms2list, mz_tolerance = 0.02)
    
    # Save the merged feature list
    saveRDS(featlist, "merged_features.rds")
    tryCatch({
      writeFeaturelist(featlist, "feature_list.csv")
    }, error = function(e) {
      message("Could not write feature list CSV: ", e\$message)
    })
    
    # --- Generate a distance matrix ---
    message("Generating distance matrix...")
    distmat <- distanceMatrix(featlist)
    
    # Save the distance matrix
    saveRDS(distmat, "distance_matrix.rds")
    write.csv(as.matrix(distmat), "distance_matrix.csv")
    
    # --- Visualize similarities and save plots to PDF ---
    message("Generating plots...")
    
    # MDS Plot
    pdf("MDS_plot.pdf", width = 8, height = 8)
    MDSplot(distmat)
    dev.off()
    
    # Heatmap Plot
    pdf("HC_heatmap.pdf", width = 10, height = 10)
    HCplot(distmat, type = "heatmap", cexRow = 0.1, cexCol = 0.1, margins = c(6, 6))
    dev.off()
    
    # Dendrogram Plot
    pdf("HC_dendrogram.pdf", width = 12, height = 12)
    HCplot(distmat, h = 0.8, cex = 0.3)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CLUMSID_LC_MS2_LOWRES":',
        paste0('        clumsid: ', as.character(packageVersion("clumsid")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms2_lowres.csv versions.yml
    """
}

workflow BIOC_CLUMSID_LC_MS2_LOWRES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PA14_amazon_lowres.mzXML ] ]

    main:
    BIOC_CLUMSID_LC_MS2_LOWRES(ch_input)

    emit:
    tables   = BIOC_CLUMSID_LC_MS2_LOWRES.out.tables
    plots    = BIOC_CLUMSID_LC_MS2_LOWRES.out.plots
    objects  = BIOC_CLUMSID_LC_MS2_LOWRES.out.objects
    versions = BIOC_CLUMSID_LC_MS2_LOWRES.out.versions
}
