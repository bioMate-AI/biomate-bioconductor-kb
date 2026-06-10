#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rsvsim — inserting_known_svs
// Insert a set of known, user-defined structural variations at exact coordinates.
// Input: genome.fasta
// Container: quay.io/biocontainers/bioconductor-rsvsim:1.50.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSVSIM_INSERTING_KNOWN_SVS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rsvsim:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "GenomicRanges", "RSVSim")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(RSVSim)
    library(Biostrings)
    library(GenomicRanges)
    
    # Read the user-provided reference genome sequence
    genome = readDNAStringSet("genome.fasta")
    
    # --- Deletion Workflow ---
    
    # 1. Define the exact coordinates of the SVs using GRanges
    knownDeletion = GRanges(IRanges(16,25), seqnames="chr2")
    names(knownDeletion) = "myDeletion"
    
    # 2. Run simulateSV with random=FALSE and pass the GRanges to the corresponding regions parameter
    sim = simulateSV(output=NA, genome=genome, regionsDels=knownDeletion,
                     bpSeqSize=10, random=FALSE, verbose=FALSE)
    
    # Save deletion results
    saveRDS(sim, "simulated_deletions.rds")
    writeXStringSet(sim, "genome_rearranged_deletions.fasta")
    if (!is.null(metadata(sim)\$deletions)) {
      write.csv(metadata(sim)\$deletions, "deletions_metadata.csv", row.names = FALSE)
    }
    
    # --- Insertion Workflow ---
    
    # 1. Define the exact coordinates of the SVs using GRanges
    knownInsertion = GRanges(IRanges(16,25),seqnames="chr1", chrB="chr2", startB=26)
    names(knownInsertion) = "myInsertion"
    
    # 2. Run simulateSV with random=FALSE and pass the GRanges to the corresponding regions parameter
    sim = simulateSV(output=NA, genome=genome, regionsIns=knownInsertion,
                     bpSeqSize=10, random=FALSE, verbose=FALSE)
    
    # Save insertion results
    saveRDS(sim, "simulated_insertions.rds")
    writeXStringSet(sim, "genome_rearranged_insertions.fasta")
    if (!is.null(metadata(sim)\$insertions)) {
      write.csv(metadata(sim)\$insertions, "insertions_metadata.csv", row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RSVSIM_INSERTING_KNOWN_SVS":
        rsvsim: \$(Rscript -e 'cat(as.character(packageVersion("rsvsim")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inserting_known_svs.csv versions.yml
    """
}

workflow BIOC_RSVSIM_INSERTING_KNOWN_SVS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fasta ] ]

    main:
    BIOC_RSVSIM_INSERTING_KNOWN_SVS(ch_input)

    emit:
    tables   = BIOC_RSVSIM_INSERTING_KNOWN_SVS.out.tables
    plots    = BIOC_RSVSIM_INSERTING_KNOWN_SVS.out.plots
    objects  = BIOC_RSVSIM_INSERTING_KNOWN_SVS.out.objects
    versions = BIOC_RSVSIM_INSERTING_KNOWN_SVS.out.versions
}
