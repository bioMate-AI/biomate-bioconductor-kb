#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pogos
// Provide simple utilities for querying bhklab PharmacoDB, modeling API outputs, and integrating to ce
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pogos/inst/doc/pogos.R
// Upstream  : ggplot2, httr, ontoProc, ontologyPlot, rjson
// Downstream: none
//
// Install: BiocManager::install("pogos")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_POGOS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pogos"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pogos:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pogos:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pogos_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pogos_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pogos_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DRProfSet)
    library(DRTraceSet)
    library(GET)
    library(jsonlite)

    # --- Lkcc [] ---
    # Key functions: iriCCLE
    iric = iriCCLE()
    iric
    # --- Lkdrp [] ---
    # Key functions: DRProfSet
    drp = DRProfSet()
    drp
    # --- Lkk [] ---
    # Key functions: datatable, frame
    data(cell_lines_v1)
    datatable(as.data.frame(cell_lines_v1), options=list(lengthMenu=c(3,5,10,50,100)))
    # --- Lkccc [] ---
    # Key functions: datatable, frame
    data(compounds_v1)
    datatable(as.data.frame(compounds_v1),
       options=list(lengthMenu=c(3,5,10,50,100)))
    # --- Lkccc2 [] ---
    # Key functions: datatable, frame
    data(datasets_v1)
    datatable(as.data.frame(datasets_v1))
    # --- Doch [] ---
    # Key functions: getOnto, onto_plot
    library(ontoProc)
    cc = getOnto("chebi_full")
    library(ontologyPlot)
    # --- Lkmo [] ---
    # Key functions: onto_plot
    onto_plot(cc, c("CHEBI:134109", "CHEBI:61115", "CHEBI:75603", "CHEBI:37699",
       "CHEBI:68481", "CHEBI:71178", "CHEBI:52172", "CHEBI:64310",
       "CHEBI:63632", "CHEBI:45863"), fontsize=28, shape="rect")
    # --- Ana [] ---
    # Key functions: getOnto, onto_plot
    clo = getOnto("cellLineOnto", year_added="2022")
    smoc = c("CLO:0000517", "CLO:0000560", "CLO:0000563", "CLO:0001072",
    "CLO:0001088", "CLO:0001138", "CLO:0007606")
    onto_plot(clo, smoc)
    # --- Lkoo [] ---
    # Key functions: getOnto, unlist
    library(ontoProc)
    clo = getOnto("cellLineOnto", year_added="2022")
    minds = which(clo$name %in% c("143B cell", "1321N1 cell", "184B5 cell"))
    tags = clo$id[minds]
    clo$name[ unlist(clo$parent[tags]) ]
    # --- Lkefo [] ---
    # Key functions: getOnto, onto_plot
    ee = getOnto("efoOnto")
    # --- Lkcom [] ---
    # Key functions: getOnto, datatable, frame
    chl = getOnto("chebi_full")
    allch = chl$name
    mm = allch[match(tolower(compounds_v1[,2]), tolower(allch), nomatch=0)]
    round(length(mm)/nrow(compounds_v1),2) # not high
    datatable(data.frame(id=names(mm), comp=as.character(mm)))
    # --- Lkcomb [] ---
    # Key functions: GET, fromJSON, readBin
    library(rjson)
    library(httr)
    xx = GET("https://pharmacodb.pmgenomics.ca/api/v1/intersections/2/895/1?indent=true")
    ans = fromJSON(readBin(xx$content, what="character"))
    doses1 = sapply(ans[[1]]$dose_responses, function(x) x[[1]])
    # --- Lkbar [] ---
    # Key functions: DRTraceSet
    library(ggplot2)
    plot(DRTraceSet(dataset="CCLE"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pogos_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pogos_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pogos_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_POGOS:", paste0("    pogos: ", packageVersion("pogos"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pogos_results.csv
    touch ${prefix}_pogos_output.rds
    echo "BIOC_POGOS:" > versions.yml
    echo "    pogos: 0.0.0" >> versions.yml
    """
}


workflow BIOC_POGOS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_POGOS(ch_input)

    emit:
    results  = BIOC_POGOS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_POGOS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_POGOS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_POGOS.out.versions  // channel: path(versions.yml)
}
