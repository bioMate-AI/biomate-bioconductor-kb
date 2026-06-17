#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Scale4C — scale_space_analysis
// Perform scale-space transformation, singularity tracking, manual correction, and tesselation visualization on 4C-seq fragment data.
// Input: liverData.csv, vp.txt
// Container: quay.io/biocontainers/bioconductor-scale4c:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Scale4C
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import raw fragment data using importBasic4CseqData
//  * 2. [Core Analysis] Initialize the Scale4C object using Scale4C
//  * 3. [Core Analysis] Add points of interest using addPointsOfInterest and pointsOfInterest<-
//  * 4. [Visualization & Output] Plot inflection points for specific sigma values using plotInflectionPoints
//  * 5. [Core Analysis] Calculate the scale-space matrix using calculateScaleSpace
//  * 6. [Core Analysis] Compute the fingerprint map using calculateFingerprintMap
//  * 7. [Core Analysis] Identify and track singularities using findSingularities
//  * 8. [Core Analysis] Manually correct or add singularities (e.g., viewpoint singularity) in the GRanges object
//  * 9. [Visualization & Output] Plot the final tesselation map using plotTesselation
//  * 10. [Visualization & Output] Export the scale-space tree structure using outputScaleSpaceTree

nextflow.enable.dsl = 2

process BIOC_SCALE4C_SCALE_SPACE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Scale4C", "GenomicRanges")
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
    library(Scale4C)
    library(GenomicRanges)
    
    # 1. Import raw fragment data using importBasic4CseqData
    csvFile <- "liverData.csv"
    liverReads <- importBasic4CseqData(
      csvFile, 
      viewpoint = 21160072, 
      viewpointChromosome = "chr10", 
      distance = 1000000
    )
    
    # 2. Initialize the Scale4C object using Scale4C
    liverData <- Scale4C(
      rawData = liverReads, 
      viewpoint = 21160072, 
      viewpointChromosome = "chr10"
    )
    
    # 3. Add points of interest using addPointsOfInterest and pointsOfInterest<-
    poiFile <- "vp.txt"
    pointsOfInterest(liverData) <- addPointsOfInterest(
      liverData, 
      read.csv(poiFile, sep = "\t", stringsAsFactors = FALSE)
    )
    
    # 4. Plot inflection points for specific sigma values using plotInflectionPoints
    pdf("inflection_points_sigma_2.pdf")
    plotInflectionPoints(liverData, 2, fileName = "", plotIP = FALSE)
    dev.off()
    
    pdf("inflection_points_sigma_50.pdf")
    plotInflectionPoints(liverData, 50, fileName = "", plotIP = FALSE)
    dev.off()
    
    # 5. Calculate the scale-space matrix using calculateScaleSpace
    # We use maxSQSigma = 2000 to allow full tracking and manual correction matching the vignette
    scaleSpace(liverData) <- calculateScaleSpace(liverData, maxSQSigma = 2000)
    
    # 6. Compute the fingerprint map using calculateFingerprintMap
    liverData <- calculateFingerprintMap(liverData, maxSQSigma = 2000)
    
    # 7. Identify and track singularities using findSingularities
    singularities(liverData) <- findSingularities(liverData, 1, guessViewpoint = FALSE)
    
    # 8. Manually correct or add singularities (e.g., viewpoint singularity) in the GRanges object
    # Add viewpoint singularity
    singularities(liverData) <- c(
      singularities(liverData), 
      GRanges("chr10", IRanges(39, 42), "*", "sqsigma" = 2000, "left" = 40, "right" = 41, "type" = "peak")
    )
    
    # Correct singularity's coordinates
    tempSingularities <- singularities(liverData)
    if (length(tempSingularities) >= 30) {
      tempSingularities\$left[30] <- 235
      tempSingularities\$right[30] <- 250
      tempSingularities\$type[30] <- "peak"
    }
    singularities(liverData) <- tempSingularities
    
    # 9. Plot the final tesselation map using plotTesselation
    pdf("tesselation_plot.pdf")
    plotTesselation(liverData, fileName = "")
    dev.off()
    
    # 10. Export the scale-space tree structure using outputScaleSpaceTree
    scaleSpaceTree <- outputScaleSpaceTree(liverData, useLog = FALSE)
    write.csv(as.data.frame(scaleSpaceTree), "scale_space_tree.csv", row.names = FALSE)
    
    # Save the final processed Scale4C object
    saveRDS(liverData, "liverData_processed.rds")

    writeLines(c(
        '"BIOC_SCALE4C_SCALE_SPACE_ANALYSIS":',
        paste0('    Scale4C: ', as.character(packageVersion('Scale4C')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scale_space_analysis.csv versions.yml
    """
}

workflow BIOC_SCALE4C_SCALE_SPACE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ liverData.csv, vp.txt ] ]

    main:
    BIOC_SCALE4C_SCALE_SPACE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCALE4C_SCALE_SPACE_ANALYSIS.out.tables
    plots    = BIOC_SCALE4C_SCALE_SPACE_ANALYSIS.out.plots
    objects  = BIOC_SCALE4C_SCALE_SPACE_ANALYSIS.out.objects
    versions = BIOC_SCALE4C_SCALE_SPACE_ANALYSIS.out.versions
}
