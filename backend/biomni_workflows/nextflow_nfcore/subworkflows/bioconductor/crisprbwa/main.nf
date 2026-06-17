#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprBwa — crispr_grna_alignment
// Align CRISPR gRNA spacer sequences to a reference genome to identify on-target and off-target sites with PAM constraints.
// Input: genome_fasta.fa, spacers_vector
// Container: quay.io/biocontainers/bioconductor-crisprbwa:1.14.0--r45hdfd78af_0
// R packages: Biostrings, crisprBase, crisprBwa, Rbwa
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, Rbwa, crisprBase, crisprBwa
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build a BWA index from the reference genome FASTA using Rbwa::bwa_build_index
//  * 2. [Input & Preparation] Load the corresponding BSgenome object and CrisprNuclease object
//  * 3. [Core Analysis] Align spacers and annotate PAMs using runCrisprBwa

nextflow.enable.dsl = 2

process BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT {
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
    .bm_deps <- c("Biostrings", "crisprBase", "crisprBwa", "Rbwa")
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
    library(Biostrings)
    library(crisprBase)
    
    # 1. Read User Inputs
    fasta <- "genome_fasta.fa"
    if (!file.exists(fasta)) {
        stop("Required input file 'genome_fasta.fa' not found in the working directory.")
    }
    
    # Read spacers_vector robustly (supporting RDS, txt, or unextended files)
    if (file.exists("spacers_vector")) {
        spacers <- tryCatch({
            readRDS("spacers_vector")
        }, error = function(e) {
            readLines("spacers_vector")
        })
    } else if (file.exists("spacers_vector.rds")) {
        spacers <- readRDS("spacers_vector.rds")
    } else if (file.exists("spacers_vector.txt")) {
        spacers <- readLines("spacers_vector.txt")
    } else {
        stop("Required input file 'spacers_vector' not found in the working directory.")
    }
    
    # Ensure spacers is a character vector
    spacers <- as.character(spacers)
    
    # 2. Build BWA Index
    outdir <- tempdir()
    index <- file.path(outdir, "genome_index")
    Rbwa::bwa_build_index(fasta,
                          index_prefix=index)
    
    # 3. Load BSgenome and CrisprNuclease Objects
    # SpCas9 is lazy-loaded from the crisprBase package
    crisprNuclease <- SpCas9
    bsgenome <- readDNAStringSet(fasta)
    
    # 4. Align Spacers and Annotate PAMs
    results <- runCrisprBwa(spacers,
                            bsgenome=bsgenome,
                            crisprNuclease=crisprNuclease,
                            n_mismatches=3,
                            canonical=FALSE,
                            bwa_index=index)
    
    # 5. Write Outputs
    write.csv(results, "crispr_grna_alignment_results.csv", row.names = FALSE)
    saveRDS(results, "crispr_grna_alignment_results.rds")

    writeLines(c(
        '"BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT":',
        paste0('    crisprBwa: ', as.character(packageVersion('crisprBwa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crispr_grna_alignment.csv versions.yml
    """
}

workflow BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome_fasta.fa, spacers_vector ] ]

    main:
    BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT.out.tables
    plots    = BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT.out.plots
    objects  = BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT.out.objects
    versions = BIOC_CRISPRBWA_CRISPR_GRNA_ALIGNMENT.out.versions
}
