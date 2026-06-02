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

    # --- Lkco [] ---
    # Key functions: dimnames, ugraph, aM2bpG
    #
    # tags formatted for display
    #
    # --- Dog1 [] ---
    # Key functions: edges, subGraph, flat
    library(Rgraphviz)
    #flat = function(x, g) c(x, edges(g)[[x]])
    #sub = subGraph(unique(c(flat("Crohn's\\\ndisease", cvtp),
    #    flat("Ulcerative\\\ncolitis", cvtp))), cvtp)
    sub = subGraph(unique(c(diseaseTags[1:4], TFtags[1:6])), cvtp)
    # --- Lkvd [] ---
    # Key functions: values
    library(vtpnet)
    data(maurGWAS)
    length(maurGWAS)
    names(values(maurGWAS))
    # --- Lkpax [] ---
    # Key functions: data
    data(pax4)
    length(pax4)
    pax4[1:4]
    # --- Lksearch [] ---
    # Key functions: registerDoParallel, seqnames, query, foreach, matchPWM, call
    ## library(foreach)
    ## library(doParallel)
    ## registerDoParallel(cores=12)
    ## library(BSgenome.Hsapiens.UCSC.hg19)
    ## library(MotifDb)
    # --- Lkmat [] ---
    # Key functions: overlapsAny
    data(pax4_85)
    vp_pax4_85 = maurGWAS[ overlapsAny(maurGWAS, pax4_85) ]
    length(vp_pax4_85)
    data(pax4_75)
    vp_pax4_75 = maurGWAS[ overlapsAny(maurGWAS, pax4_75) ]
    # --- Lkfim [] ---
    # Key functions: overlapsAny
    vp_pax4_fimo = maurGWAS[ overlapsAny(maurGWAS, pax4) ]
    length(vp_pax4_fimo)
    # --- Lkta [] ---
    # Key functions: setdiff
    u75 = unique(vp_pax4_75$disease_trait)
    ufimo = unique(vp_pax4_fimo$disease_trait)
    length(setdiff(u75, ufimo))
    length(setdiff(ufimo, u75))
    # --- Domap [] ---
    # Key functions: requireNamespace, filterGWASbyMap, getOneHits
    data(cancerMap)
    requireNamespace("gwascat")
    load(system.file("legacy/gwrngs19.rda", package="gwascat"))
    cangw = filterGWASbyMap( gwrngs19, cancerMap )
    getOneHits( pax4, cangw, "fimo" )

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
