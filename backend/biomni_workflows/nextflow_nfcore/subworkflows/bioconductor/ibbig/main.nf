#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iBBiG
// iBBiG is a bi-clustering algorithm which is optimizes for binary data analysis. We apply it to meta-
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iBBiG/inst/doc/tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iBBiG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IBBIG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ibbig"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ibbig:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ibbig:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ibbig_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ibbig_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ibbig_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Clusterscores)
    library(JIdist)
    library(Number)
    library(NumberxCol)
    library(RowScorexNumber)
    library(RowxNumber)
    library(Seeddata)
    library(jsonlite)

    # --- Arti [] ---
    # Key functions: makeArtificial
    library(iBBiG)
    binMat<-makeArtificial()
    binMat
    plot(binMat)
    # --- Obj [] ---
    # Key functions: Number, RowxNumber, NumberxCol
    str(binMat)
    Number(binMat)
    RowxNumber(binMat)[1:2,]
    NumberxCol(binMat)[,1:2]
    # --- Ibbig [] ---
    # Key functions: iBBiG
    res<- iBBiG(binMat@Seeddata, nModules=10)
    plot(res)
    # --- Ji [] ---
    # Key functions: JIdist
    JIdist(res,binMat)
    JIdist(res,binMat, margin="col", best=FALSE)
    JIdist(res,binMat, margin="col")
    JIdist(res,binMat, margin="row")
    JIdist(res,binMat, margin="both")
    # --- Jicode [] ---
    # Key functions: showMethods, getMethod, signature
    ## showMethods(JIdist)
    ## getMethod(iBBiG:::JIdist, signature(clustObj = "iBBiG", GS = "iBBiG"))
    ## getMethod("JIdist",  signature(clustObj="iBBiG", GS="iBBiG"))
    # --- Ac [] ---
    # Key functions: analyzeClust
    analyzeClust(res,binMat)
    analyzeClust(res,binMat, margin="col")
    # --- Accode [] ---
    # Key functions: showMethods, getMethod, signature
    ## showMethods(analyzeClust)
    ## getMethod("analyzeClust",  signature(clustObj="iBBiG", GS="iBBiG"))
    # --- Strclass [] ---
    # Key functions: RowScorexNumber, Clusterscores, Seeddata
    str(binMat)
    RowScorexNumber(res)[1:2,]
    Clusterscores(res)
    Seeddata(res)[1:2,1:2]
    # --- Biclustplots [] ---
    # Key functions: drawHeatmap2, biclustmember, biclustbarchart, plotclust
    ## class(res)
    ##
    ## par(mfrow=c(2,1))
    ## drawHeatmap2(res@Seeddata, res, number=4)
    ## biclustmember(res,res@Seeddata)
    # --- Biclustbasic [] ---
    # Key functions: binarize, discretize
    ## data(BicatYeast)
    ## BicatYeast[1:5,1:5]
    ## binarize(BicatYeast[1:5,1:5], threshold=0.2)
    ## discretize(BicatYeast[1:5,1:5])
    # --- Bicluser [] ---
    # Key functions: bicluster
    Modules<-bicluster(res@Seeddata, res, 1:3)
    str(Modules)
    Modules[[1]][1:3,1:4]
    # --- Writebiclust [] ---
    # Key functions: writeBiclusterResults
    ## writeBiclusterResults("Modules.txt", res, bicName="Output from iBBiG with default parameters", geneNames=rownames(res@Seeddata), arrayNames=colnames(res@Seeddata))
    ##

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ibbig_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ibbig_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ibbig_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IBBIG:", paste0("    ibbig: ", packageVersion("iBBiG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ibbig_results.csv
    touch ${prefix}_ibbig_output.rds
    echo "BIOC_IBBIG:" > versions.yml
    echo "    ibbig: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IBBIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IBBIG(ch_input)

    emit:
    results  = BIOC_IBBIG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IBBIG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IBBIG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IBBIG.out.versions  // channel: path(versions.yml)
}
