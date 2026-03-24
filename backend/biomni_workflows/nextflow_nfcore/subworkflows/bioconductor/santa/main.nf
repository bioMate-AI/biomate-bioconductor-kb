#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SANTA
// This package provides methods for measuring the strength of association between a network and a phen
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/SANTA/inst/doc/SANTA-vignette.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SANTA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SANTA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-santa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-santa:2.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-santa:2.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_santa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_santa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_santa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BinGraph)
    library(DistGraph)
    library(Knet)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: set, output
    {hook-printfun, echo=FALSE} library(knitr, quietly=TRUE) library(formatR, quietly=TRUE) knit_hooks$set(printfun = function(before, options, envir) {     if (before) return()     txt = capture.output(dump(options$printfun, '', envir = envir))     ## reformat if tidy=TRUE     if (options$tidy)         txt = tidy.source(text=txt, output=FALSE,                           width.cutoff=30L, keep.comment=TRUE,                           keep.blank.line=FALSE)$text.tidy     paste(c('\n
    # --- Code Block 2 [] ---
    # Key functions: game
    # generate the simulated network
    require(SANTA, quietly=TRUE)
    require(igraph, quietly=TRUE)
    set.seed(1) # for reproducibility
    g <- barabasi.game(n=500, power=1, m=1, directed=FALSE)
    # --- Code Block 3 [] ---
    # Key functions: DistGraph
    # measure the distance between pairs of vertices in g
    dist.method <- "shortest.paths"
    D <- DistGraph(g, dist.method=dist.method, verbose=FALSE)
    # --- Code Block 4 [] ---
    # Key functions: BinGraph
    # place the distances into discreet bins
    B <- BinGraph(D, verbose=FALSE)
    # --- Code Block 5 [] ---
    # Key functions: array
    cluster.size <- 5
    s.to.use <- c(10, 20, 50, 100, 500)
    n.trials <- 10
    pvalues <- array(0, dim=c(n.trials, length(s.to.use)),
        dimnames=list(NULL, as.character(s.to.use)))
    # --- Code Block 6 [] ---
    # Key functions: empty, edges, attribute
    # create the network
    n.nodes <- 12
    edges <- c(1,2, 1,3, 1,4, 2,3, 2,4, 3,4, 1,5, 5,6,
               2,7, 7,8, 4,9, 9,10, 3,11, 11,12)
    weights1 <- weights2 <- rep(0, n.nodes)
    # --- Code Block 8 [] ---
    # Key functions: attribute
    # obtain the GO term associations from org.Sc.sgd.db package
    library(org.Sc.sgd.db, quietly=TRUE)
    xx <- as.list(org.Sc.sgdGO2ALLORFS)
    go.terms <- c("GO:0000082", "GO:0003682", "GO:0007265",
                  "GO:0040008", "GO:0090329")
    # --- Code Block 9 [] ---
    # Key functions: Knet
    results <- list()
    for (name in network.names) {
        results[[name]] <- Knet(networks[[name]], nperm=10,
            vertex.attr=go.terms, edge.attr="distance", verbose=FALSE)
        results[[name]] <- sapply(results[[name]],
    # --- Code Block 10 [] ---
    # Key functions: data
    # load igraph objects
    data(g.bandyopadhyay.treated)
    data(g.bandyopadhyay.untreated)
    networks <- list(
        treated=g.bandyopadhyay.treated,
    # --- Code Block 12 [] ---
    # Key functions: Knet
    results <- sapply(networks, function(g) Knet(g, nperm=10,
        dist.method="shortest.paths", vertex.attr="rdds",
        edge.attr="distance"), simplify=FALSE)
    p.values <- sapply(results, function(res) res$pval)
    p.values
    # --- Code Block 13 [] ---
    # Key functions: data
    # laod igraph object
    data(g.srivas.high)
    data(g.srivas.untreated)
    networks <- list(
        high=g.srivas.high,
    # --- Code Block 15 [] ---
    # Key functions: Knet
    p.values <- sapply(networks, function(g)
           Knet(g, nperm=10, dist.method="shortest.paths",
           vertex.attr="dsbr", edge.attr="distance")$pval)
    p.values

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_santa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_santa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_santa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SANTA:", paste0("    santa: ", packageVersion("SANTA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_santa_results.csv
    touch ${prefix}_santa_output.rds
    echo "BIOC_SANTA:" > versions.yml
    echo "    santa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SANTA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SANTA(ch_input)

    emit:
    results  = BIOC_SANTA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SANTA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SANTA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SANTA.out.versions  // channel: path(versions.yml)
}
