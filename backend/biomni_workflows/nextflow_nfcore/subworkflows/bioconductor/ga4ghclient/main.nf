#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GA4GHclient
// GA4GHclient provides an easy way to access public data servers through Global Alliance for Genomics 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GA4GHclient/inst/doc/GA4GHclient.R
// Upstream  : VariantAnnotation
// Downstream: GA4GHshiny
//
// Install: BiocManager::install("GA4GHclient")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GA4GHCLIENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ga4ghclient"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ga4ghclient:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ga4ghclient:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ga4ghclient_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ga4ghclient_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ga4ghclient_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CodingVariants)
    library(jsonlite)

    # --- search Datasets [] ---
    # Key functions: searchDatasets, searchVariantSets, searchVariants
    datasets <- searchDatasets(host, nrows = 1)
    variantSets <- searchVariantSets(host, datasetId, nrows = 1)
    variants <- searchVariants(host, variantSetId, referenceName = "1",
    # --- datatable [] ---
    # Key functions: datatable
    variants.df <- searchVariants(host, variantSetId, referenceName = "1",
    DT::datatable(as.data.frame(variants.df), options = list(scrollX = TRUE))
    # --- search Reference Sets [] ---
    # Key functions: searchReferenceSets, genes, seqlevelsStyle
    referenceSets <- searchReferenceSets(host, nrows = 1)
    head(keys(org.Hs.eg.db, keytype = "SYMBOL"))
    head(genes(TxDb.Hsapiens.UCSC.hg19.knownGene))
    # --- Locate variants in genomic features [] ---
    # Key functions: datatable, seqlevelsStyle, locateVariants, CodingVariants
    variants.scn1a <- searchVariantsByGRanges(host, variantSetId, gr, asVCF = FALSE)
    DT::datatable(as.data.frame(variants.scn1a[[1]]), options = list(scrollX = TRUE))
    variants.scn1a.gr <- makeGRangesFromDataFrame(variants.scn1a[[1]],
    # --- search Call Sets [] ---
    # Key functions: searchCallSets, searchVariants
    callSetIds <- searchCallSets(host, variantSetId, nrows = 5)$id
    vcf <- searchVariants(host, variantSetId, referenceName = "1",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ga4ghclient_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ga4ghclient_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ga4ghclient_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GA4GHCLIENT:", paste0("    ga4ghclient: ", packageVersion("GA4GHclient"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ga4ghclient_results.csv
    touch ${prefix}_ga4ghclient_output.rds
    echo "BIOC_GA4GHCLIENT:" > versions.yml
    echo "    ga4ghclient: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GA4GHCLIENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GA4GHCLIENT(ch_input)

    emit:
    results  = BIOC_GA4GHCLIENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GA4GHCLIENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GA4GHCLIENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GA4GHCLIENT.out.versions  // channel: path(versions.yml)
}
