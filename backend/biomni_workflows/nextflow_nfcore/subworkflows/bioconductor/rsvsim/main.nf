#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rsvsim — structural_variation_simulation
// Simulate random structural variations in a genome with optional repeat biases, breakpoint mutations, or within specific genomic regions.
// Input: genome.fasta
// Container: quay.io/biocontainers/bioconductor-rsvsim:1.50.0--r45hdfd78af_0
// R packages: Biostrings, GenomicRanges, RSVSim
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION {
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
    library(RSVSim)
    library(Biostrings)
    library(GenomicRanges)
    
    # 1. Load the genome sequence as a DNAStringSet from user input
    if (!file.exists("genome.fasta")) {
      stop("Error: genome.fasta not found in the working directory.")
    }
    genome = readDNAStringSet("genome.fasta")
    
    # Ensure the genome has at least two chromosomes named "chr1" and "chr2"
    # to match the documented code's region specifications and coordinates.
    if (length(genome) < 2) {
      genome = c(genome, genome)
    }
    names(genome)[1:2] = c("chr1", "chr2")
    
    # 2. Run simulateSV with specified SV counts, sizes, and optional parameters
    # Stage 1: Deletions simulation
    sim = simulateSV(output=NA, genome=genome, dels=3, sizeDels=10,
    bpSeqSize=6, seed=456, verbose=FALSE)
    
    # Save results for Stage 1
    saveRDS(sim, "sim1_deletions.rds")
    writeXStringSet(sim, "genome_rearranged_sim1.fasta")
    meta1 = metadata(sim)
    if (!is.null(meta1\$deletions)) {
      write.csv(meta1\$deletions, "sim1_deletions_metadata.csv", row.names=FALSE)
    }
    
    # Stage 2: Deletions with breakpoint mutations
    sim = simulateSV(output=NA, genome=genome, dels=1, sizeDels=5, bpFlankSize=10, 
    percSNPs=0.25, indelProb=1, maxIndelSize=3, bpSeqSize=10, seed=123, verbose=FALSE)
    
    # Save results for Stage 2
    saveRDS(sim, "sim2_mutations.rds")
    writeXStringSet(sim, "genome_rearranged_sim2.fasta")
    meta2 = metadata(sim)
    if (!is.null(meta2\$deletions)) {
      write.csv(meta2\$deletions, "sim2_deletions_metadata.csv", row.names=FALSE)
    }
    
    # Stage 3: Inversions within specific genomic regions
    regions = GRanges(IRanges(c(21,1),c(40,20)), seqnames=c("chr1","chr2"))
    sim = simulateSV(output=NA, genome=genome, invs=4, sizeInvs=5, 
    regionsInvs=regions, bpSeqSize=6, seed=2345, verbose=FALSE)
    
    # Save results for Stage 3
    saveRDS(sim, "sim3_inversions.rds")
    writeXStringSet(sim, "genome_rearranged_sim3.fasta")
    meta3 = metadata(sim)
    if (!is.null(meta3\$inversions)) {
      write.csv(meta3\$inversions, "sim3_inversions_metadata.csv", row.names=FALSE)
    }

    writeLines(c(
        '"BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION":',
        paste0('        rsvsim: ', as.character(packageVersion("rsvsim")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_structural_variation_simulation.csv versions.yml
    """
}

workflow BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fasta ] ]

    main:
    BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION(ch_input)

    emit:
    tables   = BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION.out.tables
    plots    = BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION.out.plots
    objects  = BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION.out.objects
    versions = BIOC_RSVSIM_STRUCTURAL_VARIATION_SIMULATION.out.versions
}
