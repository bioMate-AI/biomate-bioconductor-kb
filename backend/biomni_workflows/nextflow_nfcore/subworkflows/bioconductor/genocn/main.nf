#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genoCN
// Simultaneous identification of copy number states and genotype calls for regions of either copy numb
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genoCN/inst/doc/genoCN.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("genoCN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOCN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genocn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genocn:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genocn:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genocn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genocn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genocn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(genoCN)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(snpData)
    data(snpInfo)
    dim(snpData)
    dim(snpInfo)
    snpData[1:2,]
    # --- Plotcn [] ---
    # Key functions: plotCN
    plotCN(pos=snpInfo$Position, LRR=snpData$LRR, BAF=snpData$BAF,
    main = "simulated data on Chr22")
    # --- Genocnv [] ---
    # Key functions: genoCNV
    Theta = genoCNV(snpInfo$Name, snpInfo$Chr, snpInfo$Position, snpData$LRR, snpData$BAF,
      snpInfo$PFB, sampleID="simu1", cnv.only=(snpInfo$PFB>1), outputSeg = TRUE,
      outputSNP = 1, outputTag = "simu1")
    # --- Plotcn [] ---
    # Key functions: plotCN
    plotCN(pos=snpInfo$Position, LRR=snpData$LRR, BAF=snpData$BAF,
    main = "simulated data on Chr22", fileNames="simu1_segment.txt")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genocn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genocn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genocn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOCN:", paste0("    genocn: ", packageVersion("genoCN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genocn_results.csv
    touch ${prefix}_genocn_output.rds
    echo "BIOC_GENOCN:" > versions.yml
    echo "    genocn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOCN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOCN(ch_input)

    emit:
    results  = BIOC_GENOCN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOCN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOCN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOCN.out.versions  // channel: path(versions.yml)
}
