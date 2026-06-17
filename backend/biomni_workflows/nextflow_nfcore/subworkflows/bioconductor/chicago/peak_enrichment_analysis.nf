#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chicago — peak_enrichment_analysis
// Test whether the non-bait interaction ends (other ends) of called interactions are enriched for specific genomic features (e.g., chromatin marks).
// Input: cd, featuresGM.txt, spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak
// Container: quay.io/biocontainers/bioconductor-chicago:1.38.0--r45hdfd78af_0
// R packages: Chicago
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chicago:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("Chicago")
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
    library(Chicago)
    
    # --- Load the processed chicagoData object from the working ---
    if (file.exists("cd")) {
      cd <- readRDS("cd")
    } else if (file.exists("cd.rds")) {
      cd <- readRDS("cd.rds")
    } else {
      stop("Error: Processed chicagoData object 'cd' or 'cd.rds' not found in the working directory.")
    }
    
    # --- Set up the features folder and list ---
    featuresFolder <- "."
    
    # Read the features mapping file
    if (!file.exists("featuresGM.txt")) {
      stop("Error: 'featuresGM.txt' not found in the working directory.")
    }
    featuresTable <- read.delim("featuresGM.txt", header=FALSE, as.is=TRUE)
    
    # Filter featuresTable to only include files that actually exist in the working directory
    existing_files <- list.files(featuresFolder)
    featuresTable <- featuresTable[featuresTable\$V2 %in% existing_files, , drop=FALSE]
    
    if (nrow(featuresTable) == 0) {
      stop("Error: None of the feature files listed in 'featuresGM.txt' exist in the working directory.")
    }
    
    featuresList <- as.list(featuresTable\$V2)
    names(featuresList) <- featuresTable\$V1
    
    # --- Calculate the appropriate number of distance bins based ---
    no_bins <- ceiling(max(abs(intData(cd)\$distSign), na.rm = TRUE)/1e4)
    
    # --- Run permutation-based enrichment testing and save the ---
    pdf("peak_enrichment_plot.pdf", width=12, height=7)
    enrichmentResults <- peakEnrichment4Features(cd, folder=featuresFolder, list_frag=featuresList, no_bins=no_bins, sample_number=100)
    dev.off()
    
    # --- Save the meaningful results to disk ---
    write.csv(as.data.frame(enrichmentResults), "enrichment_results.csv", row.names=TRUE)
    saveRDS(enrichmentResults, "enrichment_results.rds")

    writeLines(c(
        '"BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS":',
        paste0('        chicago: ', as.character(packageVersion("chicago")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cd, featuresGM.txt, spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak ] ]

    main:
    BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_CHICAGO_PEAK_ENRICHMENT_ANALYSIS.out.versions
}
