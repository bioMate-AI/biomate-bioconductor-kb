#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaseqr2 — annotation_db_build
// Build a local SQLite database with standard or custom genome annotations for offline use in the metaseqr2 pipeline.
// Input: Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz, Dasnov3.broad.Ascending_Colon_5.1.bam
// Container: quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0
// R packages: metaseqR2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METASEQR2_ANNOTATION_DB_BUILD {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0"

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
    .bm_deps <- c("metaseqR2")
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
    
    library(metaseqR2)
    
    # Define output directory and database path
    buildDir <- "annotation_db_output"
    if (!dir.exists(buildDir)) {
        dir.create(buildDir, recursive = TRUE)
    }
    myDb <- file.path(buildDir, "testann.sqlite")
    
    # Stage 1: Define organisms and sources
    organisms <- list(mm39=115)
    sources <- ifelse(.Platform\$OS.type=="unix", c("ensembl","refseq"), "ensembl")
    
    # Stage 2: Build standard annotation database using buildAnnotationDatabase
    message("Building standard annotation database...")
    buildAnnotationDatabase(organisms, sources, forceDownload=FALSE, db=myDb, rc=0.5)
    
    # Stage 3: Build custom annotation database from GTF using buildCustomAnnotation
    # Read user input files from the working directory
    gtfFile_input <- "Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz"
    bamFile_input <- "Dasnov3.broad.Ascending_Colon_5.1.bam"
    
    if (!file.exists(gtfFile_input)) {
        stop(paste("Required GTF input file not found in working directory:", gtfFile_input))
    }
    
    bamForInfo <- NULL
    if (file.exists(bamFile_input)) {
        bamForInfo <- bamFile_input
    } else {
        message("Optional BAM file not found in working directory, proceeding without BAM chromosome info.")
    }
    
    message("Building custom annotation...")
    buildCustomAnnotation(
        gtfFile=gtfFile_input,
        metadata=list(
            organism="dasNov3_test",
            source="ensembl_test",
            chromInfo=bamForInfo
        ),
        db=myDb
    )
    
    # Stage 4: Load and verify annotations using loadAnnotation
    message("Loading and verifying custom annotation...")
    dasGenes <- loadAnnotation(
        genome="dasNov3_test",
        refdb="ensembl_test",
        level="gene",
        type="gene",
        db=myDb
    )
    
    # Write named output files for the results
    saveRDS(dasGenes, file=file.path(buildDir, "dasGenes.rds"))
    
    # Export as CSV for easy inspection
    if (inherits(dasGenes, "GRanges")) {
        dasGenes_df <- as.data.frame(dasGenes)
        write.csv(dasGenes_df, file=file.path(buildDir, "dasGenes.csv"), row.names=FALSE)
    } else {
        write.csv(dasGenes, file=file.path(buildDir, "dasGenes.csv"), row.names=FALSE)
    }
    
    message("Pipeline completed successfully. Outputs saved to: ", buildDir)

    writeLines(c(
        '"BIOC_METASEQR2_ANNOTATION_DB_BUILD":',
        paste0('        metaseqr2: ', as.character(packageVersion("metaseqr2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotation_db_build.csv versions.yml
    """
}

workflow BIOC_METASEQR2_ANNOTATION_DB_BUILD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz, Dasnov3.broad.Ascending_Colon_5.1.bam ] ]

    main:
    BIOC_METASEQR2_ANNOTATION_DB_BUILD(ch_input)

    emit:
    tables   = BIOC_METASEQR2_ANNOTATION_DB_BUILD.out.tables
    plots    = BIOC_METASEQR2_ANNOTATION_DB_BUILD.out.plots
    objects  = BIOC_METASEQR2_ANNOTATION_DB_BUILD.out.objects
    versions = BIOC_METASEQR2_ANNOTATION_DB_BUILD.out.versions
}
