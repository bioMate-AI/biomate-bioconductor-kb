#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: acme — tiling_microarray_enrichment_analysis
// Identify, visualize, and export genomic regions of enrichment from tiling microarray GFF files.
// Input: fnames
// Container: quay.io/biocontainers/bioconductor-acme:2.62.0--r44h3df3fcb_0
// R packages: ACME
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-acme:2.62.0--r44h3df3fcb_0"

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
    .bm_deps <- c("ACME")
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
    
    # Load the required library
    library(ACME)
    
    # --- Read GFF files from the working directory ---
    # Identify GFF files in the current working directory
    fnames <- list.files(pattern = "\\\\.gff\$", ignore.case = TRUE)
    
    if (length(fnames) == 0) {
      stop("Error: No GFF files found in the working directory. Please provide GFF files.")
    }
    
    # Read the GFF files to construct the ACMESet object
    example.agff <- read.resultsGFF(fnames, path = ".")
    print(example.agff)
    
    # --- Calculate enrichment probabilities ---
    calc <- do.aGFF.calc(example.agff, window = 1000, thresh = 0.95)
    
    # --- Plot results for a specific chromosome and sample ---
    # Save the plot to a PDF file.
    # A tryCatch block is used to handle cases where 'chr1' might not be present in the user's GFF files.
    pdf("acme_plot.pdf")
    tryCatch({
      plot(calc, chrom = 'chr1', sample = 1)
    }, error = function(e) {
      message("Warning: Failed to plot for chrom='chr1' and sample=1. Error: ", e\$message)
    })
    dev.off()
    
    # --- Identify significant regions of enrichment ---
    regs <- findRegions(calc)
    if (!is.null(regs) && nrow(regs) > 0) {
      print(regs[1:min(5, nrow(regs)), , drop = FALSE])
      write.csv(regs, file = "regions_of_enrichment.csv", row.names = TRUE)
    } else {
      message("No regions of enrichment found.")
    }
    
    # --- Export results to SGR and bedGraph formats ---
    # Write both calculated values and raw data
    write.sgr(calc)
    
    # Write only calculated data
    write.sgr(calc, raw = FALSE)
    
    # Export to UCSC genome browser bedGraph format
    write.bedGraph(calc)
    
    # Save the calculated ACMESet object for downstream analysis
    saveRDS(calc, file = "acme_calc.rds")

    writeLines(c(
        '"BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS":',
        paste0('        acme: ', as.character(packageVersion("acme")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tiling_microarray_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fnames ] ]

    main:
    BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_ACME_TILING_MICROARRAY_ENRICHMENT_ANALYSIS.out.versions
}
