#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SPIA
// This package implements the Signaling Pathway Impact Analysis (SPIA) which uses the information form
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SPIA/inst/doc/SPIA.R
// Upstream  : Rgraphviz, graph
// Downstream: none
//
// Install: BiocManager::install("SPIA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPIA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spia"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spia:2.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spia:2.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spia_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spia_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spia_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(I)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(SPIA)
    data(colorectalcancer)
    options(digits=3)
    head(top)
    # --- Unlist [] ---
    # Key functions: unlist, na
    library(hgu133plus2.db)
    x <- hgu133plus2ENTREZID
    top$ENTREZ<-unlist(as.list(x[top$ID]))
    top<-top[!is.na(top$ENTREZ),]
    top<-top[!duplicated(top$ENTREZ),]
    # --- Spia [] ---
    # Key functions: spia
    # pathway analysis based on combined evidence; # use nB=2000 or more for more accurate results
    res=spia(de=DE_Colorectal,all=ALL_Colorectal,organism="hsa",nB=2000,plots=FALSE,beta=NULL,combine="fisher",verbose=FALSE)
    #make the output fit this screen
    res$Name=substr(res$Name,1,10)
    #show first 15 pathways, omit KEGG links
    # --- Plotp [] ---
    # Key functions: plotP, I
    plotP(res,threshold=0.05)
    points(I(-log(pPERT))~I(-log(pNDE)),data=res[res$ID=="05210",],col="green",pch=19,cex=1.5)
    # --- Combfunc [] ---
    # Key functions: combfunc, adjust, plotP, I
    res$pG=combfunc(res$pNDE,res$pPERT,combine="norminv")
    res$pGFdr=p.adjust(res$pG,"fdr")
    res$pGFWER=p.adjust(res$pG,"bonferroni")
    plotP(res,threshold=0.05)
    points(I(-log(pPERT))~I(-log(pNDE)),data=res[res$ID=="05210",],col="green",pch=19,cex=1.5)
    # --- Data [] ---
    # Key functions: spia
    data(Vessels)
    # pathway analysis based on combined evidence; # use nB=2000 or more for more accurate results
    res<-spia(de=DE_Vessels,all=ALL_Vessels,organism="hsa",nB=500,plots=FALSE,beta=NULL,verbose=FALSE)
    #make the output fit this screen
    res$Name=substr(res$Name,1,10)
    # --- Plotg [] ---
    # Key functions: plotG
    plotG(path.info[["04012"]][["activation"]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spia_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spia_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spia_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPIA:", paste0("    spia: ", packageVersion("SPIA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spia_results.csv
    touch ${prefix}_spia_output.rds
    echo "BIOC_SPIA:" > versions.yml
    echo "    spia: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPIA(ch_input)

    emit:
    results  = BIOC_SPIA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPIA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPIA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPIA.out.versions  // channel: path(versions.yml)
}
