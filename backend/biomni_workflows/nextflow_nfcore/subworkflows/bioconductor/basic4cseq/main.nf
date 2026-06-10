#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Basic4Cseq — standard_4cseq_analysis
// Perform a complete 4C-seq analysis workflow from virtual fragment library creation and read mapping to normalization, quality control, and near-cis visualizatio
// Input: fetalLiverShort.bam, fetalLiverVP.bed, BSgenome.Mmusculus.UCSC.mm9
// Container: quay.io/biocontainers/bioconductor-basic4cseq:1.46.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm9, Basic4Cseq, caTools, GenomicAlignments, rcircos
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Mmusculus.UCSC.mm9, Basic4Cseq, GenomicAlignments, caTools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a virtual fragment library for the restriction enzymes and genome
//  * 2. [Input & Preparation] Load aligned reads and points of interest
//  * 3. [Core Analysis] Initialize the Data4Cseq object
//  * 4. [Core Analysis] Map reads to the virtual fragment library
//  * 5. [Core Analysis] Select near-cis fragments around the viewpoint
//  * 6. [Input & Preparation] Normalize fragment read counts (RPM)
//  * 7. [Input & Preparation] Perform quality control on read distribution
//  * 8. [Visualization & Output] Visualize near-cis interactions using coverage plots and heatmaps

nextflow.enable.dsl = 2

process BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm9", "Basic4Cseq", "caTools", "GenomicAlignments", "rcircos")
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
        library(Basic4Cseq)
        library(BSgenome.Mmusculus.UCSC.mm9)
        library(GenomicAlignments)
        library(caTools)
        
        # 1. Create a virtual fragment library for the restriction enzymes and genome
        # We use the installed BSgenome.Mmusculus.UCSC.mm9 (Mmusculus)
        libraryFile <- "myFullFetalLiverVFL.csv"
        createVirtualFragmentLibrary(
          chosenGenome = Mmusculus,
          firstCutter = "aagctt",
          secondCutter = "catg",
          readLength = 54,
          libraryName = libraryFile,
          useOnlyIndex = TRUE
        )
        
        # 2. Load aligned reads and points of interest from user input files
        bamFile <- "fetalLiverShort.bam"
        liverReads <- readGAlignments(bamFile)
        
        pointsOfInterestFile <- "fetalLiverVP.bed"
        liverPoints <- readPointsOfInterestFile(pointsOfInterestFile)
        
        # 3. Initialize the Data4Cseq object
        liverData <- Data4Cseq(
          viewpointChromosome = "10",
          viewpointInterval = c(20879870, 20882209),
          readLength = 54,
          pointsOfInterest = liverPoints,
          rawReads = liverReads
        )
        
        # 4. Map reads to the virtual fragment library
        rawFragments(liverData) <- readsToFragments(liverData, libraryFile)
        
        # 5. Select near-cis fragments around the viewpoint
        nearCisFragments(liverData) <- chooseNearCisFragments(
          liverData,
          regionCoordinates = c(20800000, 21100000)
        )
        
        # 6. Normalize fragment read counts (RPM)
        nearCisFragments(liverData) <- normalizeFragmentData(liverData)
        
        # Save the normalized near-cis fragments to a CSV file
        write.csv(
          nearCisFragments(liverData),
          file = "fetalLiver_nearCis_fragments_normalized.csv",
          row.names = FALSE
        )
        
        # 7. Perform quality control on read distribution
        getReadDistribution(
          liverData,
          useFragEnds = TRUE,
          outputName = "fetalLiver_read_distribution.txt"
        )
        
        # 8. Visualize near-cis interactions using coverage plots and heatmaps
        # Save coverage plot as PDF
        visualizeViewpoint(
          liverData,
          plotFileName = "fetalLiver_nearCis_plot.pdf",
          mainColour = "blue",
          plotTitle = "Fetal Liver Near-Cis Plot",
          loessSpan = 0.1,
          maxY = 6000,
          xAxisIntervalLength = 50000,
          yAxisIntervalLength = 1000
        )
        
        # Save heatmap as PDF
        drawHeatmap(
          liverData,
          plotFileName = "fetalLiver_heatmap.pdf",
          xAxisIntervalLength = 50000,
          bands = 5
        )
        
        # Save the final Data4Cseq object as an RDS file
        saveRDS(liverData, file = "fetalLiver_Data4Cseq_analyzed.rds")

    writeLines(c(
        '"BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS":',
        paste0('    Basic4Cseq: ', as.character(packageVersion('Basic4Cseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_4cseq_analysis.csv versions.yml
    """
}

workflow BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fetalLiverShort.bam, fetalLiverVP.bed, BSgenome.Mmusculus.UCSC.mm9 ] ]

    main:
    BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS.out.tables
    plots    = BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS.out.plots
    objects  = BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS.out.objects
    versions = BIOC_BASIC4CSEQ_STANDARD_4CSEQ_ANALYSIS.out.versions
}
