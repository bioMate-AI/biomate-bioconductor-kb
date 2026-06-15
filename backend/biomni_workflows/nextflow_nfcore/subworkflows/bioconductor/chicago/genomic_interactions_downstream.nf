#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chicago — genomic_interactions_downstream
// Export CHiCAGO results to a GenomicInteractions object for downstream genomic overlap and annotation analyses.
// Input: cd, enhancerTrack
// Container: quay.io/biocontainers/bioconductor-chicago:1.38.0--r45hdfd78af_0
// R packages: Chicago, GenomeInfoDb, GenomicInteractions, GenomicRanges
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chicago:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("Chicago", "GenomeInfoDb", "GenomicInteractions", "GenomicRanges")
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
    
    # Load required libraries
    library(Chicago)
    library(GenomicInteractions)
    library(GenomicRanges)
    library(GenomeInfoDb)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Inputs from Working Directory
    # -----------------------------------------------------------------------------
    if (!file.exists("cd.rds")) {
      stop("Error: Input file 'cd.rds' (processed chicagoData object) not found in the working directory.")
    }
    if (!file.exists("enhancerTrack.rds")) {
      stop("Error: Input file 'enhancerTrack.rds' (GRanges object) not found in the working directory.")
    }
    
    cd <- readRDS("cd.rds")
    enhancerTrack <- readRDS("enhancerTrack.rds")
    
    # -----------------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # -----------------------------------------------------------------------------
    
    # --- Convert the chicagoData object to a GenomicInteractions ---
    gi <- exportToGI(cd)
    
    # --- Extract the other end coordinates ---
    otherEnds <- anchorTwo(gi)
    
    # --- Standardize chromosome naming ---
    otherEnds <- renameSeqlevels(otherEnds, c("chr20","chr21"))
    
    # --- Find overlaps between interaction ends and genomic ---
    overlaps <- findOverlaps(otherEnds, enhancerTrack)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    # Save the GenomicInteractions object
    saveRDS(gi, "genomic_interactions.rds")
    
    # Save the extracted other ends GRanges object
    saveRDS(otherEnds, "other_ends.rds")
    
    # Save the overlaps as a CSV table
    overlaps_df <- as.data.frame(overlaps)
    write.csv(overlaps_df, "overlaps.csv", row.names = FALSE)
    
    message("Workflow completed successfully. Outputs saved: 'genomic_interactions.rds', 'other_ends.rds', 'overlaps.csv'.")

    writeLines(c(
        '"BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM":',
        paste0('        chicago: ', as.character(packageVersion("chicago")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_interactions_downstream.csv versions.yml
    """
}

workflow BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cd, enhancerTrack ] ]

    main:
    BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM(ch_input)

    emit:
    tables   = BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM.out.tables
    plots    = BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM.out.plots
    objects  = BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM.out.objects
    versions = BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM.out.versions
}
