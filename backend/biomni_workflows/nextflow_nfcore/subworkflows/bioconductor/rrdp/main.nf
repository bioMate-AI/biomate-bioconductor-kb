#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rRDP — taxonomic_classification
// Classify 16S rRNA sequences taxonomically using the pre-trained RDP classifier.
// Input: sequences.fasta
// Container: quay.io/biocontainers/bioconductor-rrdp:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, rRDP
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the default RDP classifier
//  * 2. [Input & Preparation] Read sequences into a DNAStringSet
//  * 3. [Core Analysis] Classify sequences using predict

nextflow.enable.dsl = 2

process BIOC_RRDP_TAXONOMIC_CLASSIFICATION {
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
    .bm_deps <- c("Biostrings", "rRDP")
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
    
    # Set Java memory limit before loading rJava/rRDP to prevent OutOfMemory errors
    options(java.parameters = "-Xmx4g")
    
    # Load required libraries
    library(Biostrings)
    library(rRDP)
    
    # 1. Read sequences from the user-provided FASTA file
    seq <- readDNAStringSet("sequences.fasta")
    
    # 2. Load the default RDP classifier
    cl <- rdp()
    
    # 3. Classify sequences using predict
    pred <- predict(cl, seq)
    
    # 4. Write the classification results to a CSV file
    write.csv(as.data.frame(pred), "taxonomic_predictions.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_RRDP_TAXONOMIC_CLASSIFICATION":',
        paste0('    rRDP: ', as.character(packageVersion('rRDP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taxonomic_classification.csv versions.yml
    """
}

workflow BIOC_RRDP_TAXONOMIC_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.fasta ] ]

    main:
    BIOC_RRDP_TAXONOMIC_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_RRDP_TAXONOMIC_CLASSIFICATION.out.tables
    plots    = BIOC_RRDP_TAXONOMIC_CLASSIFICATION.out.plots
    objects  = BIOC_RRDP_TAXONOMIC_CLASSIFICATION.out.objects
    versions = BIOC_RRDP_TAXONOMIC_CLASSIFICATION.out.versions
}
