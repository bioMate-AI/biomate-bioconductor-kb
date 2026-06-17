#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: procoil — comparative_mutation_analysis
// Compare the oligomerization profiles of wild-type and mutant coiled coil sequences to analyze the impact of mutations.
// Input: mutant_sequences.fasta, registers.txt
// Container: quay.io/biocontainers/bioconductor-procoil:2.38.0--r45hdfd78af_0
// R packages: Biostrings, procoil
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, procoil
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run prediction on multiple sequences simultaneously using predict()
//  * 2. [Visualization & Output] Plot comparative profiles of selected sequences using plot()
//  * 3. [Visualization & Output] Generate a hierarchical clustering heatmap of the profiles using heatmap()

nextflow.enable.dsl = 2

process BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "procoil")
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
    library(procoil)
    library(Biostrings)
    
    # Read user input files
    fasta <- Biostrings::readAAStringSet("mutant_sequences.fasta")
    GCN4mSeq <- as.character(fasta)
    names(GCN4mSeq) <- names(fasta)
    
    GCN4mReg <- readLines("registers.txt")
    GCN4mReg <- GCN4mReg[GCN4mReg != ""]
    
    # Run prediction on multiple sequences simultaneously
    GCN4mut <- predict(PrOCoilModel, GCN4mSeq, GCN4mReg)
    GCN4mut
    
    # Plot comparative profiles of selected sequences and save to PDF
    pdf("comparative_profile_plot.pdf", width = 8, height = 6)
    plot(GCN4mut[c(1, 2)])
    dev.off()
    
    # Generate a hierarchical clustering heatmap of the profiles and save to PDF
    pdf("heatmap_plot.pdf", width = 8, height = 6)
    heatmap(GCN4mut)
    dev.off()
    
    # Save predictions to CSV
    pred_df <- GCN4mut@predictions
    write.csv(pred_df, "predictions.csv", row.names = TRUE)
    
    # Save the full CCProfile object to RDS
    saveRDS(GCN4mut, "GCN4mut_profile.rds")

    writeLines(c(
        '"BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS":',
        paste0('    procoil: ', as.character(packageVersion('procoil')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comparative_mutation_analysis.csv versions.yml
    """
}

workflow BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mutant_sequences.fasta, registers.txt ] ]

    main:
    BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS.out.tables
    plots    = BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS.out.plots
    objects  = BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS.out.objects
    versions = BIOC_PROCOIL_COMPARATIVE_MUTATION_ANALYSIS.out.versions
}
