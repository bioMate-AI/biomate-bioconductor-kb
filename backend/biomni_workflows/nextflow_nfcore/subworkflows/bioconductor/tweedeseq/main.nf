#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tweeDEseq
// Differential expression analysis of RNA-seq using the Poisson-Tweedie (PT) family of distributions. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tweeDEseq/inst/doc/tweeDEseq.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("tweeDEseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TWEEDESEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tweedeseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tweedeseq:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tweedeseq:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tweedeseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tweedeseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tweedeseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MAplot)
    library(Vplot)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: exprs, pData
    data(pickrell)
    countsNigerian <- exprs(pickrell.eset)
    dim(countsNigerian)
    countsNigerian[1:5, 1:5]
    genderNigerian <- pData(pickrell.eset)[,"gender"]
    # --- Normalizecounts [] ---
    # Key functions: normalizeCounts
    ## countsNigerianNorm <- normalizeCounts(countsNigerian, genderNigerian)
    # --- Data [] ---
    # Key functions: exprs
    data(pickrellNorm)
    countsNigerianNorm <- exprs(pickrellNorm.eset)
    # --- Filtercounts [] ---
    # Key functions: filterCounts
    countsNigerianNorm <- filterCounts(countsNigerianNorm)
    dim(countsNigerianNorm)
    # --- Testshapept [] ---
    # Key functions: testShapePT
    testShapePT(thetahat, a=0)
    # --- Data [] ---
    # Key functions: data
    data(genderGenes)
    data(hkGenes)
    length(XiEgenes)
    length(msYgenes)
    length(hkGenes)
    # --- Goftest [] ---
    # Key functions: gofTest
    chi2gof <- gofTest(countsNigerianNorm[geneSubset, ], a=0)
    # --- Gof [] ---
    # Key functions: qqchisq
    par(mfrow=c(1,2), mar=c(4, 5, 3, 4))
    qq <- qqchisq(chi2gof, main="Chi2 Q-Q Plot", ylim = c(0, 60))
    qq <- qqchisq(chi2gof, normal=TRUE, ylim = c(-5, 7))
    # --- Secretin [] ---
    # Key functions: unlist, compareCountDist
    par(mfrow=c(1,2), mar=c(4, 5, 3, 2))
    xf <- unlist(countsNigerianNorm["ENSG00000070031", genderNigerian=="female"])
    compareCountDist(xf, main="Female samples")
    xm <- unlist(countsNigerianNorm["ENSG00000070031", genderNigerian=="male"])
    compareCountDist(xm, main="Male samples")
    # --- Tweede [] ---
    # Key functions: tweeDE
    resPT <- tweeDE(countsNigerianNorm[geneSubset, ], group = genderNigerian)
    # --- Data [] ---
    # Key functions: data, merge
    data(annotEnsembl63)
    head(annotEnsembl63)
    deGenes <- merge(deGenes, annotEnsembl63, by="row.names", sort=FALSE)
    # --- Tabdegenes [] ---
    # Key functions: xtable
    library(xtable)
    # --- Manvplots [] ---
    # Key functions: MAplot, Vplot
    hl <- list(list(genes=msYgenes, pch=21, col="blue", bg="blue", cex=0.7),
               list(genes=XiEgenes, pch=21, col="skyblue", bg="skyblue", cex=0.7),
               list(genes=deGenes, pch=1, col="red", lwd=2, cex=1.5)
              )
    par(mfrow=c(1,2), mar=c(4, 5, 3, 2))
    # --- Glmpt [] ---
    # Key functions: glmPT
    mod <- glmPT(countsNigerianNorm["ENSG00000070031",] ~ genderNigerian)
    mod
    summary(mod)
    # --- Tweedeglm [] ---
    # Key functions: tweeDEglm
    resPTglm <- tweeDEglm( ~ genderNigerian, counts = countsNigerianNorm[geneSubset,])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tweedeseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tweedeseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tweedeseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TWEEDESEQ:", paste0("    tweedeseq: ", packageVersion("tweeDEseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tweedeseq_results.csv
    touch ${prefix}_tweedeseq_output.rds
    echo "BIOC_TWEEDESEQ:" > versions.yml
    echo "    tweedeseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TWEEDESEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TWEEDESEQ(ch_input)

    emit:
    results  = BIOC_TWEEDESEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TWEEDESEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TWEEDESEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TWEEDESEQ.out.versions  // channel: path(versions.yml)
}
