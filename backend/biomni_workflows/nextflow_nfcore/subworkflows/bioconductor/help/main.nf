#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HELP
// The package contains a modular pipeline for analysis of HELP microarray data, and includes graphical
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HELP/inst/doc/HELP.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HELP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HELP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-help"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-help:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-help:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_help_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_help_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_help_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Density)
    library(SAMPLEs)
    library(jsonlite)

    # --- Sub [] ---
    # Key functions: path, readSampleKey, SAMPLEs, sampleNames
    chips <- sub("[_.]*532[_.]*pair.*","",basename(msp1.files))
    chips ## CHIP_IDs
    samplekey <- file.path(data.path, "sample.key.txt")
    chips <- readSampleKey(file=samplekey,chips=chips)
    chips ## SAMPLEs (from supplied key)
    # --- Calctm [] ---
    # Key functions: calcTm, getFeatures
    calcTm("ATCTAGGAAGATTTAGAGAGGCAATGTGTCATTTAGCATCTAATTTTACC")
    calcTm(getFeatures(pairs,"SEQUENCE")[1:4])
    # --- Calcgc [] ---
    # Key functions: calcGC, getFeatures
    calcGC("ATCTAGGAAGATTTAGAGAGGCAATGTGTCATTTAGCATCTAATTTTACC")
    calcGC(getFeatures(pairs,"SEQUENCE")[1:4])
    # --- Getsamples [] ---
    # Key functions: getSamples, calcPrototype
    getSamples(pairs)[1:4,]
    calcPrototype(pairs,center=FALSE)[1:4]
    # --- Fig1 [] ---
    # Key functions: plotChip
    plotChip(pairs, sample="Brain2")
    # --- Fig2 [] ---
    # Key functions: sample, plotChip
    x <- rep(1:100,100)
    y <- rep(1:100,each=100)
    z <- x*(1001:11000/1000)
    z <- z-mean(z)
    z <- z*(sample(1:10000/10000)+1)
    # --- Exprs [] ---
    # Key functions: exprs, exprs2
    exprs(pairs) <- log2(exprs(pairs))
    exprs2(pairs) <- log2(exprs2(pairs))
    # --- Fig3 [] ---
    # Key functions: plotFeature
    plotFeature(pairs[,"Brain2"],cex=0.5)
    # --- Fig4 [] ---
    # Key functions: density, rainbow
    plot(density(x),main="")
    for (i in 1:20) {
    d <- density(x[which(y==i)])
    lines(d$x,0.3*d$y/max(d$y),col=rainbow(n=20,start=0,end=0.66)[21-i])
    }
    # --- Fig5 [] ---
    # Key functions: quantileNormalize, density, Density
    x2 <- quantileNormalize(x,y,num.bins=20,num.steps=1,mode="discrete")
    d2 <- density(x2)
    plot(c(min(d2$x), max(d2$x)), c(0, 20), type="p", cex=0, ylab="Density (by bin)", xlab="", main="")
    # --- Which [] ---
    # Key functions: getFeatures, getSamples
    rand <- which(getFeatures(pairs, "TYPE")=="RAND")
    msp.rand <- getSamples(pairs, element="exprs")[rand,]
    hpa.rand <- getSamples(pairs, element="exprs2")[rand,]
    # --- Which [] ---
    # Key functions: getFeatures, getSamples, quantileNormalize
    norand <- which(getFeatures(pairs, "TYPE")=="DATA")
    size <- as.numeric(getFeatures(pairs, "SIZE"))[norand]
    msp <- getSamples(pairs, "Brain2", element="exprs")[norand]
    hpa <- getSamples(pairs, "Brain2", element="exprs2")[norand]
    nofail <- which(msp>msp.fail["Brain2"] | hpa>hpa.fail["Brain2"])
    # --- Which [] ---
    # Key functions: quantileNormalize
    meth <- which(msp>msp.fail["Brain2"] & hpa<=hpa.meth["Brain2"])
    hpa.norm <- hpa
    hpa.norm[meth] <- quantileNormalize(hpa[meth],size[meth])
    nometh <- which(hpa>hpa.meth["Brain2"])
    hpa.norm[nometh] <- quantileNormalize(hpa[nometh],size[nometh])
    # --- Exprs [] ---
    # Key functions: exprs, exprs2, getSamples
    pairs.norm <- pairs
    exprs(pairs.norm)[norand, "Brain2"] <- msp.norm
    exprs2(pairs.norm)[norand, "Brain2"] <- hpa.norm
    getSamples(pairs, element="exprs")[1:5,]
    getSamples(pairs.norm, element="exprs")[1:5,]
    # --- Getsamples [] ---
    # Key functions: getSamples, getFeatures, combineData
    data <- getSamples(pairs,element="exprs2")
    seqids <- getFeatures(pairs,'SEQ_ID')
    weight <- getSamples(pairs,element="exprs")
    combineData(data, seqids, weight, trim=0.2)[1:5,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_help_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_help_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_help_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HELP:", paste0("    help: ", packageVersion("HELP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_help_results.csv
    touch ${prefix}_help_output.rds
    echo "BIOC_HELP:" > versions.yml
    echo "    help: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HELP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_HELP(ch_input)

    emit:
    results  = BIOC_HELP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HELP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HELP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HELP.out.versions  // channel: path(versions.yml)
}
