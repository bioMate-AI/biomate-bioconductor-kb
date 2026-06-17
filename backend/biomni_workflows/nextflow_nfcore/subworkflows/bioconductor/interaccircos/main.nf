#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: interacCircos — interactive_circos_histogram
// Create an interactive Circos plot displaying a genomic histogram track.
// Input: histogram_data.csv
// Container: quay.io/biocontainers/bioconductor-interaccircos:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: htmlwidgets, interacCircos
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the interacCircos library
//  * 2. [Input & Preparation] Load the histogram data
//  * 3. [Visualization & Output] Generate the interactive Circos plot with CircosHistogram and Circos

nextflow.enable.dsl = 2

process BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("interacCircos")
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
    
    # 1. Load the interacCircos library
    library(interacCircos)
    
    # 2. Load the histogram data from the declared user input file
    histogramData <- read.csv("histogram_data.csv", stringsAsFactors = FALSE)
    
    # 3. Generate the interactive Circos plot with CircosHistogram and Circos
    # Keeping every documented function call and argument name EXACTLY as shown
    circos_plot <- Circos(moduleList=CircosHistogram('HISTOGRAM01', data = histogramData,
          fillColor= "#ff7f0e",maxRadius = 210,minRadius = 175,
          animationDisplay = TRUE),genome=list("2L"=23011544,"2R"=21146708,"3L"=24543557,"3R"= 27905053,"X"=22422827,"4"=1351857),
          outerRadius = 220, width = 700,height = 550)
    
    # 4. Write named output files for the meaningful results
    saveRDS(circos_plot, "interactive_circos_histogram.rds")
    
    # Save the interactive HTML widget
    tryCatch({
      htmlwidgets::saveWidget(circos_plot, "interactive_circos_histogram.html", selfcontained = TRUE)
    }, error = function(e) {
      message("HTML widget saving failed, but RDS was successfully saved. Error: ", e\$message)
    })

    writeLines(c(
        '"BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM":',
        paste0('    interacCircos: ', as.character(packageVersion('interacCircos')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_circos_histogram.csv versions.yml
    """
}

workflow BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ histogram_data.csv ] ]

    main:
    BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM(ch_input)

    emit:
    tables   = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM.out.tables
    plots    = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM.out.plots
    objects  = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM.out.objects
    versions = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_HISTOGRAM.out.versions
}
