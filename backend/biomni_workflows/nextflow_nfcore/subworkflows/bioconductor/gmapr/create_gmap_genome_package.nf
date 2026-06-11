#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmapR — create_gmap_genome_package
// Package a GmapGenome index into a reusable R package for distribution and reproducibility.
// Input: gmapGenome
// Container: quay.io/biocontainers/bioconductor-gmapr:1.48.0--r44h15a9599_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gmapR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Package the genome using makeGmapGenomePackage

nextflow.enable.dsl = 2

process BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(gmapR)
    
    # Read the user input GmapGenome object from the working directory
    input_file <- "gmapGenome.rds"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    gmapGenome <- readRDS(input_file)
    
    # Ensure the destination directory exists
    dest_dir <- "myDestDir"
    if (!dir.exists(dest_dir)) {
      dir.create(dest_dir, recursive = TRUE)
    }
    
    # Package the genome using makeGmapGenomePackage exactly as documented
    makeGmapGenomePackage(gmapGenome=gmapGenome,
                          version="1.0.0",
                          maintainer="<your.name@somewhere.com>",
                          author="Your Name",
                          destDir="myDestDir",
                          license="Artistic-2.0",
                          pkgName="GmapGenome.Dmelanogaster.UCSC.dm3")
    
    # Verify and write the list of created package files as output
    created_files <- list.files(dest_dir, recursive = TRUE, full.names = TRUE)
    writeLines(created_files, "created_package_files.txt")

    writeLines(c(
        '"BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE":',
        paste0('    gmapR: ', as.character(packageVersion('gmapR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_gmap_genome_package.csv versions.yml
    """
}

workflow BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gmapGenome ] ]

    main:
    BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE(ch_input)

    emit:
    tables   = BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE.out.tables
    plots    = BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE.out.plots
    objects  = BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE.out.objects
    versions = BIOC_GMAPR_CREATE_GMAP_GENOME_PACKAGE.out.versions
}
