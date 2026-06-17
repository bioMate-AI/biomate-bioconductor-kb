#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rarevariantvis — multiple_sample_visualization
// Simultaneously visualize rare variants from multiple genome samples in a single interactive plot.
// Input: RareVariants_CoriellIndex_S1.txt, RareVariants_Coriell_S2.txt
// Container: quay.io/biocontainers/bioconductor-rarevariantvis:2.38.0--r45hdfd78af_0
// R packages: RareVariantVis
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rarevariantvis:2.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("RareVariantVis")
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
    
    # Ensure the required package is loaded
    if (!requireNamespace("RareVariantVis", quietly = TRUE)) {
      stop("The 'RareVariantVis' package is required but not installed.")
    }
    library(RareVariantVis)
    
    # Define the input files expected in the working directory
    inputFiles = c("RareVariants_CoriellIndex_S1.txt",
                   "RareVariants_Coriell_S2.txt")
    
    # Verify that the user-provided input files exist before proceeding
    missing_files <- inputFiles[!file.exists(inputFiles)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input file(s) in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # Define the sample names corresponding to the input files
    sampleNames = c("CoriellIndex_S1", "Coriell_S2")
    
    # Run the multiple sample visualization for chromosome 19
    # This generates an interactive HTML visualization named "CorielSamples.html"
    multipleVis(inputFiles, "CorielSamples.html", sampleNames, "19")
    
    # Verify the output file was successfully created
    if (file.exists("CorielSamples.html")) {
      cat("Successfully generated multiple sample visualization: CorielSamples.html\n")
    } else {
      stop("Error: 'CorielSamples.html' was not generated.")
    }

    writeLines(c(
        '"BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION":',
        paste0('        rarevariantvis: ', as.character(packageVersion("rarevariantvis")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_sample_visualization.csv versions.yml
    """
}

workflow BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RareVariants_CoriellIndex_S1.txt, RareVariants_Coriell_S2.txt ] ]

    main:
    BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION.out.tables
    plots    = BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION.out.plots
    objects  = BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION.out.objects
    versions = BIOC_RAREVARIANTVIS_MULTIPLE_SAMPLE_VISUALIZATION.out.versions
}
