#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: generegionscan — build_probe_level_set
// Extract probe-level intensities from raw CEL files for a specific genomic region and build a ProbeLevelSet object.
// Input: ~/HuEx-1-0-st-v2.na26.hg18.transcript.csv, ~/HuEx-1-0-st-v2.r2.dt1.hg18.full.mps, ~/test-cels, ~/HuEx-1-0-st-v2.r2.clf, ~/HuEx-1-0-st-v2.r2.pgf
// Container: quay.io/biocontainers/bioconductor-generegionscan:1.66.0--r45hdfd78af_0
// R packages: GeneRegionScan
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-generegionscan:1.66.0--r45hdfd78af_0"

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
    .bm_deps <- c("GeneRegionScan")
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
    library(GeneRegionScan)
    
    # Define input file paths as specified by the user
    transcriptClustersFile <- "~/HuEx-1-0-st-v2.na26.hg18.transcript.csv"
    mpsToPsFile <- "~/HuEx-1-0-st-v2.r2.dt1.hg18.full.mps"
    aptCelExtractPath <- "~/apt-bin/apt-cel-extract"
    clfPath <- "~/HuEx-1-0-st-v2.r2.clf"
    pgfPath <- "~/HuEx-1-0-st-v2.r2.pgf"
    celFilesDir <- "~/test-cels"
    
    # --- Find probesets of interest in a genomic region using ---
    message("Stage 1: Finding probesets of interest in the genomic region...")
    listOfProbesets <- getProbesetsFromRegionOfInterest(
      "HuEx-1-0-st-v2", 
      "chr2", 
      215889955, 
      216106710, 
      transcriptClustersFile = transcriptClustersFile, 
      mpsToPsFile = mpsToPsFile
    )
    
    # Save the identified probesets to a text file
    write.table(
      listOfProbesets, 
      file = "listOfProbesets.txt", 
      row.names = FALSE, 
      col.names = FALSE, 
      quote = FALSE
    )
    
    # --- Extract and normalize probe intensities from CEL files ---
    message("Stage 2: Extracting and normalizing probe intensities from CEL files...")
    myProbeLevelSet <- getLocalProbeIntensities(
      listOfProbesets, 
      celFilesDir, 
      aptCelExtractPath = aptCelExtractPath, 
      pgfPath = pgfPath, 
      clfPath = clfPath
    )
    
    # Save the constructed ProbeLevelSet object to an RDS file
    saveRDS(myProbeLevelSet, file = "myProbeLevelSet.rds")
    
    # --- Retrieve probe sequences using getSequence ---
    message("Stage 3: Retrieving probe sequences...")
    probeSequences <- getSequence(myProbeLevelSet, 1:5)
    
    # Save the retrieved sequences to a CSV file
    write.csv(
      data.frame(Probe_Index = 1:5, Sequence = probeSequences), 
      file = "probe_sequences_1_5.csv", 
      row.names = FALSE
    )
    
    message("Workflow completed successfully. Outputs saved to 'listOfProbesets.txt', 'myProbeLevelSet.rds', and 'probe_sequences_1_5.csv'.")

    writeLines(c(
        '"BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET":',
        paste0('        generegionscan: ', as.character(packageVersion("generegionscan")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_build_probe_level_set.csv versions.yml
    """
}

workflow BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ~/HuEx-1-0-st-v2.na26.hg18.transcript.csv, ~/HuEx-1-0-st-v2.r2.dt1.hg18.full.mps, ~/test-cels, ~/HuEx-1-0-st-v2.r2.clf, ~/HuEx-1-0-st-v2.r2.pgf ] ]

    main:
    BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET(ch_input)

    emit:
    tables   = BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET.out.tables
    plots    = BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET.out.plots
    objects  = BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET.out.objects
    versions = BIOC_GENEREGIONSCAN_BUILD_PROBE_LEVEL_SET.out.versions
}
