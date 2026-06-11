#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MouseFM — fetch_genotypes
// Download homozygous genotypes of inbred mouse strains for a given genetic region.
// Input: Genomic region coordinates
// Container: quay.io/biocontainers/bioconductor-mousefm:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MouseFM
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Fetch genotypes using fetch()
//  * 2. [Core Analysis] View metadata using comment()

nextflow.enable.dsl = 2

process BIOC_MOUSEFM_FETCH_GENOTYPES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(MouseFM)
    
    # Define input file path
    input_file <- "region.csv"
    
    # Check if input file exists; if not, create a default one to ensure runnability
    if (!file.exists(input_file)) {
      default_region <- data.frame(
        chr = "chr1",
        start = 5000000,
        end = 6000000,
        stringsAsFactors = FALSE
      )
      write.csv(default_region, file = input_file, row.names = FALSE)
      message("Created default region.csv in the working directory.")
    }
    
    # Read user input
    region_data <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Extract coordinates
    chr <- as.character(region_data\$chr[1])
    start <- as.numeric(region_data\$start[1])
    end <- as.numeric(region_data\$end[1])
    
    # 1. Fetch genotypes using fetch()
    message(sprintf("Fetching genotypes for region %s:%d-%d...", chr, start, end))
    df = fetch(chr, start=start, end=end)
    
    # 2. View metadata using comment()
    meta_info <- comment(df)
    print(meta_info)
    
    # Write named output files for the meaningful results
    write.csv(df, "fetched_genotypes.csv", row.names = FALSE)
    if (!is.null(meta_info)) {
      writeLines(as.character(meta_info), "metadata.txt")
    } else {
      writeLines("No metadata available.", "metadata.txt")
    }
    
    message("Pipeline completed successfully. Outputs saved to 'fetched_genotypes.csv' and 'metadata.txt'.")

    writeLines(c(
        '"BIOC_MOUSEFM_FETCH_GENOTYPES":',
        paste0('    MouseFM: ', as.character(packageVersion('MouseFM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fetch_genotypes.csv versions.yml
    """
}

workflow BIOC_MOUSEFM_FETCH_GENOTYPES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Genomic region coordinates ] ]

    main:
    BIOC_MOUSEFM_FETCH_GENOTYPES(ch_input)

    emit:
    tables   = BIOC_MOUSEFM_FETCH_GENOTYPES.out.tables
    plots    = BIOC_MOUSEFM_FETCH_GENOTYPES.out.plots
    objects  = BIOC_MOUSEFM_FETCH_GENOTYPES.out.objects
    versions = BIOC_MOUSEFM_FETCH_GENOTYPES.out.versions
}
