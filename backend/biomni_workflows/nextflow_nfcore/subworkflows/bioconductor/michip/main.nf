#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MiChip
// This package takes the MiChip miRNA microarray .grp scanner output files and parses these out, provi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MiChip/inst/doc/MiChip.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MiChip")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICHIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-michip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-michip:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-michip:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_michip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_michip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_michip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MiChip)
    library(jsonlite)

    # --- Defaultrawdata [] ---
    # Key functions: parseRawData
    datadir <-system.file("extdata", package="MiChip")
    defaultRawData <- parseRawData(datadir)
    # --- Noe [] ---
    # Key functions: removeUnwantedRows
    noEmptiesDataSet <- removeUnwantedRows(defaultRawData, c("Empty"))
    # --- Humandataset [] ---
    # Key functions: standardRemoveRows
    humanDataSet <- standardRemoveRows(defaultRawData)
    # --- Flagcorrectdataset [] ---
    # Key functions: correctForFlags
    flagCorrectedDataSet <- correctForFlags(humanDataSet)
    # --- Flagcorrecteddataset [] ---
    # Key functions: correctForFlags
    flagCorrectedDataSet <- correctForFlags(humanDataSet, intensityCutoff = 50)
    # --- Summeddata [] ---
    # Key functions: summarizeIntensitiesAsMedian
    summedData <- summarizeIntensitiesAsMedian(flagCorrectedDataSet,minSumlength = 0, madAdjust=FALSE)
    # --- Plotintensities [] ---
    # Key functions: plotIntensitiesScatter, exprs
    plotIntensitiesScatter(exprs(summedData), NULL, "MiChipDemX", "SummarizedScatter")
    # --- Boxplotsummed [] ---
    # Key functions: boxplotData, exprs
    boxplotData(exprs(summedData), "MiChipDemX", "Summarized")
    # --- Mednormeddata [] ---
    # Key functions: normalizePerChipMedian
    mednormedData <- normalizePerChipMedian(summedData)
    # --- Outputannot [] ---
    # Key functions: outputAnnotatedDataMatrix
    outputAnnotatedDataMatrix(mednormedData, "MiChipDemo", "medNormedIntensity",  "exprs")
    # --- Mynormedeset [] ---
    # Key functions: workedExampleMedianNormalize
    datadir <-system.file("extdata", package="MiChip")
     myNormedEset <- workedExampleMedianNormalize("NormedDemo", intensityCutoff = 50,datadir)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_michip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_michip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_michip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MICHIP:", paste0("    michip: ", packageVersion("MiChip"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_michip_results.csv
    touch ${prefix}_michip_output.rds
    echo "BIOC_MICHIP:" > versions.yml
    echo "    michip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MICHIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MICHIP(ch_input)

    emit:
    results  = BIOC_MICHIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MICHIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MICHIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MICHIP.out.versions  // channel: path(versions.yml)
}
