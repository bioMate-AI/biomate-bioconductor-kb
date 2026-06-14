#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GLAD — daglad_analysis
// Detect genomic breakpoints and assign copy number status using the improved DAGLAD algorithm with explicit calling thresholds.
// Input: user_data.txt
// Container: quay.io/biocontainers/bioconductor-glad:2.74.0--r45h1ca3914_0
// R packages: GLAD
// Bioconductor: 3.20 | R: 4.4
// Requires: GLAD
// Visualizations: profile plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert data to a profileCGH object
//  * 2. [Core Analysis] Run the daglad segmentation and calling algorithm with custom thresholds
//  * 3. [Visualization & Output] Plot the genomic profile with threshold lines

nextflow.enable.dsl = 2

process BIOC_GLAD_DAGLAD_ANALYSIS {
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
    .bm_deps <- c("GLAD")
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
    library(GLAD)
    
    # Read user input data
    # The file must contain at least: LogRatio, Chromosome, PosOrder
    user_data <- read.table("user_data.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Convert the input data frame to a profileCGH object
    profileCGH <- as.profileCGH(user_data)
    
    # Retrieve cytoband data from the package namespace without using data()
    cytoband <- NULL
    tryCatch({
      cytoband <- get0("cytoband", envir = asNamespace("GLAD"))
    }, error = function(e) {
      warning("Could not load cytoband annotation from GLAD package.")
    })
    
    # Run the daglad segmentation and calling algorithm with custom thresholds
    profileCGH <- daglad(profileCGH, mediancenter=FALSE, normalrefcenter=FALSE, genomestep=FALSE,
                         smoothfunc="lawsglad", lkern="Exponential", model="Gaussian",
                         qlambda=0.999,  bandwidth=10, base=FALSE, round=1.5,
                         lambdabreak=8, lambdaclusterGen=40, param=c(d=6), alpha=0.001, msize=2,
                         method="centroid", nmin=1, nmax=8,
                         amplicon=1, deletion=-5, deltaN=0.2,  forceGL=c(-0.3,0.3), nbsigma=3,
                         MinBkpWeight=0.35, CheckBkpPos=TRUE)
    
    # Save the full profileCGH object as an RDS file
    saveRDS(profileCGH, file = "daglad_profileCGH.rds")
    
    # Save the profile values (including segmentation and status calls) as a CSV table
    if (!is.null(profileCGH\$profileValues)) {
      write.csv(profileCGH\$profileValues, file = "daglad_results.csv", row.names = FALSE)
    }
    
    # Plot the genomic profile with threshold lines and save to a PDF
    pdf("genomic_profile.pdf", width = 10, height = 6)
    plotProfile(profileCGH, Smoothing="Smoothing", Bkp=TRUE, plotband=FALSE, cytoband = cytoband)
    abline(h=c(-0.3,-0.2,0.2,0.3),col=c("green","black","black","red"))
    axis(2,at=c(-0.3,-0.2,0.2,0.3), labels=c("forceGL[1]","-deltaN","+deltaN","forceGL[2]"), las=2)
    dev.off()

    writeLines(c(
        '"BIOC_GLAD_DAGLAD_ANALYSIS":',
        paste0('    GLAD: ', as.character(packageVersion('GLAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_daglad_analysis.csv versions.yml
    """
}

workflow BIOC_GLAD_DAGLAD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_data.txt ] ]

    main:
    BIOC_GLAD_DAGLAD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GLAD_DAGLAD_ANALYSIS.out.tables
    plots    = BIOC_GLAD_DAGLAD_ANALYSIS.out.plots
    objects  = BIOC_GLAD_DAGLAD_ANALYSIS.out.objects
    versions = BIOC_GLAD_DAGLAD_ANALYSIS.out.versions
}
