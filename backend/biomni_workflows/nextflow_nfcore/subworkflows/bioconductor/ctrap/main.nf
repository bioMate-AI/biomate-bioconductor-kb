#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cTRAP
// Compare differential gene expression results with those from known cellular perturbations (such as g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cTRAP/inst/doc/cTRAP.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cTRAP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CTRAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ctrap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ctrap:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ctrap:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ctrap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ctrap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ctrap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cTRAP)
    library(jsonlite)

    # --- load ENCODE samples [] ---
    # Key functions: loadENCODEsamples, prepareENCODEgeneExpression
    ENCODEmetadata <- downloadENCODEknockdownMetadata(cellLine, gene)
    table(ENCODEmetadata$`Experiment target`)
    length(unique(ENCODEmetadata$`Experiment target`))
    # --- differential gene expression [] ---
    # Key functions: rowSums, performDifferentialExpression
    filter <- rowSums(counts[ , -c(1, 2)] >= minReads) >= minSamples
    counts$gene_id <- convertGeneIdentifiers(counts$gene_id)
    diffExpr <- performDifferentialExpression(counts)
    # --- CMap metadata conditions [] ---
    # Key functions: loadCMapData, getCMapConditions
    Load CMap metadata (automatically downloaded if not found)
    cmapMetadata <- loadCMapData("cmapMetadata.txt", type="metadata")
    getCMapConditions(cmapMetadata)
    # --- CMap knockdown perturbations [] ---
    # Key functions: filterCMapMetadata, prepareCMapPerturbations
    cmapMetadataKD <- filterCMapMetadata(
    cmapPerturbationsKD <- prepareCMapPerturbations(
    # --- CMap small molecule perturbations [] ---
    # Key functions: filterCMapMetadata, prepareCMapPerturbations
    cmapMetadataCompounds <- filterCMapMetadata(
    cmapPerturbationsCompounds <- prepareCMapPerturbations(
    # --- compare knockdown [] ---
    # Key functions: rankSimilarPerturbations
    compareKD <- rankSimilarPerturbations(diffExprStat, cmapPerturbationsKD)
    # --- compare small molecules [] ---
    # Key functions: rankSimilarPerturbations
    compareCompounds <- rankSimilarPerturbations(diffExprStat,
    # --- perturbation info [] ---
    # Key functions: attr
    EIF4G1knockdown <- grep("EIF4G1", compareKD[[1]], value=TRUE)
    print(compareKD, EIF4G1knockdown)
    Information on the top 10 most similar compound perturbations (based on
    # --- drug set enrichment analysis [] ---
    # Key functions: loadDrugDescriptors, prepareDrugSets, analyseDrugSetEnrichment, plotDrugSetEnrichment
    descriptors <- loadDrugDescriptors("CMap", "2D")
    drugSets    <- prepareDrugSets(descriptors)
    dsea        <- analyseDrugSetEnrichment(drugSets, predicted)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ctrap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ctrap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ctrap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CTRAP:", paste0("    ctrap: ", packageVersion("cTRAP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ctrap_results.csv
    touch ${prefix}_ctrap_output.rds
    echo "BIOC_CTRAP:" > versions.yml
    echo "    ctrap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CTRAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CTRAP(ch_input)

    emit:
    results  = BIOC_CTRAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CTRAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CTRAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CTRAP.out.versions  // channel: path(versions.yml)
}
