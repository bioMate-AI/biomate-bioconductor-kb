#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: norce — biotype_analysis
// Filter and extract biotype-specific gene lists from GTF files.
// Input: temp.gtf
// Container: quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0
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
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
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
    
    # 1. Filter GTF file for specific biotypes using filterBiotype
    biotypes <- c('unprocessed_pseudogene', 'transcribed_unprocessed_pseudogene')
    extrResult <- filterBiotype(fileImport, biotypes)
    
    # 2. Extract gene-biotype relationships using extractBiotype
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORCE_BIOTYPE_ANALYSIS":
        norce: \$(Rscript -e 'cat(as.character(packageVersion("norce")))')
    END_VERSIONS
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
