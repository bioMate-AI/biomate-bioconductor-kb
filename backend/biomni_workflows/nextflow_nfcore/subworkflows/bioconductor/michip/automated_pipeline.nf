#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: michip — automated_pipeline
// Run an automated, all-in-one pipeline that parses, filters, corrects, normalizes, and exports MiChip data and diagnostic plots using a single wrapper function.
// Input: B_676.gpr, B_677.gpr
// Container: quay.io/biocontainers/bioconductor-michip:1.64.0--r45hdfd78af_0
// R packages: MiChip
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICHIP_AUTOMATED_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-michip:1.64.0--r45hdfd78af_0"

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
    .bm_deps <- c("MiChip")
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
    library(MiChip)
    
    # Define the directory containing the user input files (B_676.gpr and B_677.gpr)
    datadir <- "."
    
    # Run the automated pipeline wrapper function exactly as documented
    myNormedEset <- workedExampleMedianNormalize("NormedDemo", intensityCutoff = 50, datadir)
    
    # Save the resulting ExpressionSet object to an RDS file
    saveRDS(myNormedEset, file = "myNormedEset.rds")
    
    # Export the normalized expression matrix to a CSV file
    write.csv(exprs(myNormedEset), file = "NormedDemo_expression_matrix.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_MICHIP_AUTOMATED_PIPELINE":',
        paste0('        michip: ', as.character(packageVersion("michip")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_pipeline.csv versions.yml
    """
}

workflow BIOC_MICHIP_AUTOMATED_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ B_676.gpr, B_677.gpr ] ]

    main:
    BIOC_MICHIP_AUTOMATED_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MICHIP_AUTOMATED_PIPELINE.out.tables
    plots    = BIOC_MICHIP_AUTOMATED_PIPELINE.out.plots
    objects  = BIOC_MICHIP_AUTOMATED_PIPELINE.out.objects
    versions = BIOC_MICHIP_AUTOMATED_PIPELINE.out.versions
}
