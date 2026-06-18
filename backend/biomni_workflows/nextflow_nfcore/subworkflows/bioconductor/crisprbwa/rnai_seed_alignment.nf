#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprBwa — rnai_seed_alignment
// Map short RNAi (siRNA/shRNA) seed sequences to a reference genome to predict putative off-targets without PAM constraints.
// Input: genome_fasta.fa, seeds_vector
// Container: quay.io/biocontainers/bioconductor-crisprbwa:1.14.0--r45hdfd78af_0
// R packages: Rbwa, crisprBwa
// Bioconductor: 3.20 | R: 4.4
// Requires: Rbwa, crisprBwa
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build a BWA index from the reference genome FASTA using Rbwa::bwa_build_index
//  * 2. [Core Analysis] Align seed sequences using runBwa

nextflow.enable.dsl = 2

process BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Rbwa", "crisprBwa")
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
    
    # Load required libraries
    library(Rbwa)
    library(crisprBwa)
    
    # Define input file paths
    fasta_input <- "genome_fasta.fa"
    seeds_input <- "seeds_vector"
    
    # Validate inputs
    if (!file.exists(fasta_input)) {
      stop("Error: Reference genome FASTA file 'genome_fasta.fa' not found in the working directory.")
    }
    if (!file.exists(seeds_input)) {
      stop("Error: Seeds vector file 'seeds_vector' not found in the working directory.")
    }
    
    # Read seeds vector (supports both RDS and plain text formats)
    seeds <- tryCatch({
      readRDS(seeds_input)
    }, error = function(e) {
      readLines(seeds_input)
    })
    seeds <- as.character(seeds)
    seeds <- trimws(seeds)
    seeds <- seeds[seeds != ""]
    
    # Define index prefix in a temporary directory
    outdir <- tempdir()
    index <- file.path(outdir, "genome_index")
    
    # Build BWA index
    # Documented call: Rbwa::bwa_build_index(fasta, index_prefix=index)
    fasta <- fasta_input
    Rbwa::bwa_build_index(fasta,
                          index_prefix=index)
    
    # Run BWA alignment for RNAi seeds
    # Documented call: runBwa(seeds, n_mismatches=2, bwa_index=index)
    alignments <- runBwa(seeds,
                         n_mismatches=2,
                         bwa_index=index)
    
    # Save outputs
    write.csv(alignments, file = "rnai_seed_alignments.csv", row.names = FALSE)
    saveRDS(alignments, file = "rnai_seed_alignments.rds")

    writeLines(c(
        '"BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT":',
        paste0('    crisprBwa: ', as.character(packageVersion('crisprBwa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnai_seed_alignment.csv versions.yml
    """
}

workflow BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome_fasta.fa, seeds_vector ] ]

    main:
    BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT.out.tables
    plots    = BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT.out.plots
    objects  = BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT.out.objects
    versions = BIOC_CRISPRBWA_RNAI_SEED_ALIGNMENT.out.versions
}
