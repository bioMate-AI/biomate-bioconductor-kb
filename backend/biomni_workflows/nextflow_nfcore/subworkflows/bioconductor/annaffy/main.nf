#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: annaffy — microarray_annotation_report
// Generate an annotated HTML or tab-delimited text report containing statistical results, expression data, and database-linked annotations for top-ranked probes.
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-annaffy:1.82.0--r45hdfd78af_0
// R packages: annaffy, multtest
// Bioconductor: 3.20 | R: 4.4
// Requires: annaffy, multtest
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the annaffy and multtest packages
//  * 2. [Core Analysis] Calculate test statistics (e.g., t-statistics) and rank probes
//  * 3. [Core Analysis] Select desired annotation columns using aaf.handler()
//  * 4. [Core Analysis] Retrieve probe annotations using aafTableAnn()
//  * 5. [Core Analysis] Format statistical data using aafTable()
//  * 6. [Core Analysis] Extract expression intensities using aafTableInt()
//  * 7. [Core Analysis] Merge annotation, statistical, and expression tables
//  * 8. [Visualization & Output] Export the merged table to HTML and tab-delimited text files

nextflow.enable.dsl = 2

process BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT {
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
    .bm_deps <- c("annaffy", "multtest")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # 1. Load the annaffy and multtest packages
        library("annaffy")
        library(multtest)
        
        # Load the user-provided ExpressionSet from the working directory
        aafExpr <- readRDS("ExpressionSet.rds")
        
        # 2. Calculate test statistics (e.g., t-statistics) and rank probes
        class <- as.integer(as.factor(pData(aafExpr)[[1]])) - 1
        teststat <- mt.teststat(exprs(aafExpr), class)
        index <- order(abs(teststat), decreasing = TRUE)
        probeids <- featureNames(aafExpr)[index]
        
        # 3. Select desired annotation columns using aaf.handler()
        aaf.handler()
        anncols <- aaf.handler()[c(1:3,8:9,11)]
        
        # 4. Retrieve probe annotations using aafTableAnn()
        chip_name <- annotation(aafExpr)
        if (!grepl("\\\\.db\$", chip_name)) {
            chip_name <- paste0(chip_name, ".db")
        }
        anntable <- aafTableAnn(head(probeids, 50), chip_name, anncols)
        
        # 5. Format statistical data using aafTable()
        testtable <- aafTable("t-statistic" = head(teststat[index], 50), signed = TRUE)
        
        # 6. Extract expression intensities using aafTableInt()
        table <- merge(anntable, testtable)
        exprtable <- aafTableInt(aafExpr, probeids = head(probeids, 50))
        
        # 7. Merge annotation, statistical, and expression tables
        table <- merge(table, exprtable)
        
        # 8. Export the merged table to HTML and tab-delimited text files
        saveHTML(table, "example2.html", title = "Example Table with Data")
        saveText(table, "example2.txt")
        
        # Save the final table object as an RDS file for downstream R use
        saveRDS(table, "annotated_report.rds")

    writeLines(c(
        '"BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT":',
        paste0('    annaffy: ', as.character(packageVersion('annaffy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_annotation_report.csv versions.yml
    """
}

workflow BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT(ch_input)

    emit:
    tables   = BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT.out.tables
    plots    = BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT.out.plots
    objects  = BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT.out.objects
    versions = BIOC_ANNAFFY_MICROARRAY_ANNOTATION_REPORT.out.versions
}
