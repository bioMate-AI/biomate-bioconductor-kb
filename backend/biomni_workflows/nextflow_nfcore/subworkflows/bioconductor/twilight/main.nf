#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: twilight
// In a typical microarray setting with gene expression data observed under two conditions, the local f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/twilight/inst/doc/tr_2004_01.R
// Upstream  : golubEsets, splines, stats, vsn
// Downstream: OrderedList
//
// Install: BiocManager::install("twilight")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TWILIGHT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-twilight"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-twilight:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-twilight:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_twilight_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_twilight_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_twilight_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(twilight)
    library(jsonlite)

    # --- Exit [] ---
    # Key functions: exit
    library(splines)
    library(stats)
    library(golubEsets)
    library(vsn)
    oldopt <- options(digits=3)
    # --- Data [] ---
    # Key functions: justvsn
    data(Golub_Train)
    golubNorm <- justvsn(Golub_Train)
    id <- as.numeric(Golub_Train$ALL.AML) #$
    # --- Pval [] ---
    # Key functions: pval
    library(twilight)
    pval <- twilight.pval(golubNorm, id, B=100)
    # --- Bitmap [] ---
    # Key functions: bitmap, off
    bitmap(file="tr_2004_01-scores.png",width=6,height=4.5,pointsize=10)
    plot(expval,which="scores",grayscale=F,legend=F)
    dev.off()
    bitmap(file="tr_2004_01-qvalues.png",width=6,height=4.5,pointsize=10)
    plot(expval,which="qvalues")
    # --- Exprs [] ---
    # Key functions: exprs, pval
    gene <- exprs(golubNorm)[pval$result$index[1],]
    corr <- twilight.pval(golubNorm,gene,method="spearman",quant.ci=0.99,B=100)
    corr
    # --- Bitmap [] ---
    # Key functions: bitmap, off
    bitmap(file="tr_2004_01-corr.png",width=6,height=4.5,pointsize=10)
    plot(corr,which="scores",grayscale=F,legend=F)
    dev.off()
    # --- Filtering [] ---
    # Key functions: filtering
    yperm <- twilight.filtering(golubNorm,id,method="fc",num.perm=50,num.take=10)
    dim(yperm)
    # --- Pval [] ---
    # Key functions: pval
    yperm <- yperm[-1,]
    b <- twilight.pval(golubNorm,yperm[1,],method="fc",yperm=yperm)
    hist(b$result$pvalue,col="gray",br=20)
    # --- Bitmap [] ---
    # Key functions: bitmap, off
    bitmap(file="tr_2004_01-hist.png",width=6,height=4.5,pointsize=10)
    hist(b$result$pvalue,col="gray",br=20,main="",xlab="P-value")
    dev.off()
    # --- Combi [] ---
    # Key functions: combi
    twilight.combi(x,pin=FALSE,bin=FALSE)
    # --- Pair [] ---
    # Key functions: pair
    twilight.permute.pair(y,7,bal=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_twilight_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_twilight_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_twilight_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TWILIGHT:", paste0("    twilight: ", packageVersion("twilight"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_twilight_results.csv
    touch ${prefix}_twilight_output.rds
    echo "BIOC_TWILIGHT:" > versions.yml
    echo "    twilight: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TWILIGHT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TWILIGHT(ch_input)

    emit:
    results  = BIOC_TWILIGHT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TWILIGHT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TWILIGHT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TWILIGHT.out.versions  // channel: path(versions.yml)
}
