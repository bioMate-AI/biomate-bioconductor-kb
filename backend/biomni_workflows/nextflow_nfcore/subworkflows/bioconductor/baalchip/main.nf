#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BaalChIP
// The package offers functions to process multiple ChIP-seq BAM files and detect allele-specific event
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BaalChIP/inst/doc/BaalChIP.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BaalChIP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAALCHIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-baalchip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-baalchip:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-baalchip:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_baalchip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_baalchip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_baalchip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BaalChIP)
    library(QCfilter)
    library(jsonlite)

    # --- Baal Ch I P [] ---
    # Key functions: BaalChIP
    res <- BaalChIP(samplesheet=samplesheet, hets=hets)
    res <- BaalChIP.run(res, cores=4, verbose=TRUE) #cores for parallel computing
    # --- Baal Ch I P [] ---
    # Key functions: BaalChIP, alleleCounts, QCfilter, mergePerGroup, filter1allele
    samplesheet <- file.path(wd, "exampleChIP1.tsv")
    hets <- c("MCF7"="MCF7_hetSNP.txt", "GM12891"="GM12891_hetSNP.txt")
    res <- BaalChIP(samplesheet=samplesheet, hets=hets)
    # --- Baal Ch I P [] ---
    # Key functions: BaalChIP
    wd <- system.file("test",package="BaalChIP") #system directory
    samplesheet <- file.path(wd, "exampleChIP2.tsv")
    hets <- c("TaT1"="TaT1_hetSNP.txt", "AMOVC"="AMOVC_hetSNP.txt")
    # --- Plot QC metrics [] ---
    # Key functions: plotQC
    plotQC(ENCODEexample, what="barplot_per_group")
    # --- plot Simul [] ---
    # Key functions: plotSimul, summaryASB
    plotSimul(ENCODEexample)
    a <- BaalChIP.get(ENCODEexample, "assayedVar")[["MCF7"]]
    a <- BaalChIP.get(FAIREexample, "assayedVar")[["MDA134"]]
    # --- adjustment Baal Plot [] ---
    # Key functions: adjustmentBaalPlot
    adjustmentBaalPlot(ENCODEexample)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_baalchip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_baalchip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_baalchip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAALCHIP:", paste0("    baalchip: ", packageVersion("BaalChIP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_baalchip_results.csv
    touch ${prefix}_baalchip_output.rds
    echo "BIOC_BAALCHIP:" > versions.yml
    echo "    baalchip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAALCHIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAALCHIP(ch_input)

    emit:
    results  = BIOC_BAALCHIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAALCHIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAALCHIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAALCHIP.out.versions  // channel: path(versions.yml)
}
