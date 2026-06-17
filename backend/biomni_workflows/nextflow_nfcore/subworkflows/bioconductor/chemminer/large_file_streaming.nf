#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChemmineR — large_file_streaming
// Stream through massive SD files to compute descriptors and retrieve specific compounds without loading the entire file into memory.
// Input: test.sdf
// Container: quay.io/biocontainers/bioconductor-chemminer:3.62.0--r45ha27e39d_0
// R packages: ChemmineR
// Bioconductor: 3.20 | R: 4.4
// Requires: ChemmineR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a descriptor extraction function
//  * 2. [Visualization & Output] Stream through the file and write descriptors to a tabular file using sdfStream
//  * 3. [Core Analysis] Filter the generated index based on property criteria
//  * 4. [Input & Preparation] Retrieve target molecules from the original file using read.SDFindex

nextflow.enable.dsl = 2

process BIOC_CHEMMINER_LARGE_FILE_STREAMING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ChemmineR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(ChemmineR)
    
    # Define descriptor set function exactly as documented
    desc <- function(sdfset) {
      cbind(
        SDFID = sdfid(sdfset),
        MW = MW(sdfset),
        groups(sdfset),
        APFP = desc2fp(x = sdf2ap(sdfset), descnames = 1024, type = "character"),
        AP = sdf2ap(sdfset, type = "character"),
        rings(sdfset, type = "count", upper = 6, arom = TRUE)
      )
    }
    
    # Stream through the input SD file and write descriptors to a tabular file
    sdfStream(input = "test.sdf", output = "matrix.xls", fct = desc, Nlines = 1000)
    
    # Read the generated index and select the first 4 columns
    indexDF <- read.delim("matrix.xls", row.names = 1)[, 1:4]
    
    # Filter the index based on molecular weight criteria (MW < 400)
    indexDFsub <- indexDF[indexDF\$MW < 400, ]
    
    # Retrieve target molecules from the original file using the filtered index
    sdfset <- read.SDFindex(file = "test.sdf", index = indexDFsub, type = "SDFset")
    
    # Write outputs to the working directory
    write.csv(indexDFsub, "filtered_index.csv", row.names = TRUE)
    saveRDS(sdfset, "filtered_compounds.rds")
    write.SDF(sdfset, "filtered_compounds.sdf")

    writeLines(c(
        '"BIOC_CHEMMINER_LARGE_FILE_STREAMING":',
        paste0('    ChemmineR: ', as.character(packageVersion('ChemmineR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_file_streaming.csv versions.yml
    """
}

workflow BIOC_CHEMMINER_LARGE_FILE_STREAMING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.sdf ] ]

    main:
    BIOC_CHEMMINER_LARGE_FILE_STREAMING(ch_input)

    emit:
    tables   = BIOC_CHEMMINER_LARGE_FILE_STREAMING.out.tables
    plots    = BIOC_CHEMMINER_LARGE_FILE_STREAMING.out.plots
    objects  = BIOC_CHEMMINER_LARGE_FILE_STREAMING.out.objects
    versions = BIOC_CHEMMINER_LARGE_FILE_STREAMING.out.versions
}
