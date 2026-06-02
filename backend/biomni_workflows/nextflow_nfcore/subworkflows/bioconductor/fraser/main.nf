#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FRASER
// Detection of rare aberrant splicing events in transcriptome profiles. Read count ratio expectations 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FRASER/inst/doc/FRASER.R
// Upstream  : BiocParallel
// Downstream: none
//
// Install: BiocManager::install("FRASER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRASER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fraser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fraser:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fraser:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fraser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fraser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fraser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FRASER)
    library(FraserDataSet)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- register [] ---
    # Key functions: register
    library(BiocParallel)
    register(SerialParam())
    # --- quick fraser guide [] ---
    # Key functions: createTestFraserSettings, countRNAData, calculatePSIValues, filterExpressionAndVariability, annotateRangesWithTxDb
    library(FRASER)
    fds <- createTestFraserSettings()
    fds <- countRNAData(fds)
    # --- sampleData Table [] ---
    # Key functions: fread
    sampleTable <- fread(system.file(
    head(sampleTable)
    # --- FRASER setting example1 [] ---
    # Key functions: FraserDataSet
    bamFiles <- system.file(sampleTable[,bamFile], package="FRASER", mustWork=TRUE)
    settings <- FraserDataSet(colData=sampleTable, workingDir="FRASER_output")
    # --- FRASER setting example2 [] ---
    # Key functions: createTestFraserSettings
    settings <- createTestFraserSettings()
    # --- parallelize example [] ---
    # Key functions: register
    if(.Platform$OS.type == "unix") {
    register(MulticoreParam(workers=min(10, multicoreWorkers())))
    register(SnowParam(workers=min(10, multicoreWorkers())))
    # --- count R N A Data [] ---
    # Key functions: countRNAData
    fds <- countRNAData(settings)
    # --- create fds with counts [] ---
    # Key functions: fread, FraserDataSet
    sampleTable <- fread(system.file("extdata", "sampleTable_countTable.tsv",
    head(sampleTable)
    junctionCts   <- fread(system.file("extdata", "raw_junction_counts.tsv.gz",
    # --- calculate psi/jaccard values [] ---
    # Key functions: calculatePSIValues
    fds <- calculatePSIValues(fds)
    # --- filter junctions [] ---
    # Key functions: filterExpressionAndVariability, plotFilterExpression
    fds <- filterExpressionAndVariability(fds, minDeltaPsi=0, filter=FALSE)
    plotFilterExpression(fds, bins=100)
    # --- sample covariation [] ---
    # Key functions: plotCountCorHeatmap
    plotCountCorHeatmap(fds, type="jaccard", logit=TRUE, normalized=FALSE)
    # --- intron sample correlation [] ---
    # Key functions: plotCountCorHeatmap
    plotCountCorHeatmap(fds, type="jaccard", logit=TRUE, normalized=FALSE,
    # --- F R A S E R [] ---
    # Key functions: FRASER
    fds <- FRASER(fds, q=c(jaccard=3))
    # --- covariation after fitting [] ---
    # Key functions: plotCountCorHeatmap
    plotCountCorHeatmap(fds, type="jaccard", normalized=TRUE, logit=TRUE)
    # --- Extract differential expression results [] ---
    # Key functions: annotateRangesWithTxDb, annotateRanges, results
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    fds <- annotateRangesWithTxDb(fds, txdb=txdb, orgDb=orgDb)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fraser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fraser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fraser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FRASER:", paste0("    fraser: ", packageVersion("FRASER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fraser_results.csv
    touch ${prefix}_fraser_output.rds
    echo "BIOC_FRASER:" > versions.yml
    echo "    fraser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FRASER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FRASER(ch_input)

    emit:
    results  = BIOC_FRASER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FRASER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FRASER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FRASER.out.versions  // channel: path(versions.yml)
}
