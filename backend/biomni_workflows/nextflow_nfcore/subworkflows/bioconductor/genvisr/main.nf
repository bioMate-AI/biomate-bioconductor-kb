#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenVisR
// Produce highly customizable publication quality graphics for genomic data primarily at the cohort le
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenVisR/inst/doc/Intro.R
// Upstream  : ggplot2, knitr, reshape2
// Downstream: none
//
// Install: BiocManager::install("GenVisR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENVISR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genvisr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genvisr:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genvisr:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genvisr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genvisr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genvisr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenVisR)
    library(jsonlite)

    # --- Transition and Transversion Analysis [] ---
    # Key functions: TvTi
    expec <- c("A->C or T->G (TV)"=.066, "A->G or T->C (TI)"=.217,
               "A->T or T->A (TV)"=.065, "G->A or C->T (TI)"=.4945,
               "G->C or C->G (TV)"=.0645, "G->T or C->A (TV)"=.093)
    TvTi(brcaMAF, y=expec, lab_txtAngle=45, fileType="MAF",
         palette=c("#77C55D", "#A461B4", "#C1524B", "#93B5BB", 
                   "#4F433F", "#BFA753"))


    # --- Genomic Coverage Visualisation [] ---
    # Key functions: genCov
    gr <- GenomicRanges::GRanges(seqnames=c("chr10"), 
                                 ranges=IRanges::IRanges(start=c(89622195), 
                                 end=c(89729532)), 
                                 strand=BiocGenerics::strand(c("+")))
    cov_input_A <- data.frame(chr=10, start=89622194:89729524, 
                              end=89622195:89729525, 
                              cov=c(rnorm(100000, mean=40), rnorm(7331, mean=10)))
    cov_input_B <- data.frame(chr=10, start=89622194:89729524, 
                              end=89622195:89729525, 
                              cov=c(rnorm(50000, mean=40), rnorm(7331, mean=10), 
                                    rnorm(50000, mean=40)))
    data_cov <- list("Sample A"=cov_input_A, "Sample B"=cov_input_B)
    genCov(data_cov, txdb, gr, genome, transform=c("Intron", "CDS", "UTR"), 
           base=c(10, 2, 2), reduce=TRUE)


    # --- Copy Number Visualisation [] ---
    # Key functions: cnSpec, cnView
    cnSpec(LucCNseg, genome="hg19")
    coordinate <- sort(sample(0:106455000, size=2000, replace=FALSE))
    cn <- c(rnorm(300, mean=3, sd=.2), rnorm(700, mean=2, sd=.2), 
            rnorm(1000, mean=3, sd=.2))
    data_cn <- data.frame(chromosome='chr14', coordinate=coordinate, cn=cn)
    data_seg <- data.frame(chromosome=14, start=coordinate[c(1, 301, 1001)], 
                           end=coordinate[c(300, 1000, 2000)], 
                           segmean=c(3, 2, 3))
    cnView(data_cn, z=data_seg, chr='chr14', genome='hg19', ideogram_txtSize=4)


    # --- Loss of Heterozygosity and Coverage Bars [] ---
    # Key functions: lohSpec, lohView, covBars
    lohSpec(x=HCC1395_Germline)
    lohView(HCC1395_Germline, chr='chr5', genome='hg19', ideogram_txtSize=4)
    cov_matrix <- matrix(sample(100000, 500), nrow=50, ncol=10, 
                         dimnames=list(0:49, paste0("Sample", 1:10)))
    covBars(cov_matrix, colour=c("blue", "grey", "red"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genvisr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genvisr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genvisr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENVISR:", paste0("    genvisr: ", packageVersion("GenVisR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genvisr_results.csv
    touch ${prefix}_genvisr_output.rds
    echo "BIOC_GENVISR:" > versions.yml
    echo "    genvisr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENVISR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENVISR(ch_input)

    emit:
    results  = BIOC_GENVISR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENVISR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENVISR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENVISR.out.versions  // channel: path(versions.yml)
}
