#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MMDiff2 — chipseq_shape_diff_analysis
// Detect statistically significant differences in ChIP-Seq read enrichment profiles (peak shapes) between different conditions.
// Input: sampleSheet.csv, peaks.GRanges, sorted_indexed.bam
// Container: quay.io/biocontainers/bioconductor-mmdiff2:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Mmusculus.UCSC.mm9, GenomicRanges, MMDiff2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize metadata and DBAmmd object (DBAmmd)
//  * 2. [Core Analysis] Set regions of interest (setRegions)
//  * 3. [Core Analysis] Retrieve peak reads from BAM files (getPeakReads)
//  * 4. [Core Analysis] Estimate fragment centers (estimateFragmentCenters)
//  * 5. [Core Analysis] Compute peak histograms (compHists)
//  * 6. [Core Analysis] Compute pairwise distances between samples (compDists)
//  * 7. [Core Analysis] Set experimental contrast (setContrast)
//  * 8. [Core Analysis] Compute p-values for differential shape testing (compPvals)
//  * 9. [Visualization & Output] Report and visualize results (reportResults, plotDists, plotPeak, plotDISTS4Peak, runShinyMMDiff2)

nextflow.enable.dsl = 2

process BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("MMDiff2", "GenomicRanges", "BSgenome.Mmusculus.UCSC.mm9")
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
    library(MMDiff2)
    library(GenomicRanges)
    library(BSgenome.Mmusculus.UCSC.mm9)
    
    # 1. Initialize metadata and DBAmmd object
    # We read from the current working directory where the user's files are located.
    ExperimentData <- list(
      genome = 'BSgenome.Mmusculus.UCSC.mm9',
      dataDir = '.',
      sampleSheet = 'sampleSheet.csv'
    )
    MetaData <- list('ExpData' = ExperimentData)
    MMD <- DBAmmd(MetaData)
    
    # 2. Set regions of interest
    # Read the GenomicRanges object from the user-provided 'peaks.GRanges' RDS file
    Peaks <- readRDS("peaks.GRanges")
    MMD <- setRegions(MMD, Peaks)
    
    # 3. Retrieve peak reads from BAM files
    MMD <- getPeakReads(MMD)
    
    # 4. Estimate fragment centers
    MMD <- estimateFragmentCenters(MMD)
    
    # 5. Compute peak histograms
    MMD <- compHists(MMD, bin.length = 20, whichPos = "Center")
    
    # 6. Compute pairwise distances between samples
    MMD <- compDists(MMD, dist.method = "MMD", run.parallel = FALSE)
    
    # 7. Set experimental contrast
    MMD <- setContrast(MMD, contrast = 'byCondition')
    
    # 8. Compute p-values for differential shape testing
    MMD <- compPvals(MMD, dist.method = 'MMD')
    
    # 9. Report and visualize results
    # Save tabular results
    res <- reportResults(MMD)
    write.csv(as.data.frame(res), file = "MMDiff2_results.csv", row.names = TRUE)
    
    # Save plots to a PDF file
    pdf("MMDiff2_plots.pdf", width = 8, height = 6)
    
    # Plot distances summary
    tryCatch({
      plotDists(
        MMD,
        dist.method = 'MMD',
        whichContrast = 1,
        diff.method = 'MMD.locfit',
        bUsePval = FALSE,
        th = 0.1,
        title = NULL,
        what = 3,
        xlim = NULL,
        ylim = NULL,
        Peak.IDs = NULL,
        withLegend = TRUE
      )
    }, error = function(e) {
      warning("Could not plot distances: ", e\$message)
    })
    
    # Plot specific peak details if peaks are reported
    Peak.ids <- names(res)
    if (length(Peak.ids) > 0) {
      tryCatch({
        plotPeak(
          MMD,
          Peak.id = Peak.ids[1],
          NormMethod = NULL,
          plot.input = FALSE,
          whichPos = "Center",
          whichContrast = 1
        )
      }, error = function(e) {
        warning("Could not plot peak: ", e\$message)
      })
      
      tryCatch({
        plotDISTS4Peak(
          MMD,
          Peak.id = Peak.ids[1],
          dist.method = 'MMD',
          whichContrast = 1,
          Zoom = TRUE
        )
      }, error = function(e) {
        warning("Could not plot distances for peak: ", e\$message)
      })
    }
    
    dev.off()
    
    # Save the final DBAmmd object
    saveRDS(MMD, file = "MMD_object.rds")
    
    # Run Shiny app only if in an interactive session
    if (interactive()) {
      runShinyMMDiff2(MMD)
    }

    writeLines(c(
        '"BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS":',
        paste0('    MMDiff2: ', as.character(packageVersion('MMDiff2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseq_shape_diff_analysis.csv versions.yml
    """
}

workflow BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleSheet.csv, peaks.GRanges, sorted_indexed.bam ] ]

    main:
    BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS.out.tables
    plots    = BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS.out.plots
    objects  = BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS.out.objects
    versions = BIOC_MMDIFF2_CHIPSEQ_SHAPE_DIFF_ANALYSIS.out.versions
}
