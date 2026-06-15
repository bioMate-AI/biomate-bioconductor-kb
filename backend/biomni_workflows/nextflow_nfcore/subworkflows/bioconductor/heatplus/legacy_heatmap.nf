#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Heatplus — legacy_heatmap
// Generate heatmaps using the older legacy functions heatmap_2 and heatmap_plus.
// Input: exprs_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-heatplus:3.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Heatplus
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate basic legacy heatmap using heatmap_2
//  * 2. [Visualization & Output] Generate annotated legacy heatmap using heatmap_plus

nextflow.enable.dsl = 2

process BIOC_HEATPLUS_LEGACY_HEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Heatplus")
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
    library(Heatplus)
    
    # Read user input files from the working directory
    # exprs_matrix.csv: numeric matrix of features (rows) by samples (columns)
    mm <- as.matrix(read.csv("exprs_matrix.csv", row.names = 1, check.names = FALSE))
    
    # sample_metadata.csv: data frame of sample annotations (rows = samples, columns = annotations)
    addvar <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # --- Generate basic legacy heatmap using heatmap_2 ---
    pdf("heatmap_2_basic.pdf")
    heatmap_2(mm)
    dev.off()
    
    pdf("heatmap_2_custom.pdf")
    heatmap_2(mm, do.dendro=c(FALSE, TRUE), legend=1, legfrac=12)
    dev.off()
    
    # --- Generate annotated legacy heatmap using heatmap_plus ---
    pdf("heatmap_plus_basic.pdf")
    heatmap_plus(mm)
    dev.off()
    
    pdf("heatmap_plus_annotated.pdf")
    heatmap_plus(mm, addvar=addvar, cov=ncol(addvar))
    dev.off()
    
    pdf("heatmap_plus_custom.pdf")
    heatmap_plus(mm, addvar=addvar, cov=ncol(addvar), h=20, col=RGBColVec(64))
    dev.off()

    writeLines(c(
        '"BIOC_HEATPLUS_LEGACY_HEATMAP":',
        paste0('    Heatplus: ', as.character(packageVersion('Heatplus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_legacy_heatmap.csv versions.yml
    """
}

workflow BIOC_HEATPLUS_LEGACY_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_HEATPLUS_LEGACY_HEATMAP(ch_input)

    emit:
    tables   = BIOC_HEATPLUS_LEGACY_HEATMAP.out.tables
    plots    = BIOC_HEATPLUS_LEGACY_HEATMAP.out.plots
    objects  = BIOC_HEATPLUS_LEGACY_HEATMAP.out.objects
    versions = BIOC_HEATPLUS_LEGACY_HEATMAP.out.versions
}
