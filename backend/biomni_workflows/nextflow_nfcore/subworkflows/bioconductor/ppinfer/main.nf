#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PPInfer
// Interactions between proteins occur in many, if not most, biological processes. Most proteins perfor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PPInfer/inst/doc/PPInfer.R
// Upstream  : Category, GOstats, limma
// Downstream: gsean
//
// Install: BiocManager::install("PPInfer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PPINFER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ppinfer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ppinfer:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ppinfer:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ppinfer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ppinfer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ppinfer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ORA)
    library(V)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: graphNEL, decompose
    library(PPInfer)
    data(litG)
    litG <- igraph.from.graphNEL(litG)
    summary(litG)
    sg <- decompose(litG, min.vertices = 50)
    # --- Plot [] ---
    # Key functions: kawai
    plot(sg, layout = layout.kamada.kawai(sg), vertex.size = 10)
    # --- Kernel [] ---
    # Key functions: kernel, infer, V
    K <- net.kernel(sg)
    set.seed(123)
    litG.infer <- net.infer(names(V(sg))[1:10], K, top = 20, cross = 10)
    litG.infer$CVerror
    index <- match(litG.infer$top,names(V(sg)))
    # --- Plot [] ---
    # Key functions: kawai
    plot(sg, layout = layout.kamada.kawai(sg), vertex.size = 10)
    # --- Try [] ---
    # Key functions: infer, V
    litG.infer <- try(net.infer(names(V(sg))[1:50], K, top = 20))
    cat(litG.infer)
    litG.infer <- net.infer(names(V(sg))[1:40], K, top = 20)
    litG.infer$top
    # --- Data [] ---
    # Key functions: sample, V, infer
    data(examplePathways)
    data(exampleRanks)
    geneNames <- names(exampleRanks)
    set.seed(1)
    gene.names <- sample(geneNames, length(V(sg)))
    # --- Ora [] ---
    # Key functions: ORA
    # ORA
    result.ORA <- ORA(examplePathways, gene.id[1:10])
    # --- Barplot [] ---
    # Key functions: scale_colour_gradient
    ORA.barplot(result.ORA, category = "Category", size = "Size",
                count = "Count", pvalue = "pvalue", sort = "pvalue") +
                scale_colour_gradient(low = 'red', high = 'gray', limits=c(0, 0.1))
    # --- Na [] ---
    # Key functions: na, scale, fgsea
    # GSEA
    index <- !is.na(infer$score)
    gene.id <- infer$top[index]
    scores <- infer$score[index]
    scaled.scores <- as.numeric(scale(scores))
    # --- Net [] ---
    # Key functions: net
    enrich.net(result.GSEA, examplePathways, node.id = 'pathway',
               pvalue = 'pval', pvalue.cutoff = 0.25, degree.cutoff = 0,
               n = 100, vertex.label.cex = 0.75, show.legend = FALSE,
               edge.width = function(x) {5*sqrt(x)},
               layout=igraph::layout.kamada.kawai)
    # --- Readrds [] ---
    # Key functions: nodes
    ## library(GOstats)
    ##
    ## # load kernel matrix
    ## K.9606 <- readRDS("K9606.rds")
    ##
    # --- Human [] ---
    # Key functions: human, new, hyperGTest
    ## # find top 100 proteins
    ## apoptosis.infer <- ppi.infer.human(list.proteins, K.9606, output="entrezgene", 100)
    ## gene.id <- apoptosis.infer$top
    ## head(gene.id)
    ##
    # --- Mget [] ---
    # Key functions: mget, getGeneKEGGLinks, human, frame
    ## library(KEGG.db)
    ## library(limma)
    ##
    ## # load target class for p53
    ## mget('p53 signaling pathway', KEGGPATHNAME2ID)
    # --- Readrds [] ---
    # Key functions: mget, getGeneKEGGLinks, mouse
    ## # load kernel matrix
    ## K.10090 <- readRDS("K10090.rds")
    ## # remove prefix
    ## rownames(K.10090) <- sub(".*\\.", "", rownames(K.10090))
    ##
    # --- Mget [] ---
    # Key functions: mget, getGeneKEGGLinks, mouse, frame
    ## # load target class
    ## mget('Ras signaling pathway', KEGGPATHNAME2ID)
    ## kegg.mmu <- getGeneKEGGLinks(species.KEGG='mmu')
    ## index <- which(kegg.mmu[,2] == 'path:mmu04014')
    ## path.04014 <- kegg.mmu[index,1]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ppinfer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ppinfer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ppinfer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PPINFER:", paste0("    ppinfer: ", packageVersion("PPInfer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ppinfer_results.csv
    touch ${prefix}_ppinfer_output.rds
    echo "BIOC_PPINFER:" > versions.yml
    echo "    ppinfer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PPINFER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PPINFER(ch_input)

    emit:
    results  = BIOC_PPINFER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PPINFER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PPINFER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PPINFER.out.versions  // channel: path(versions.yml)
}
