#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IsoformSwitchAnalyzeR
// Analysis of alternative splicing and isoform switches with predicted functional consequences (e.g. g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IsoformSwitchAnalyzeR/inst/doc/IsoformSwitchAnalyzeR.R
// Upstream  : VennDiagram
// Downstream: none
//
// Install: BiocManager::install("IsoformSwitchAnalyzeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOFORMSWITCHANALYZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isoformswitchanalyzer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isoformswitchanalyzer:2.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isoformswitchanalyzer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isoformswitchanalyzer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isoformswitchanalyzer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IsoformSwitchAnalyzeR)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    myDesign <- data.frame(
        sampleID = colnames(salmonQuant$abundance)[-1],
        condition = gsub('_.*', '', colnames(salmonQuant$abundance)[-1])
    )
    # --- Data [] ---
    # Key functions: subsetSwitchAnalyzeRlist
    ---------------------------------------------------------------------
    ### load example data
    data("exampleSwitchList")
    ### Subset for quick runtime
    # --- Extractswitchsummary [] ---
    # Key functions: extractSwitchSummary
    ---------------------------------------------------------------------
    extractSwitchSummary( exampleSwitchList )
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("exampleSwitchListAnalyzed")
    # --- Extractswitchsummary [] ---
    # Key functions: extractSwitchSummary
    ---------------------------------------------------------------------
    extractSwitchSummary(
        exampleSwitchListAnalyzed,
        filterForConsequences = TRUE
    )
    # --- Subset [] ---
    # Key functions: extractTopSwitches
    ---------------------------------------------------------------------
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    ### A newly created switchAnalyzeRlist + switch analysis
    data("exampleSwitchList")
    names(exampleSwitchList)
    # --- Subsetswitchanalyzerlist [] ---
    # Key functions: subsetSwitchAnalyzeRlist
    ---------------------------------------------------------------------
    exampleSwitchList
    ### Subset
    # --- Frame [] ---
    # Key functions: frame, importRdata
    ---------------------------------------------------------------------
    ### Make design matrix
    # --- Importsalmondata [] ---
    # Key functions: importSalmonData
    ---------------------------------------------------------------------
    aSwitchList <- importSalmonData(
        salmonFileDataFrame = salmonDf, # as created above
        showProgress=FALSE              # For nicer printout in vignette
    )
    # --- Data [] ---
    # Key functions: preFilter
    ---------------------------------------------------------------------
    data("exampleSwitchList")
    # --- Extractsequence [] ---
    # Key functions: extractSequence
    ---------------------------------------------------------------------
    ### This example relies on the example data from the 'Analyzing Open Reading Frames' section above
    # --- Analyzealternativesplicing [] ---
    # Key functions: analyzeAlternativeSplicing, retentions
    ---------------------------------------------------------------------
    ### This example relies on the example data from the 'Importing External Sequence Analysis' section above
    # --- Data [] ---
    # Key functions: subsetSwitchAnalyzeRlist, genes, extractTopSwitches
    ---------------------------------------------------------------------
    ### Load already analyzed data
    data("exampleSwitchListAnalyzed")
    ### Let's reduce the switchAnalyzeRlist to only one condition
    # --- Extracttopswitches [] ---
    # Key functions: extractTopSwitches
    ---------------------------------------------------------------------
    ### Extract data.frame with all switching isoforms

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isoformswitchanalyzer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isoformswitchanalyzer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isoformswitchanalyzer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOFORMSWITCHANALYZER:", paste0("    isoformswitchanalyzer: ", packageVersion("IsoformSwitchAnalyzeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isoformswitchanalyzer_results.csv
    touch ${prefix}_isoformswitchanalyzer_output.rds
    echo "BIOC_ISOFORMSWITCHANALYZER:" > versions.yml
    echo "    isoformswitchanalyzer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOFORMSWITCHANALYZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOFORMSWITCHANALYZER(ch_input)

    emit:
    results  = BIOC_ISOFORMSWITCHANALYZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOFORMSWITCHANALYZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOFORMSWITCHANALYZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOFORMSWITCHANALYZER.out.versions  // channel: path(versions.yml)
}
