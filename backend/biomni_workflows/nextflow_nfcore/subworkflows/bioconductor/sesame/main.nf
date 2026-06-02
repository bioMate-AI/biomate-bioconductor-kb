#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sesame
// Tools For analyzing Illumina Infinium DNA methylation arrays. SeSAMe provides utilities to support a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sesame/inst/doc/KYCG.R
// Upstream  : SummarizedExperiment, ggplot2, gprofiler2, knitr, tibble
// Downstream: none
//
// Install: BiocManager::install("sesame")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SESAME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sesame"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sesame:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sesame:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sesame_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sesame_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sesame_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sesame)
    library(KYCG_buildGeneDBs)
    library(KYCG_getDBs)
    library(KYCG_listDBGroups)
    library(KYCG_plotEnrichAll)
    library(KYCG_plotLollipop)
    library(jsonlite)

    # --- Data Initialization and Caching [Data Prep] ---
    # Key functions: sesameDataCache, sesameDataGet
    sesameDataCache()
    se <- sesameDataGet("MM285.10.SE.tissue")

    # --- Query Preparation and Annotation [Annotation] ---
    # Key functions: sesameDataGet, sesameData_getTxnGRanges, sesameData_annoProbes
    df <- SummarizedExperiment::rowData(
        sesameDataGet('MM285.tissueSignature')
    )
    query <- df$Probe_ID[df$branch == "fetal_liver" & df$type == "Hypo"]
    regs <- sesameData_getTxnGRanges("mm10", merge2gene = TRUE)
    genes <- sesameData_annoProbes(
        query, regs, platform = "MM285", return_ov_features = TRUE
    )

    # --- Enrichment Testing [Enrichment] ---
    # Key functions: KYCG_getDBs, testEnrichment
    query_pgc <- KYCG_getDBs("MM285.designGroup")[["PGCMeth"]]
    results_pgc <- testEnrichment(query_pgc, platform = "MM285")

    # --- Set Enrichment Analysis [Enrichment] ---
    # Key functions: KYCG_getDBs, testEnrichmentSEA
    query_tss <- KYCG_getDBs("KYCG.MM285.designGroup")[["TSS"]]
    db_tss <- KYCG_getDBs("MM285.seqContextN", "distToTSS")
    res_sea <- testEnrichmentSEA(query_tss, db_tss, prepPlot = TRUE)

    # --- Visualization of Enrichment Results [Visualisation] ---
    # Key functions: sesameData_getProbesByGene, KYCG_buildGeneDBs, testEnrichment, KYCG_plotLollipop
    query_gene <- names(sesameData_getProbesByGene("Dnmt3a", "MM285"))
    db_gene <- KYCG_buildGeneDBs(
        query_gene, max_distance = 100000, platform = "MM285"
    )
    results_gene <- testEnrichment(
        query_gene, db_gene, platform = "MM285"
    )
    KYCG_plotLollipop(results_gene, label = "gene_name")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sesame_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sesame_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sesame_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SESAME:", paste0("    sesame: ", packageVersion("sesame"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sesame_results.csv
    touch ${prefix}_sesame_output.rds
    echo "BIOC_SESAME:" > versions.yml
    echo "    sesame: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SESAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SESAME(ch_input)

    emit:
    results  = BIOC_SESAME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SESAME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SESAME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SESAME.out.versions  // channel: path(versions.yml)
}
