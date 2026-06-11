#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rcas — multi_sample_meta_analysis
// Compare and contrast multiple transcriptomic samples (e.g. biological replicates or different conditions) using an SQLite database and generate a comparative HT
// Input: myProjDataFile.tsv, annotation.gtf, mySampleDataTable.tsv
// Container: quay.io/biocontainers/bioconductor-rcas:1.36.0--r45hdfd78af_0
// R packages: RCAS, RSQLite, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rcas:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("RCAS", "RSQLite", "knitr")
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
    library(RCAS)
    library(RSQLite)
    library(knitr)
    
    # 1. Define paths to BED files and read the project data frame from user input
    projDataFile <- file.path(getwd(), 'myProjDataFile.tsv')
    if (!file.exists(projDataFile)) {
      stop("Required user input file 'myProjDataFile.tsv' not found in the working directory.")
    }
    projData <- read.table(projDataFile, header = TRUE, sep = '\t', stringsAsFactors = FALSE)
    
    # 2. Write the project data frame to a TSV file (preserving documented call)
    write.table(projData, projDataFile, sep = '\t', quote = FALSE, row.names = FALSE)
    
    # Define path to the reference genome annotation GTF file from user input
    gtfFilePath <- file.path(getwd(), 'annotation.gtf')
    if (!file.exists(gtfFilePath)) {
      stop("Required user input file 'annotation.gtf' not found in the working directory.")
    }
    
    # 3. Create or update an SQLite database
    databasePath <- file.path(getwd(), 'myProject.sqlite')
    
    # Remove pre-existing database to ensure a clean, reproducible run
    if (file.exists(databasePath)) {
      file.remove(databasePath)
    }
    
    invisible(createDB(dbPath = databasePath, projDataFile = projDataFile, gtfFilePath = gtfFilePath, genomeVersion = 'hg19'))
    createDB(dbPath = databasePath, projDataFile = projDataFile, gtfFilePath = gtfFilePath, genomeVersion = 'hg19', update = TRUE)
    
    # 4. Delete specific sample data from the database (wrapped in tryCatch for robustness)
    tryCatch({
      RCAS::deleteSampleDataFromDB(dbPath = databasePath, sampleNames = c('FMR1_1', 'FMR1_2'))
    }, error = function(e) {
      message("Skipped deleting FMR1_1/FMR1_2: ", e\$message)
    })
    
    # 5. Summarize database content and write to a CSV file
    dbSummary <- RCAS::summarizeDatabaseContent(dbPath = databasePath)
    knitr::kable(dbSummary)
    write.csv(dbSummary, file.path(getwd(), 'database_summary.csv'), row.names = FALSE)
    
    # 6. Connect to the database and read tables
    mydb <- RSQLite::dbConnect(RSQLite::SQLite(), databasePath)
    RSQLite::dbListTables(mydb)
    annotationSummaries <- RSQLite::dbReadTable(mydb, 'annotationSummaries')
    write.csv(annotationSummaries, file.path(getwd(), 'annotation_summaries.csv'), row.names = FALSE)
    RSQLite::dbDisconnect(mydb)
    
    # 7. Read the sample data table mapping samples to groups and write to a TSV file
    sampleDataFile <- file.path(getwd(), 'mySampleDataTable.tsv')
    if (!file.exists(sampleDataFile)) {
      stop("Required user input file 'mySampleDataTable.tsv' not found in the working directory.")
    }
    sampleData <- read.table(sampleDataFile, header = TRUE, sep = '\t', stringsAsFactors = FALSE)
    write.table(sampleData, sampleDataFile, sep = '\t', quote = FALSE, row.names = FALSE)
    
    # 8. Generate a comparative meta-analysis HTML report
    runReportMetaAnalysis(dbPath = databasePath, sampleTablePath = sampleDataFile, outFile = file.path(getwd(), 'myProject.html'))

    writeLines(c(
        '"BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS":',
        paste0('        rcas: ', as.character(packageVersion("rcas")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_meta_analysis.csv versions.yml
    """
}

workflow BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ myProjDataFile.tsv, annotation.gtf, mySampleDataTable.tsv ] ]

    main:
    BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS.out.tables
    plots    = BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS.out.plots
    objects  = BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS.out.objects
    versions = BIOC_RCAS_MULTI_SAMPLE_META_ANALYSIS.out.versions
}
