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
    library(GA4GHclient)
    library(CodingVariants)
    library(jsonlite)

    # --- Genomic Variant Retrieval [] ---
    # Key functions: searchVariants
    host <- "http://1kgenomes.ga4gh.org/"
    variantSetId <- "release"
    variants_vcf <- searchVariants(host, variantSetId, referenceName = "1",
        start = 15000, end = 16000, nrows = 10, asVCF = TRUE)
    variants_df <- searchVariants(host, variantSetId, referenceName = "1",
        start = 15000, end = 16000, nrows = 10, asVCF = FALSE)


    # --- Gene-Targeted Variant Search [] ---
    # Key functions: searchVariantsByGRanges
    host <- "http://1kgenomes.ga4gh.org/"
    variantSetId <- "release"
    gr <- GenomicRanges::GRanges(seqnames = "1",
        ranges = IRanges::IRanges(start = 15000, end = 16000))
    variants_gene <- searchVariantsByGRanges(host, variantSetId, gr,
        asVCF = FALSE)


    # --- Call Set and Genotype Retrieval [] ---
    # Key functions: searchCallSets, searchVariants
    host <- "http://1kgenomes.ga4gh.org/"
    variantSetId <- "release"
    callSets <- searchCallSets(host, variantSetId, nrows = 5)
    callSetIds <- callSets$id
    vcf_calls <- searchVariants(host, variantSetId, referenceName = "1",
        start = 15000, end = 16000, callSetIds = callSetIds, nrows = 10)

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
