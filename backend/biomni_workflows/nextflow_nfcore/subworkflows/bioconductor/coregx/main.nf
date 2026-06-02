#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CoreGx
// A collection of functions and classes which serve as the foundation for our lab's suite of R package
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CoreGx/inst/doc/TreatmentResponseExperiment.R
// Upstream  : Biobase, SummarizedExperiment
// Downstream: PharmacoGx, RadioGx, ToxicoGx
//
// Install: BiocManager::install("CoreGx")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COREGX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-coregx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-coregx:2.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-coregx:2.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_coregx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_coregx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_coregx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TREDataMapper)
    library(jsonlite)


    # --- Class Diagram [] ---
    # Key functions: include_graphics
    knitr::include_graphics('TreatmentResponseExperimentClassDiagram.drawio.png')
    knitr::include_graphics('TreatmentResponseExperimentStructure.drawio.png')

    # --- Head Data [] ---
    # Key functions: fread
    filePath <- system.file('extdata', 'merckLongTable.csv', package='CoreGx',
      mustWork=TRUE)
    merckDT <- fread(filePath, na.strings=c('NULL'))
    colnames(merckDT)
    knitr::kable(head(merckDT)[, 1:5])

    # --- Sample Data2 [] ---
    # Key functions: TREDataMapper, guessMapping
    knitr::kable(head(merckDT)[, 5:ncol(merckDT)])
    # Our guesses of how we may identify rows, columns and assays
    groups <- list(
      justDrugs=c('drug1id', 'drug2id'),
      drugsAndDoses=c('drug1id', 'drug2id', 'drug1dose', 'drug2dose'),
      justCells=c('cellid'),
      cellsAndBatches=c('cellid', 'batchid'),
      assays1=c('drug1id', 'drug2id', 'cellid'),
      assays2=c('drug1id', 'drug2id', 'drug1dose', 'drug2dose', 'cellid', 'batchid')
    )

    # --- Mappings To Datamapper [] ---
    # Key functions: rowDataMap, colDataMap
    rowDataMap(TREdataMapper) <- guess$drugsAndDose
    colDataMap(TREdataMapper) <- guess$cellsAndBatches
    assays <- list(
      sensitivity=list(
        guess$assays2[[1]],
        guess$assays2[[2]][seq_len(4)]
      ),
      profiles=list(
        guess$assays2[[1]],
        guess$assays2[[2]][c(5, 6)]
      )
    )

    # --- Assign Assaymap [] ---
    # Key functions: assayMap
    assayMap(TREdataMapper) <- assays
    head(rownames(tre))

    # --- Colnames [] ---
    # Key functions: coregx
    head(colnames(tre))
    row <- rownames(tre)[1]
    columns <- colnames(tre)[1:2]
    tre[row, columns]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_coregx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_coregx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_coregx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COREGX:", paste0("    coregx: ", packageVersion("CoreGx"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coregx_results.csv
    touch ${prefix}_coregx_output.rds
    echo "BIOC_COREGX:" > versions.yml
    echo "    coregx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COREGX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COREGX(ch_input)

    emit:
    results  = BIOC_COREGX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COREGX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COREGX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COREGX.out.versions  // channel: path(versions.yml)
}
