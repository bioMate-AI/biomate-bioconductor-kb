#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — proximity_analysis
// Test if genomic regions tend to be closer to or farther from transcription start sites or enhancer regions for each gene set.
// Input: peaks_E2F4.bed, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_PROXIMITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("chipenrich")
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
    
    # Load required library
    library(chipenrich)
    
    # --- Define the path to the gene sets file and load the peaks ---
    # Read the user-provided peaks file and format it as a data.frame with required columns
    peaks_df = read.table("peaks_E2F4.bed", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
    colnames(peaks_df)[1:3] = c("chrom", "start", "end")
    peaks_E2F4 = peaks_df
    
    # Define the path to the gene sets file
    gs_path = "vignette_genesets.txt"
    
    # --- Run proxReg() to calculate peak-to-TSS/enhancer distances ---
    results.prox = proxReg(peaks_E2F4, reglocation = 'tss',	genome = 'hg19', genesets=gs_path, out_name=NULL)
    
    # --- Extract and inspect the proximity results ---
    results.prox = results.prox\$results
    print(results.prox[1:5,1:7])
    
    # Write named output files for the meaningful results
    write.csv(results.prox, "proximity_analysis_results.csv", row.names = FALSE)
    saveRDS(results.prox, "proximity_analysis_results.rds")

    writeLines(c(
        '"BIOC_CHIPENRICH_PROXIMITY_ANALYSIS":',
        paste0('        chipenrich: ', as.character(packageVersion("chipenrich")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proximity_analysis.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_PROXIMITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4.bed, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_PROXIMITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_PROXIMITY_ANALYSIS.out.tables
    plots    = BIOC_CHIPENRICH_PROXIMITY_ANALYSIS.out.plots
    objects  = BIOC_CHIPENRICH_PROXIMITY_ANALYSIS.out.objects
    versions = BIOC_CHIPENRICH_PROXIMITY_ANALYSIS.out.versions
}
