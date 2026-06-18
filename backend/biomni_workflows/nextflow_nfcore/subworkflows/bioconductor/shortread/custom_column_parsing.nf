#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ShortRead — custom_column_parsing
// Read specific columns of sequence and quality data from text-based export files into memory-efficient DNAStringSet and BStringSet objects.
// Input: export_file.txt
// Container: quay.io/biocontainers/bioconductor-shortread:1.68.0--r45ha27e39d_0
// R packages: ShortRead
// Bioconductor: 3.20 | R: 4.4
// Requires: ShortRead
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the path to the tabular text file
//  * 2. [Input & Preparation] Set up a colClasses list specifying which columns to read as DNAString or BString and which to ignore
//  * 3. [Input & Preparation] Read the specified columns into memory-efficient XStringSet objects using readXStringColumns

nextflow.enable.dsl = 2

process BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING {
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
    .bm_deps <- c("ShortRead")
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
    library(ShortRead)
    
    # 1. Define the path to the tabular text file
    # The pipeline expects 'export_file.txt' in the working directory.
    if (!file.exists("export_file.txt")) {
      stop("Error: 'export_file.txt' not found in the working directory.")
    }
    
    # Define the path and pattern directly
    dirPath <- "."
    pattern <- "export_file.txt"
    
    # 2. Set up a colClasses list specifying which columns to read as DNAString or BString and which to ignore
    colClasses <- rep(list(NULL), 21)
    colClasses[9:10] <- c("DNAString", "BString")
    names(colClasses)[9:10] <- c("read", "quality")
    
    # 3. Read the specified columns into memory-efficient XStringSet objects using readXStringColumns
    cols <- readXStringColumns(dirPath, pattern, colClasses)
    
    # Write meaningful outputs
    saveRDS(cols, "parsed_columns.rds")
    
    # Export to CSV for downstream compatibility
    output_df <- data.frame(
      read = as.character(cols\$read),
      quality = as.character(cols\$quality),
      stringsAsFactors = FALSE
    )
    write.csv(output_df, "parsed_columns.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING":',
        paste0('    ShortRead: ', as.character(packageVersion('ShortRead')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_column_parsing.csv versions.yml
    """
}

workflow BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ export_file.txt ] ]

    main:
    BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING(ch_input)

    emit:
    tables   = BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING.out.tables
    plots    = BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING.out.plots
    objects  = BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING.out.objects
    versions = BIOC_SHORTREAD_CUSTOM_COLUMN_PARSING.out.versions
}
