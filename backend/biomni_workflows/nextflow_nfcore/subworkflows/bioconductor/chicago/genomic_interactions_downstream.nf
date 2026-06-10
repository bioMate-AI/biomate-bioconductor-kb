#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chicago — genomic_interactions_downstream
// Export CHiCAGO results to a GenomicInteractions object for downstream genomic overlap and annotation analyses.
// Input: cd, enhancerTrack
// Container: quay.io/biocontainers/bioconductor-chicago:1.38.0--r45hdfd78af_0
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
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
    
    # Stage 1: Convert the chicagoData object to a GenomicInteractions object
    gi <- exportToGI(cd)
    
    # Stage 2: Extract the other end coordinates
    otherEnds <- anchorTwo(gi)
    
    # Stage 3: Standardize chromosome naming
    otherEnds <- renameSeqlevels(otherEnds, c("chr20","chr21"))
    
    # Stage 4: Find overlaps between interaction ends and genomic features
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHICAGO_GENOMIC_INTERACTIONS_DOWNSTREAM":
        chicago: \$(Rscript -e 'cat(as.character(packageVersion("chicago")))')
    END_VERSIONS
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
