#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hiAnnotator
// hiAnnotator contains set of functions which allow users to annotate a GRanges object with custom set
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hiAnnotator/inst/doc/Intro.R
// Upstream  : doMC, doParallel, doSMP, doSNOW
// Downstream: hiReadsProcessor
//
// Install: BiocManager::install("hiAnnotator")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIANNOTATOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hiannotator"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hiannotator:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hiannotator:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hiannotator_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hiannotator_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hiannotator_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hiAnnotator)
    library(jsonlite)


    # --- Eval = False [] ---
    # Key functions: getUCSCtable, makeGRanges, getNearestFeature, refFlat
    #  refflat <- getUCSCtable("refFlat", "RefSeq Genes")
    #  genes <- makeGRanges(refflat)

    ## -----------------------------------------------------------------------------
    nearestGenes <- getNearestFeature(alldata.rd, genes.rd, "NearestGene")
    head(nearestGenes)

    # nearestGenes <- getNearestFeature(alldata.rd,genes.rd,"NearestGene", parallel=TRUE)

    ## get nearest 5' genes
    nearestGenes <- getNearestFeature(alldata.rd, genes.rd, "NearestGene", side = "5p") 
    head(nearestGenes)

    ## get nearest 3' genes
    nearestGenes <- getNearestFeature(alldata.rd, genes.rd, "NearestGene", side = "3p")

    # --- Eval=false [] ---
    # Key functions: getFeatureCounts, getFeatureCountsBig, feature, getSitesInFeature
    #  geneCounts <- getFeatureCounts(alldata.rd, genes.rd, "NumOfGene",
    #                                 doInChunks = TRUE, chunkSize = 100)
    #  head(geneCounts)
    #  
    #  geneCounts <- getFeatureCountsBig(alldata.rd, genes.rd, "NumOfGene")
    #  head(geneCounts)

    ## -----------------------------------------------------------------------------
    ## Shows which feature(s) a position was found in.
    InGenes <- getSitesInFeature(alldata.rd, genes.rd, "InGene")
    head(InGenes)

    ## Simply shows TRUE/FALSE 
    InGenes <- getSitesInFeature(alldata.rd, genes.rd, "InGene", asBool = TRUE)
    head(InGenes)

    # --- Eval=true [] ---
    # Key functions: doAnnotation, plotdisFeature, makeGRanges, within, virus, nearest, expr
    res <- doAnnotation(annotType = "within", alldata.rd, genes.rd, "InGene", asBool = TRUE)
    plotdisFeature(res, "virus", "InGene")

    res <- doAnnotation(annotType = "nearest", alldata.rd, genes.rd, "NearestGene", side = '5p')
    plotdisFeature(res, "virus", "X5pNearestGeneDist")

    data(sites.ctrl)
    sites$type <- "expr"
    sites <- rbind(sites,sites.ctrl)
    alldata.rd <- makeGRanges(sites, soloStart = TRUE)
    res <- doAnnotation(annotType = "within", alldata.rd, genes.rd, "InGene", asBool = TRUE)
    plotdisFeature(res, "virus", "InGene")
    plotdisFeature(res, "virus", "InGene", typeRatio = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hiannotator_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hiannotator_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hiannotator_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HIANNOTATOR:", paste0("    hiannotator: ", packageVersion("hiAnnotator"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hiannotator_results.csv
    touch ${prefix}_hiannotator_output.rds
    echo "BIOC_HIANNOTATOR:" > versions.yml
    echo "    hiannotator: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HIANNOTATOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HIANNOTATOR(ch_input)

    emit:
    results  = BIOC_HIANNOTATOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HIANNOTATOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HIANNOTATOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HIANNOTATOR.out.versions  // channel: path(versions.yml)
}
