#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FilterFFPE — artifact_chimeric_read_filtration
// Find and filter artificial chimeric reads and their duplicates from an FFPE BAM file to prepare it for downstream structural variation calling.
// Input: file.bam
// Container: quay.io/biocontainers/bioconductor-filterffpe:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FilterFFPE, Rsamtools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find artifact chimeric reads and duplicate chimeric reads using findArtifactChimericReads
//  * 2. [Input & Preparation] Filter the BAM file by read names using filterBamByReadNames
//  * 3. [Core Analysis] Alternatively, perform both finding and filtering in a single step using FFPEReadFilter
//  * 4. [Core Analysis] Verify the filtered BAM file using Rsamtools::scanBam

nextflow.enable.dsl = 2

process BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION {
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
    library(FilterFFPE)
    library(Rsamtools)
    
    # Define input file (must exist in the working directory)
    file <- "file.bam"
    
    # Define output paths in the current working directory
    outFolder <- "."
    FFPEReadsFile <- paste0(outFolder, "/example.FFPEReads.txt")
    dupChimFile <- paste0(outFolder, "/example.dupChim.txt")
    
    # 1. Find artifact chimeric reads and duplicate chimeric reads
    artifactReads <- findArtifactChimericReads(file = file, threads = 2,
                                               FFPEReadsFile = FFPEReadsFile,
                                               dupChimFile = dupChimFile)
    
    # Save identified artifact reads to an RDS file
    saveRDS(artifactReads, file = "artifactReads.rds")
    
    # 2. Filter the BAM file by read names
    dupChim <- readLines(dupChimFile)
    readsToFilter <- c(artifactReads, dupChim)
    destination <- paste0(outFolder, "/example.FilterFFPE.bam")
    filterBamByReadNames(file = file, readsToFilter = readsToFilter,
                         destination = destination, overwrite=TRUE)
    
    # 3. Alternatively, perform both finding and filtering in a single step
    FFPEReadFilter(file = file, threads=2, destination = destination,
                   overwrite=TRUE, FFPEReadsFile = FFPEReadsFile,
                   dupChimFile = dupChimFile)
    
    # 4. Verify the filtered BAM file using Rsamtools::scanBam
    newBam <- Rsamtools::scanBam(destination)
    
    # Save scan results to an RDS file
    saveRDS(newBam, file = "scanBam_results.rds")

    writeLines(c(
        '"BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION":',
        paste0('    FilterFFPE: ', as.character(packageVersion('FilterFFPE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_artifact_chimeric_read_filtration.csv versions.yml
    """
}

workflow BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.bam ] ]

    main:
    BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION(ch_input)

    emit:
    tables   = BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION.out.tables
    plots    = BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION.out.plots
    objects  = BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION.out.objects
    versions = BIOC_FILTERFFPE_ARTIFACT_CHIMERIC_READ_FILTRATION.out.versions
}
