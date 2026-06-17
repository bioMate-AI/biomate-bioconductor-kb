#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SIMAT — gc_sim_ms_analysis
// Process raw GC-SIM-MS data to identify target peaks, perform retention index calibration, and calculate similarity scores.
// Input: Run, target.table, Library, RItable
// Container: quay.io/biocontainers/bioconductor-simat:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SIMAT
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the raw run data, target table, reference library, and RI standards
//  * 2. [Visualization & Output] Plot the Total Ion Chromatogram (TIC)
//  * 3. [Core Analysis] Retrieve target information using getTarget
//  * 4. [Core Analysis] Detect peaks in the run using getPeak
//  * 5. [Visualization & Output] Plot the Extracted Ion Chromatogram (EIC) for visual inspection
//  * 6. [Core Analysis] Generate a retention index calibration function using getRI and re-detect peaks with RI adjustment
//  * 7. [Visualization & Output] Calculate and plot similarity scores using getPeakScore

nextflow.enable.dsl = 2

process BIOC_SIMAT_GC_SIM_MS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("SIMAT")
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
    
    # Load the required Bioconductor package
    library(SIMAT)
    
    # 1. Load the raw run data, target table, reference library, and RI standards
    # Reading the declared user input files from the working directory
    Run <- readRDS("Run.rds")
    target.table <- readRDS("target.table.rds")
    Library <- readRDS("Library.rds")
    RItable <- readRDS("RItable.rds")
    
    # 2. Plot the Total Ion Chromatogram (TIC)
    pdf("TIC_plot.pdf")
    plotTIC(Run = Run)
    dev.off()
    
    # 3. Retrieve target information using getTarget
    Targets <- getTarget(Method = "library", Library = Library, target.table = target.table)
    saveRDS(Targets, "Targets.rds")
    
    # 4. Detect peaks in the run using getPeak
    runPeaks <- getPeak(Run = Run, Targets = Targets)
    saveRDS(runPeaks, "runPeaks.rds")
    
    # 5. Plot the Extracted Ion Chromatogram (EIC) for visual inspection
    pdf("EIC_plot.pdf")
    plotEIC(peakEIC = runPeaks[[1]][[1]])
    dev.off()
    
    # 6. Generate a retention index calibration function using getRI and re-detect peaks with RI adjustment
    calibRI <- getRI(RItable)
    saveRDS(calibRI, "calibRI.rds")
    
    runPeaksRI <- getPeak(Run = Run, Targets = Targets, calibRI = calibRI)
    saveRDS(runPeaksRI, "runPeaksRI.rds")
    
    # 7. Calculate and plot similarity scores using getPeakScore
    pdf("PeakScore_histogram.pdf")
    Scores <- getPeakScore(runPeaks = runPeaks, plot = TRUE)
    dev.off()
    
    # Save the calculated similarity scores
    write.csv(Scores, "Scores.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SIMAT_GC_SIM_MS_ANALYSIS":',
        paste0('    SIMAT: ', as.character(packageVersion('SIMAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gc_sim_ms_analysis.csv versions.yml
    """
}

workflow BIOC_SIMAT_GC_SIM_MS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Run, target.table, Library, RItable ] ]

    main:
    BIOC_SIMAT_GC_SIM_MS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SIMAT_GC_SIM_MS_ANALYSIS.out.tables
    plots    = BIOC_SIMAT_GC_SIM_MS_ANALYSIS.out.plots
    objects  = BIOC_SIMAT_GC_SIM_MS_ANALYSIS.out.objects
    versions = BIOC_SIMAT_GC_SIM_MS_ANALYSIS.out.versions
}
