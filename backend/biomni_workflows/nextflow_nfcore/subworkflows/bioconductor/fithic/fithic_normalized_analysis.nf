#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FitHiC — fithic_normalized_analysis
// Run Fit-Hi-C on raw Hi-C contact maps incorporating matrix balancing-based normalization bias values (e.g., ICE or KR) to control for experimental biases.
// Input: fragsfile.gz, intersfile.gz, biasfile.gz
// Container: quay.io/biocontainers/bioconductor-fithic:1.36.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FitHiC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define paths to input files, bias file, and output directory
//  * 2. [Core Analysis] Run the FitHiC function with the bias file specified to calculate normalized interaction significance

nextflow.enable.dsl = 2

process BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("FitHiC")
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
    
    library("FitHiC")
    
    # 1. Define paths to input files, bias file, and output directory
    fragsfile <- "fragsfile.gz"
    intersfile <- "intersfile.gz"
    biasfile <- "biasfile.gz"
    outdir <- file.path(getwd(), "Dixon_hESC_HindIII_hg18_w40000_chr1.afterICE")
    
    if (!dir.exists(outdir)) {
      dir.create(outdir, recursive = TRUE)
    }
    
    # 2. Run the FitHiC function with the bias file specified to calculate normalized interaction significance
    FitHiC(fragsfile, intersfile, outdir, biasfile,
        libname="Dixon_hESC_HindIII_hg18_w40000_chr1", noOfBins=50,
        distUpThres=5000000, distLowThres=50000, visual=TRUE)
    
    # 3. Export meaningful results to standard formats (CSV, RDS)
    pass1_path <- file.path(outdir, "Dixon_hESC_HindIII_hg18_w40000_chr1.fithic_pass1.txt")
    pass2_path <- file.path(outdir, "Dixon_hESC_HindIII_hg18_w40000_chr1.fithic_pass2.txt")
    sig1_path <- file.path(outdir, "Dixon_hESC_HindIII_hg18_w40000_chr1.spline_pass1.significances.txt.gz")
    sig2_path <- file.path(outdir, "Dixon_hESC_HindIII_hg18_w40000_chr1.spline_pass2.significances.txt.gz")
    
    if (file.exists(pass1_path)) {
      pass1_data <- read.table(pass1_path, header = TRUE)
      write.csv(pass1_data, "fithic_pass1_probabilities.csv", row.names = FALSE)
      saveRDS(pass1_data, "fithic_pass1_probabilities.rds")
    }
    
    if (file.exists(pass2_path)) {
      pass2_data <- read.table(pass2_path, header = TRUE)
      write.csv(pass2_data, "fithic_pass2_probabilities.csv", row.names = FALSE)
      saveRDS(pass2_data, "fithic_pass2_probabilities.rds")
    }
    
    if (file.exists(sig1_path)) {
      sig1_data <- read.table(gzfile(sig1_path), header = TRUE)
      write.csv(sig1_data, "fithic_pass1_significances.csv", row.names = FALSE)
      saveRDS(sig1_data, "fithic_pass1_significances.rds")
    }
    
    if (file.exists(sig2_path)) {
      sig2_data <- read.table(gzfile(sig2_path), header = TRUE)
      write.csv(sig2_data, "fithic_pass2_significances.csv", row.names = FALSE)
      saveRDS(sig2_data, "fithic_pass2_significances.rds")
    }

    writeLines(c(
        '"BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS":',
        paste0('    FitHiC: ', as.character(packageVersion('FitHiC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fithic_normalized_analysis.csv versions.yml
    """
}

workflow BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fragsfile.gz, intersfile.gz, biasfile.gz ] ]

    main:
    BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS.out.tables
    plots    = BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS.out.plots
    objects  = BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS.out.objects
    versions = BIOC_FITHIC_FITHIC_NORMALIZED_ANALYSIS.out.versions
}
