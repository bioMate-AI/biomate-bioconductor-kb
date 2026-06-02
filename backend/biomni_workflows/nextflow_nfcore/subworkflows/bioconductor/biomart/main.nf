#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biomaRt
// In recent years a wealth of biological data has become available in public data repositories. Easy a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biomaRt/inst/doc/accessing_ensembl.R
// Upstream  : none
// Downstream: chromPlot, customProDB, DrugVsDisease, GenomicOZone, MineICA
//
// Install: BiocManager::install("biomaRt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOMART {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biomart"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biomart:2.62.1--r44_0' :
        'quay.io/biocontainers/bioconductor-biomart:2.62.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biomart_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biomart_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biomart_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biomaRt)
    library(jsonlite)

    # --- Database Connection and Dataset Selection [] ---
    # Key functions: useEnsembl, listDatasets, useDataset
    ensembl <- useEnsembl(biomart = "genes")
    datasets <- listDatasets(ensembl)
    target_dataset <- "hsapiens_gene_ensembl"
    ensembl <- useDataset(
        dataset = target_dataset,
        mart = ensembl
    )

    # --- Querying Gene Annotations [] ---
    # Key functions: getBM, listFilters, listAttributes
    affyids <- c("202763_at", "209310_s_at", "207500_at")
    filters <- listFilters(ensembl)
    attributes <- listAttributes(ensembl)
    annot_data <- getBM(
        attributes = c("affy_hg_u133_plus_2", "hgnc_symbol", "entrezgene_id"),
        filters = "affy_hg_u133_plus_2",
        values = affyids,
        mart = ensembl
    )

    # --- Sequence Retrieval [] ---
    # Key functions: getSequence
    entrez_ids <- c("673", "837")
    coding_sequences <- getSequence(
        id = entrez_ids,
        type = "entrezgene_id",
        seqType = "coding_gene_flank",
        upstream = 100,
        mart = ensembl
    )

    # --- Cross-Species Homology Mapping [] ---
    # Key functions: useEnsembl, getLDS
    human_mart <- useEnsembl("ensembl", dataset = "hsapiens_gene_ensembl")
    mouse_mart <- useEnsembl("ensembl", dataset = "mmusculus_gene_ensembl")
    homology_map <- getLDS(
        attributes = c("hgnc_symbol", "chromosome_name", "start_position"),
        filters = "hgnc_symbol",
        values = "TP53",
        mart = human_mart,
        attributesL = c("refseq_mrna", "chromosome_name", "start_position"),
        martL = mouse_mart
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biomart_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biomart_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biomart_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOMART:", paste0("    biomart: ", packageVersion("biomaRt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomart_results.csv
    touch ${prefix}_biomart_output.rds
    echo "BIOC_BIOMART:" > versions.yml
    echo "    biomart: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOMART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOMART(ch_input)

    emit:
    results  = BIOC_BIOMART.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOMART.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOMART.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOMART.out.versions  // channel: path(versions.yml)
}
