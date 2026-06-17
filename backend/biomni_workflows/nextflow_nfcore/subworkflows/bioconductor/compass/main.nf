#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: COMPASS — standard_compass
// Fit a COMPASS model to cell-level marker intensity data using a COMPASSContainer and extract functionality scores.
// Input: data.rds, counts.rds, meta.csv
// Container: quay.io/biocontainers/bioconductor-compass:1.48.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: COMPASS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a COMPASSContainer using COMPASSContainer()
//  * 2. [Core Analysis] Fit the COMPASS model using COMPASS()
//  * 3. [Core Analysis] Extract functionality and polyfunctionality scores using FunctionalityScore() and PolyfunctionalityScore()
//  * 4. [Core Analysis] Extract posterior probabilities using Posterior()
//  * 5. [Visualization & Output] Visualize results using plot() with different measures (PosteriorDiff(), PosteriorLogDiff())

nextflow.enable.dsl = 2

process BIOC_COMPASS_STANDARD_COMPASS {
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
    .bm_deps <- c("COMPASS")
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
    library(COMPASS)
    
    # 1. Read User Input Files
    # - data.rds: list of cell-level marker intensity matrices
    # - counts.rds: named integer vector of total cell counts
    # - meta.csv: sample metadata table
    data <- readRDS("data.rds")
    counts <- readRDS("counts.rds")
    meta <- read.csv("meta.csv", stringsAsFactors = FALSE)
    
    # 2. Construct COMPASSContainer
    CC <- COMPASSContainer(
      data=data,
      counts=counts,
      meta=meta,
      individual_id="iid",
      sample_id="sid"
    )
    
    # 3. Fit the COMPASS Model
    fit <- COMPASS( CC,
      treatment=trt == "Treatment",
      control=trt == "Control",
      iterations=100
    )
    
    # 4. Extract Functionality and Polyfunctionality Scores
    FS <- FunctionalityScore(fit)
    PFS <- PolyfunctionalityScore(fit)
    
    # 5. Extract Posterior Probabilities
    post <- Posterior(fit)
    
    # 6. Save Tabular and Object Outputs
    # Save scores as CSV
    write.csv(data.frame(Individual = names(FS), FunctionalityScore = FS), 
              file = "functionality_scores.csv", row.names = FALSE)
    write.csv(data.frame(Individual = names(PFS), PolyfunctionalityScore = PFS), 
              file = "polyfunctionality_scores.csv", row.names = FALSE)
    
    # Save fit and posterior objects as RDS
    saveRDS(fit, file = "compass_fit.rds")
    saveRDS(post, file = "posterior_probabilities.rds")
    
    # 7. Visualize Results and Save to PDF
    pdf("compass_plots.pdf", width = 10, height = 8)
    
    # Plot mean probability of response heatmap
    tryCatch({
      plot(fit)
    }, error = function(e) {
      warning("Default plot failed: ", e\$message)
    })
    
    # Plot posterior difference heatmap
    tryCatch({
      plot(fit, measure=PosteriorDiff(fit), threshold=0)
    }, error = function(e) {
      warning("PosteriorDiff plot failed: ", e\$message)
    })
    
    # Plot posterior log difference heatmap
    tryCatch({
      plot(fit, measure=PosteriorLogDiff(fit), threshold=0)
    }, error = function(e) {
      warning("PosteriorLogDiff plot failed: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_COMPASS_STANDARD_COMPASS":',
        paste0('    COMPASS: ', as.character(packageVersion('COMPASS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_compass.csv versions.yml
    """
}

workflow BIOC_COMPASS_STANDARD_COMPASS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.rds, counts.rds, meta.csv ] ]

    main:
    BIOC_COMPASS_STANDARD_COMPASS(ch_input)

    emit:
    tables   = BIOC_COMPASS_STANDARD_COMPASS.out.tables
    plots    = BIOC_COMPASS_STANDARD_COMPASS.out.plots
    objects  = BIOC_COMPASS_STANDARD_COMPASS.out.objects
    versions = BIOC_COMPASS_STANDARD_COMPASS.out.versions
}
