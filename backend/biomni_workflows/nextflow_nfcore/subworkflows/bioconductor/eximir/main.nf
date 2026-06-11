#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eximir — affymetrix_mirna_normalization
// Read, annotate, and normalize Affymetrix miRNA CEL files using spike-in or quantile normalization.
// Input: CEL files, miRNA-1_0.CDF
// Container: quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0
// R packages: affy, ExiMiR, makecdfenv, mirna10cdf
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0"

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
    .bm_deps <- c("affy", "ExiMiR", "makecdfenv", "mirna10cdf")
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
    
    # Create the 'Affymetrix' directory as expected by the documented code
    dir.create("Affymetrix", showWarnings = FALSE, recursive = TRUE)
    
    # Find and copy the CDF file
    cdf_file <- list.files(pattern = "(?i)miRNA-1_0\\\\.cdf\$")
    if (length(cdf_file) > 0) {
      file.copy(cdf_file[1], "Affymetrix/miRNA-1_0.CDF", overwrite = TRUE)
    } else {
      stop("Required CDF file 'miRNA-1_0.CDF' not found in the working directory.")
    }
    
    # Find and copy CEL files
    cel_files <- list.files(pattern = "(?i)\\\\.cel\$")
    if (length(cel_files) > 0) {
      for (f in cel_files) {
        file.copy(f, file.path("Affymetrix", f), overwrite = TRUE)
      }
    } else {
      stop("No CEL files found in the working directory.")
    }
    
    # Documented workflow
    try(library(mirna10cdf), silent = TRUE)
    library(makecdfenv)
    cdfenv <- make.cdf.env(cdf.path='Affymetrix', filename='miRNA-1_0.CDF')
    library(affy)
    abatch <- ReadAffy(cdfname='cdfenv', celfile.path='Affymetrix')
    library(ExiMiR)
    eset.spike <- NormiR(abatch, bgcorrect.method='rma',
                                    normalize.method='spikein',
                                    pmcorrect.method='pmonly',
                                    summary.method='medianpolish')
    
    # Save outputs
    saveRDS(eset.spike, file = "eset_spike.rds")
    write.csv(exprs(eset.spike), file = "normalized_intensities.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION":',
        paste0('        eximir: ', as.character(packageVersion("eximir")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affymetrix_mirna_normalization.csv versions.yml
    """
}

workflow BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CEL files, miRNA-1_0.CDF ] ]

    main:
    BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION.out.tables
    plots    = BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION.out.plots
    objects  = BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION.out.objects
    versions = BIOC_EXIMIR_AFFYMETRIX_MIRNA_NORMALIZATION.out.versions
}
