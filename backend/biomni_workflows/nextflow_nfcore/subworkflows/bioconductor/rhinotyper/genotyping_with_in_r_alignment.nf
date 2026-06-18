#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rhinotypeR — genotyping_with_in_r_alignment
// Genotype rhinovirus sequences by aligning user sequences to packaged prototypes directly within R, followed by genotype assignment and frequency visualization.
// Input: user_sequences.fasta
// Container: quay.io/biocontainers/bioconductor-rhinotyper:1.4.0--r45hdfd78af_0
// R packages: Biostrings, rhinotypeR
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, rhinotypeR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Align user sequences to packaged prototypes
//  * 2. [Core Analysis] Assign genotypes
//  * 3. [Visualization & Output] Plot genotype frequencies

nextflow.enable.dsl = 2

process BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT {
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
    .bm_deps <- c("Biostrings", "rhinotypeR")
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
    library(rhinotypeR)
    library(Biostrings)
    
    # Define input file path
    input_file <- "user_sequences.fasta"
    
    # Check if input file exists
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "is missing in the working directory."))
    }
    
    # Read user sequences
    user_seqs <- Biostrings::readDNAStringSet(input_file)
    
    # 1. Align user sequences to packaged prototypes
    aln <- alignToRefs(
      seqData   = user_seqs,
      method    = "ClustalW",           # or "ClustalOmega", "Muscle"
      trimToRef = TRUE,                 # crop to reference non-gap span
      refName   = "JN855971.1_A107"     # default anchor; change if desired
    )
    
    # Save alignment object
    saveRDS(aln, "aligned_sequences.rds")
    
    # 2. Assign genotypes
    res <- assignTypes(aln, model = "IUPAC", deleteGapsGlobally = FALSE, threshold = 0.105)
    
    # Save genotype assignment results
    write.csv(res, "genotype_assignments.csv", row.names = FALSE)
    
    # Print head of results to console
    print(head(res))
    
    # 3. Plot genotype frequencies
    pdf("genotype_frequency_plot.pdf", width = 8, height = 6)
    plotFrequency(res)
    dev.off()

    writeLines(c(
        '"BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT":',
        paste0('    rhinotypeR: ', as.character(packageVersion('rhinotypeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genotyping_with_in_r_alignment.csv versions.yml
    """
}

workflow BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_sequences.fasta ] ]

    main:
    BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT.out.tables
    plots    = BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT.out.plots
    objects  = BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT.out.objects
    versions = BIOC_RHINOTYPER_GENOTYPING_WITH_IN_R_ALIGNMENT.out.versions
}
