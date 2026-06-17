#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: norce — biotype_analysis
// Filter and extract biotype-specific gene lists from GTF files.
// Input: temp.gtf
// Container: quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0
// R packages: NoRCE
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORCE_BIOTYPE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("NoRCE")
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
    if (!requireNamespace("NoRCE", quietly = TRUE)) {
      stop("Package 'NoRCE' is required but not installed.")
    }
    library(NoRCE)
    
    # Define input file from the working directory
    fileImport <- "temp.gtf"
    
    # Verify that the user input file exists
    if (!file.exists(fileImport)) {
      stop(paste("Required input file '", fileImport, "' is missing from the working directory.", sep = ""))
    }
    
    # --- Filter GTF file for specific biotypes using filterBiotype ---
    biotypes <- c('unprocessed_pseudogene', 'transcribed_unprocessed_pseudogene')
    extrResult <- filterBiotype(fileImport, biotypes)
    
    # --- Extract gene-biotype relationships using extractBiotype ---
    gtf <- extractBiotype(gtfFile = fileImport)
    
    # Save results to RDS objects
    saveRDS(extrResult, "extrResult.rds")
    saveRDS(gtf, "gtf_biotype_matrix.rds")
    
    # Attempt to save results as CSV tables for easier inspection
    tryCatch({
      if (is.data.frame(extrResult) || is.matrix(extrResult)) {
        write.csv(extrResult, "extrResult.csv", row.names = FALSE)
      } else if (is.list(extrResult)) {
        for (name in names(extrResult)) {
          if (is.data.frame(extrResult[[name]]) || is.matrix(extrResult[[name]])) {
            write.csv(extrResult[[name]], paste0("extrResult_", name, ".csv"), row.names = FALSE)
          }
        }
      }
    }, error = function(e) {
      warning("Could not write extrResult to CSV: ", e\$message)
    })
    
    tryCatch({
      if (is.data.frame(gtf) || is.matrix(gtf)) {
        write.csv(gtf, "gtf_biotype_matrix.csv", row.names = TRUE)
      }
    }, error = function(e) {
      warning("Could not write gtf to CSV: ", e\$message)
    })
    
    message("Workflow completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_NORCE_BIOTYPE_ANALYSIS":',
        paste0('        norce: ', as.character(packageVersion("norce")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biotype_analysis.csv versions.yml
    """
}

workflow BIOC_NORCE_BIOTYPE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ temp.gtf ] ]

    main:
    BIOC_NORCE_BIOTYPE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NORCE_BIOTYPE_ANALYSIS.out.tables
    plots    = BIOC_NORCE_BIOTYPE_ANALYSIS.out.plots
    objects  = BIOC_NORCE_BIOTYPE_ANALYSIS.out.objects
    versions = BIOC_NORCE_BIOTYPE_ANALYSIS.out.versions
}
