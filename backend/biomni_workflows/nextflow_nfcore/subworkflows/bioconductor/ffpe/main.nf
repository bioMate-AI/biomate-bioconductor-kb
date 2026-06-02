#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ffpe
// Identify low-quality data using metrics developed for expression data derived from Formalin-Fixed, P
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ffpe/inst/doc/ffpe.R
// Upstream  : ffpeExampleData, genefilter
// Downstream: none
//
// Install: BiocManager::install("ffpe")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FFPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ffpe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ffpe:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ffpe:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ffpe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ffpe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ffpe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CATplot)
    library(jsonlite)

    # --- Foo [] ---
    # Key functions: packageDescription
    options(keep.source = TRUE)
    options(width = 60)
    options(eps = FALSE)
    foo <- packageDescription("ffpe")
    # --- Sortediqrplot [] ---
    # Key functions: sortedIqrPlot
    library(ffpe)
    library(ffpeExampleData)
    data(lumibatch.GSE17565)
    sortedIqrPlot(lumibatch.GSE17565,dolog2=TRUE)
    # --- Sampleqc [] ---
    # Key functions: sampleQC
    QC <- sampleQC(lumibatch.GSE17565,xaxis="index",cor.to="pseudochip",QCmeasure="IQR")
    # --- Dotchart [] ---
    # Key functions: frame, dotchart, ifelse
    QCvsRNA <- data.frame(inputRNA.ng=lumibatch.GSE17565$inputRNA.ng,
                          rejectQC=QC$rejectQC)
    QCvsRNA <- QCvsRNA[order(QCvsRNA$rejectQC,-QCvsRNA$inputRNA.ng),]
    par(mgp=c(4,2,0))
    # --- Sampleqc2 [] ---
    # Key functions: sampleQC
    QC <- sampleQC(lumibatch.GSE17565,xaxis="index",cor.to="pseudochip",QCmeasure=log10(lumibatch.GSE17565$inputRNA.ng),labelnote="log10(RNA concentration)")
    # --- Process Rep [] ---
    # Key functions: lumiT, lumiN
    ##replicate 1
    lumibatch.rep1 <- lumibatch.QC[,lumibatch.QC$replicate==1]
    lumbiatch.rep1 <- lumiT(lumibatch.rep1,"log2")
    lumbiatch.rep1 <- lumiN(lumibatch.rep1,"quantile")
    ##replicate 2
    # --- Keepsamples [] ---
    # Key functions: intersect, omit, equal
    available.samples <- intersect(lumibatch.rep1$source,lumibatch.rep2$source)
    lumibatch.rep1 <- lumibatch.rep1[,na.omit(match(available.samples,lumibatch.rep1$source))]
    lumibatch.rep2 <- lumibatch.rep2[,na.omit(match(available.samples,lumibatch.rep2$source))]
    all.equal(lumibatch.rep1$source,lumibatch.rep2$source)
    # --- Repcor [] ---
    # Key functions: exprs, any
    probe.var <- apply(exprs(lumibatch.rep1),1,var)
    # --- Ttest [] ---
    # Key functions: rowttests, exprs, factor
    library(genefilter)
    ttests.rep1 <- rowttests(exprs(lumibatch.rep1),fac=factor(lumibatch.rep1$cell.type))
    ttests.rep2 <- rowttests(exprs(lumibatch.rep2),fac=factor(lumibatch.rep2$cell.type))
    pvals.rep1 <- ttests.rep1$p.value;names(pvals.rep1) <- rownames(ttests.rep1)
    pvals.rep2 <- ttests.rep2$p.value;names(pvals.rep2) <- rownames(ttests.rep2)
    # --- Catplot [] ---
    # Key functions: CATplot
    x <- CATplot(pvals.rep1,pvals.rep2,maxrank=1000,xlab="Size of top-ranked gene lists",ylab="Concordance")
    legend("topleft",lty=1:2,legend=c("Actual concordance","Concordance expected by chance"), bty="n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ffpe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ffpe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ffpe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FFPE:", paste0("    ffpe: ", packageVersion("ffpe"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ffpe_results.csv
    touch ${prefix}_ffpe_output.rds
    echo "BIOC_FFPE:" > versions.yml
    echo "    ffpe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FFPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FFPE(ch_input)

    emit:
    results  = BIOC_FFPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FFPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FFPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FFPE.out.versions  // channel: path(versions.yml)
}
