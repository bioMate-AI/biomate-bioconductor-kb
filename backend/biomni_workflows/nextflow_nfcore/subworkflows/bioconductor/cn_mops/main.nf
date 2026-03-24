#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cn.mops
// cn.mops (Copy Number estimation by a Mixture Of PoissonS) is a data processing pipeline for copy num
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cn.mops/inst/doc/cn.mops.R
// Upstream  : Biobase, GenomeInfoDb, GenomicRanges
// Downstream: panelcn.mops
//
// Install: BiocManager::install("cn.mops")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CN_MOPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cn_mops"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cn.mops:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cn.mops:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cn_mops_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cn_mops_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cn_mops_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Files [] ---
    # Key functions: files, getReadCountsFromBAM
    ## BAMFiles <- list.files(pattern=".bam$")
    ## bamDataRanges <- getReadCountsFromBAM(BAMFiles)
    # --- Mops [] ---
    # Key functions: mops
    ## res <- cn.mops(bamDataRanges)
    # --- Data [] ---
    # Key functions: mops, off
    data(cn.mops)
    resCNMOPS <- cn.mops(XRanges)
    pdf("003.pdf")
    plot(resCNMOPS,which=7,toFile=TRUE)
    dev.off()
    # --- Files [] ---
    # Key functions: files, getReadCountsFromBAM
    BAMFiles <- list.files(system.file("extdata", package="cn.mops"),pattern=".bam$",
    		full.names=TRUE)
    bamDataRanges <- getReadCountsFromBAM(BAMFiles,
    		sampleNames=paste("Sample",1:3))
    # --- Mops [] ---
    # Key functions: mops
    ## resCNMOPS <- cn.mops(XRanges)
    # --- Calcintegercopynumbers [] ---
    # Key functions: calcIntegerCopyNumbers
    resCNMOPS <- calcIntegerCopyNumbers(resCNMOPS)
    # --- Mops [] ---
    # Key functions: mops
    ## resCNMOPSX <- cn.mops(X)
    # --- Calcintegercopynumbers [] ---
    # Key functions: calcIntegerCopyNumbers
    ## resCNMOPSX <- calcIntegerCopyNumbers(resCNMOPSX)
    # --- All [] ---
    # Key functions: all, individualCall
    ## all(individualCall(resCNMOPSX)==individualCall(resCNMOPS))
    # --- Cnvs [] ---
    # Key functions: cnvs
    cnvs(resCNMOPS)[1:5]
    # --- Cnvr [] ---
    # Key functions: cnvr
    cnvr(resCNMOPS)[1,1:5]
    # --- Ranges [] ---
    # Key functions: ranges, cnvr
    ranges(cnvr(resCNMOPS))[1:2]
    ranges(cnvr(resCNMOPS)) %over% ranges(CNVRanges)
    # --- Segplot [] ---
    # Key functions: segplot
    ## segplot(resCNMOPS,sampleIdx=13)
    # --- Pdf [] ---
    # Key functions: segplot, off
    pdf("002.pdf")
    segplot(resCNMOPS,sampleIdx=13,seqnames="chrA")
    dev.off()
    # --- Pdf [] ---
    # Key functions: off
    pdf("001.pdf")
    plot(resCNMOPS,which=1,toFile=TRUE)
    dev.off()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cn_mops_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cn_mops_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cn_mops_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CN_MOPS:", paste0("    cn_mops: ", packageVersion("cn.mops"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cn_mops_results.csv
    touch ${prefix}_cn_mops_output.rds
    echo "BIOC_CN_MOPS:" > versions.yml
    echo "    cn_mops: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CN_MOPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CN_MOPS(ch_input)

    emit:
    results  = BIOC_CN_MOPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CN_MOPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CN_MOPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CN_MOPS.out.versions  // channel: path(versions.yml)
}
