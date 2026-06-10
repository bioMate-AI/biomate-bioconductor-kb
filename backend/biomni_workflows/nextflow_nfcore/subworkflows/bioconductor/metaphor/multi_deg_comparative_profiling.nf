#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaphor — multi_deg_comparative_profiling
// Compare metabolic profiles across multiple groups or conditions using a heatmap.
// Input: BRCA_DEGS.csv, OVCA_Scores.csv, PRAD_Scores.csv
// Container: quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0
// R packages: MetaPhOR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("MetaPhOR")
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
    
    # Load required library
    library(MetaPhOR)
    
    # Set seed for reproducible bootstrapping in pathwayAnalysis
    set.seed(1234)
    
    # Stage 1: Run pathway analysis for BRCA using the user-provided DEG list
    brca <- pathwayAnalysis(
      DEGpath = "BRCA_DEGS.csv",
      genename = "X",
      sampsize = 1095,
      iters = 50000,
      headers = c("logFC", "adj.P.Val")
    )
    
    # Save the calculated BRCA scores to a CSV file
    write.csv(brca, "BRCA_Scores.csv", row.names = TRUE)
    
    # Stage 2: Load pre-calculated scores for comparison conditions from user input
    ovca <- read.csv(
      "OVCA_Scores.csv",
      header = TRUE,
      row.names = 1
    )
    
    prad <- read.csv(
      "PRAD_Scores.csv",
      header = TRUE,
      row.names = 1
    )
    
    # Stage 3: Combine the scores into a list
    all.scores <- list(brca, ovca, prad)
    names <- c("BRCA", "OVCA", "PRAD")
    
    # Save the combined scores list as an RDS object
    saveRDS(all.scores, "all_scores.rds")
    
    # Stage 4: Generate and save the comparative heatmap
    pdf("comparative_heatmap.pdf", width = 10, height = 8)
    metaHeatmap(
      scorelist = all.scores,
      samplenames = names,
      pvalcut = 0.05
    )
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING":
        metaphor: \$(Rscript -e 'cat(as.character(packageVersion("metaphor")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_deg_comparative_profiling.csv versions.yml
    """
}

workflow BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BRCA_DEGS.csv, OVCA_Scores.csv, PRAD_Scores.csv ] ]

    main:
    BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING(ch_input)

    emit:
    tables   = BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING.out.tables
    plots    = BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING.out.plots
    objects  = BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING.out.objects
    versions = BIOC_METAPHOR_MULTI_DEG_COMPARATIVE_PROFILING.out.versions
}
