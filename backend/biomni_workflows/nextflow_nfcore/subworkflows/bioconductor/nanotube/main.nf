#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NanoTube
// NanoTube includes functions for the processing, quality control, analysis, and visualization of Nano
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NanoTube/inst/doc/NanoTube.R
// Upstream  : plotly
// Downstream: none
//
// Install: BiocManager::install("NanoTube")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NANOTUBE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nanotube"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nanotube:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nanotube:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nanotube_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nanotube_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nanotube_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NanoTube)
    library(jsonlite)

    # --- Data Processing and Normalization [processNanostringData] ---
    # Key functions: processNanostringData
    example_data <- system.file("extdata", "GSE117751_RAW", package = "NanoTube")
    sample_info <- system.file("extdata", 
                               "GSE117751_sample_data.csv", 
                               package = "NanoTube")
    dat <- processNanostringData(
        nsFiles = example_data,
        sampleTab = sample_info,
        idCol = "RCC_Name",
        groupCol = "Sample_Diagnosis",
        normalization = "nSolver",
        bgType = "t.test",
        bgPVal = 0.01
    )

    # --- Differential Expression Analysis [runLimmaAnalysis, makeDiffExprFile] ---
    # Key functions: runLimmaAnalysis, makeDiffExprFile
    limmaResults <- runLimmaAnalysis(dat, base.group = "None")
    limmaStats <- makeDiffExprFile(
        limmaResults, 
        filename = NULL, 
        returns = "stats"
    )
    limmaStats <- as.data.frame(limmaStats)
    limmaTab <- head(limmaStats[order(
        limmaStats$`p-val (Autoimmune.retinopathy)`, 
        decreasing = FALSE
    ), 1:4])

    # --- Volcano Plot Visualisation [deVolcano] ---
    # Key functions: deVolcano
    deVolcano(
        limmaResults, 
        plotContrast = "Autoimmune.retinopathy"
    )

    # --- Gene Set Enrichment Analysis [limmaToFGSEA] ---
    # Key functions: limmaToFGSEA
    data("ExamplePathways")
    fgseaResults <- limmaToFGSEA(
        limmaResults, 
        gene.sets = ExamplePathways
    )
    fgseaTab <- head(fgseaResults$Autoimmune.retinopathy[
        order(fgseaResults$Autoimmune.retinopathy$pval, 
              decreasing = FALSE),
    ])

    # --- Alternative Normalization with RUV [processNanostringData] ---
    # Key functions: processNanostringData
    sample_info_reps <- system.file("extdata", 
                                    "GSE117751_sample_data_replicates.csv", 
                                    package = "NanoTube")
    datRUVIII <- processNanostringData(
        nsFiles = example_data,
        sampleTab = sample_info_reps,
        idCol = "RCC_Name",
        replicateCol = "Replicate_ID",
        groupCol = "Sample_Diagnosis",
        normalization = "RUVIII",
        bgType = "t.test",
        bgPVal = 0.01,
        n.unwanted = 1
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nanotube_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nanotube_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nanotube_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NANOTUBE:", paste0("    nanotube: ", packageVersion("NanoTube"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nanotube_results.csv
    touch ${prefix}_nanotube_output.rds
    echo "BIOC_NANOTUBE:" > versions.yml
    echo "    nanotube: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NANOTUBE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NANOTUBE(ch_input)

    emit:
    results  = BIOC_NANOTUBE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NANOTUBE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NANOTUBE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NANOTUBE.out.versions  // channel: path(versions.yml)
}
