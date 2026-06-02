#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vtpnet
// variant-transcription factor-phenotype networks, inspired by Maurano et al., Science (2012), PMID 22
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vtpnet/inst/doc/vtpnet.R
// Upstream  : MotifDb, Rgraphviz, doParallel, foreach, graph
// Downstream: none
//
// Install: BiocManager::install("vtpnet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VTPNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vtpnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vtpnet:0.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vtpnet:0.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vtpnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vtpnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vtpnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(vtpnet)
    library(jsonlite)

    # --- Data Loading and Exploration [Data Acquisition] ---
    # Key functions: data
    data(maurGWAS)
    data(pax4)
    data(pax4_85)
    data(pax4_75)
    gwas_count = length(maurGWAS)
    pax4_count = length(pax4)
    gwas_metadata_cols = names(GenomicRanges::values(maurGWAS))

    # --- Variant-TF Overlap Analysis [Overlap Analysis] ---
    # Key functions: overlapsAny
    vp_pax4_85 = maurGWAS[GenomicRanges::overlapsAny(maurGWAS, pax4_85)]
    vp_pax4_75 = maurGWAS[GenomicRanges::overlapsAny(maurGWAS, pax4_75)]
    vp_pax4_fimo = maurGWAS[GenomicRanges::overlapsAny(maurGWAS, pax4)]
    u75 = unique(vp_pax4_75$disease_trait)
    ufimo = unique(vp_pax4_fimo$disease_trait)
    diff_traits = setdiff(u75, ufimo)

    # --- GWAS Filtering and Hit Identification [Filtering] ---
    # Key functions: filterGWASbyMap, getOneHits
    data(cancerMap)
    data(maurGWAS)
    data(pax4)
    cangw = filterGWASbyMap(maurGWAS, cancerMap)
    hits = getOneHits(pax4, cangw, "fimo")

    # --- Network Construction and Subgraphing [Network Analysis] ---
    # Key functions: aM2bpG, ugraph, subGraph
    diseaseTags = c("Ankylosing\nspondylitis", "Asthma", "Celiac\ndisease")
    TFtags = c("ELF3", "MEF2A", "TCF3")
    adjm = matrix(1, nrow=length(diseaseTags), ncol=length(TFtags))
    dimnames(adjm) = list(diseaseTags, TFtags)
    cvtp = graph::ugraph(graph::aM2bpG(adjm))
    sub = graph::subGraph(unique(c(diseaseTags[1:2], TFtags[1:2])), cvtp)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vtpnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vtpnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vtpnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VTPNET:", paste0("    vtpnet: ", packageVersion("vtpnet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vtpnet_results.csv
    touch ${prefix}_vtpnet_output.rds
    echo "BIOC_VTPNET:" > versions.yml
    echo "    vtpnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VTPNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VTPNET(ch_input)

    emit:
    results  = BIOC_VTPNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VTPNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VTPNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VTPNET.out.versions  // channel: path(versions.yml)
}
