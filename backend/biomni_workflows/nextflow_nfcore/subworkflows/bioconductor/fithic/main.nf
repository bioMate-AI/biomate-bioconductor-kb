#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FitHiC — fithic_standard_analysis
// Run Fit-Hi-C on raw Hi-C contact maps without normalization bias files to estimate interaction significance.
// Input: fragsfile.gz, intersfile.gz
// Container: quay.io/biocontainers/bioconductor-fithic:1.36.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FitHiC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define paths to input files and output directory
//  * 2. [Core Analysis] Run the FitHiC function to perform spline fitting and calculate p-values/q-values

nextflow.enable.dsl = 2

process BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS {
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
        
        # 1. Define paths to input files and output directory
        fragsfile <- "fragsfile.gz"
        intersfile <- "intersfile.gz"
        libname <- "fithic_run"
        outdir <- file.path(getwd(), libname)
        
        # Verify that the required user input files exist
        if (!file.exists(fragsfile)) {
          stop(paste("Required input file missing:", fragsfile))
        }
        if (!file.exists(intersfile)) {
          stop(paste("Required input file missing:", intersfile))
        }
        
        # Create output directory if it doesn't exist
        if (!dir.exists(outdir)) {
          dir.create(outdir, recursive = TRUE)
        }
        
        # 2. Run the FitHiC function to perform spline fitting and calculate p-values/q-values
        library("FitHiC")
        
        FitHiC(fragsfile, intersfile, outdir,
            libname=libname, visual=TRUE)
        
        # 3. Post-processing: Export meaningful results to standard formats (CSV and RDS)
        tryCatch({
          # Define expected output file paths from Fit-Hi-C
          pass1_stats_path <- file.path(outdir, paste0(libname, ".fithic_pass1.txt"))
          pass2_stats_path <- file.path(outdir, paste0(libname, ".fithic_pass2.txt"))
          pass1_sig_path <- file.path(outdir, paste0(libname, ".spline_pass1.significances.txt.gz"))
          pass2_sig_path <- file.path(outdir, paste0(libname, ".spline_pass2.significances.txt.gz"))
        
          # Read and save Pass 2 significances (the final model results)
          if (file.exists(pass2_sig_path)) {
            sig_data <- read.table(gzfile(pass2_sig_path), header = TRUE)
            
            # Save as CSV
            write.csv(sig_data, file = file.path(outdir, "fithic_final_significances.csv"), row.names = FALSE)
            
            # Save as RDS
            saveRDS(sig_data, file = file.path(outdir, "fithic_final_significances.rds"))
            
            message("Successfully exported final significances to CSV and RDS.")
          }
        
          # Read and save Pass 2 probability binning stats
          if (file.exists(pass2_stats_path)) {
            stats_data <- read.table(pass2_stats_path, header = TRUE)
            write.csv(stats_data, file = file.path(outdir, "fithic_pass2_stats.csv"), row.names = FALSE)
            saveRDS(stats_data, file = file.path(outdir, "fithic_pass2_stats.rds"))
            message("Successfully exported fit statistics to CSV and RDS.")
          }
        }, error = function(e) {
          warning("Post-processing of Fit-Hi-C output files failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS":',
        paste0('    FitHiC: ', as.character(packageVersion('FitHiC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fithic_standard_analysis.csv versions.yml
    """
}

workflow BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fragsfile.gz, intersfile.gz ] ]

    main:
    BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS.out.tables
    plots    = BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS.out.plots
    objects  = BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS.out.objects
    versions = BIOC_FITHIC_FITHIC_STANDARD_ANALYSIS.out.versions
}
