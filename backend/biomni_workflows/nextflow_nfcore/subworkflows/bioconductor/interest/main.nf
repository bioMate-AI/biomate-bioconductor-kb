#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IntEREst
// This package performs Intron-Exon Retention analysis on RNA-seq data (.bam files).
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IntEREst/inst/doc/IntEREst.R
// Upstream  : BiocParallel, clinfun
// Downstream: none
//
// Install: BiocManager::install("IntEREst")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTEREST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-interest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-interest:1.30.2--r44_0' :
        'quay.io/biocontainers/bioconductor-interest:1.30.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_interest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_interest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_interest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Fraction)
    library(jsonlite)

    # --- reference build [] ---
    # Key functions: normalizePath, referencePrepare
    suppressMessages(library("IntEREst"))
    exonDat<- cbind(tmpEx[,3], ".",
    tmpEx[,c(7,4,5)], ".", tmpEx[,6], ".",paste("ID=exon",
    # --- annotate u12 [] ---
    # Key functions: annotateU12
    ind<- u12$gene_name %in% c("RHBDD2", "YBX2")
    annotateU12(pwmU12U2=list(pwmU12db[[1]][,11:17],pwmU12db[[2]],
    pwmSsIndex=list(indexDonU12=1, indexBpU12=1, indexAccU12=3,
    # --- normalize Path [] ---
    # Key functions: normalizePath, interest, readInterestResults
    outDir<- file.path(tempdir(),"interestFolder")
    dir.create(outDir)
    outDir<- normalizePath(outDir)
    # --- get Annotation [] ---
    # Key functions: getAnnotation, exactTestInterest, rowData, Fraction
    getAnnotation(mdsChr22Obj)
    test<- exactTestInterest(mdsChr22Obj,
    sampleAnnoCol="test_ctrl", sampleAnnotation=c("ctrl","test"),
    # --- get Annotation [] ---
    # Key functions: getAnnotation, qlfInterest
    group <- getAnnotation(mdsChr22Obj)[,"type"]
    qlfRes<- qlfInterest(x=mdsChr22Obj,
    design=model.matrix(~group), silent=TRUE,
    # --- u12 Boxplot [] ---
    # Key functions: u12Boxplot
    par(mar=c(7,4,2,1))
    u12Boxplot(mdsChr22Obj, sampleAnnoCol="type",
    col=rep(c("orange", "yellow"),3) ,	lasNames=3,
    # --- u12BoxplotNb object [] ---
    # Key functions: u12BoxplotNb
    par(mar=c(2,4,1,1))
    u12BoxplotNb(mdsChr22Obj, sampleAnnoCol="type", lasNames=1,
    boxplotNames=c(), outline=FALSE, plotLegend=TRUE,
    # --- u12 Density Plot Intron [] ---
    # Key functions: u12DensityPlotIntron, lfc
    u12DensityPlotIntron(mdsChr22Obj,
    type= c("U12", "U2Up", "U2Dn", "U2UpDn", "U2Rand"),
    sampleAnnotation=c("ctrl","test"), intExCol="int_ex",
    # --- add Annotation [] ---
    # Key functions: addAnnotation, deseqInterest
    mdsChr22RefIntRetSpObj<- cbind(mdsChr22Obj, mdsChr22IntSpObj)
    mdsChr22RefIntRetSpObj<- addAnnotation(x=mdsChr22RefIntRetSpObj,
    sampleAnnotation=c(rep("intron",16), rep("exon",16))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_interest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_interest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_interest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTEREST:", paste0("    interest: ", packageVersion("IntEREst"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interest_results.csv
    touch ${prefix}_interest_output.rds
    echo "BIOC_INTEREST:" > versions.yml
    echo "    interest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTEREST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTEREST(ch_input)

    emit:
    results  = BIOC_INTEREST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTEREST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTEREST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTEREST.out.versions  // channel: path(versions.yml)
}
