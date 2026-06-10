#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cellity — pca_based_quality_assessment
// Identify low-quality cells using unsupervised PCA-based outlier detection on extracted biological and technical features.
// Input: gene_counts.tsv, read_stats.tsv
// Container: quay.io/biocontainers/bioconductor-cellity:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cellity
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize gene expression counts using normalise_by_factor
//  * 2. [Core Analysis] Extract biological and technical features using extract_features
//  * 3. [Core Analysis] Assess cell quality and detect outliers using assess_cell_quality_PCA

nextflow.enable.dsl = 2

process BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    
    # Load required library
    library(cellity)
    
    # Read user input files
    sample_counts <- as.matrix(read.delim("gene_counts.tsv", row.names = 1, header = TRUE, check.names = FALSE))
    sample_stats <- as.matrix(read.delim("read_stats.tsv", row.names = 1, header = TRUE, check.names = FALSE))
    
    # 1. Normalize gene expression counts
    sample_counts_nm <- normalise_by_factor(sample_counts, colSums(sample_counts))
    
    # 2. Extract biological and technical features
    sample_features <- extract_features(sample_counts_nm, sample_stats)
    sample_features_all <- sample_features[[1]]
    
    # 3. Assess cell quality and detect outliers using PCA with PDF output
    sample_qual_pca <- assess_cell_quality_PCA(sample_features_all, file = "./training_quality_PCA_allF.pdf")
    
    # Map the output to the training variable to preserve expected output files
    training_quality_PCA_allF <- sample_qual_pca
    
    # Save outputs
    write.csv(sample_qual_pca, "sample_qual_pca.csv", row.names = TRUE)
    write.csv(training_quality_PCA_allF, "training_quality_PCA_allF.csv", row.names = TRUE)
    saveRDS(sample_features, "sample_features.rds")

    writeLines(c(
        '"BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT":',
        paste0('    cellity: ', as.character(packageVersion('cellity')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_based_quality_assessment.csv versions.yml
    """
}

workflow BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_counts.tsv, read_stats.tsv ] ]

    main:
    BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT.out.tables
    plots    = BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT.out.plots
    objects  = BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT.out.objects
    versions = BIOC_CELLITY_PCA_BASED_QUALITY_ASSESSMENT.out.versions
}
