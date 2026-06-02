#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DMRcaller
// Uses Bisulfite sequencing data in two conditions and identifies differentially methylated regions be
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DMRcaller/inst/doc/DMRcaller.R
// Upstream  : betareg
// Downstream: none
//
// Install: BiocManager::install("DMRcaller")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DMRCALLER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dmrcaller"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dmrcaller:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dmrcaller:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dmrcaller_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dmrcaller_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dmrcaller_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DMRcaller)
    library(GRanges)
    library(GRangesList)
    library(jsonlite)

    # --- De Novo DMR Detection [] ---
    # Key functions: computeDMRs
    chr_local <- GRanges(seqnames = Rle("Chr3"), ranges = IRanges(5E5,6E5))
    DMRsNoiseFilterCG <- computeDMRs(methylationDataList[["WT"]],
                          methylationDataList[["met1-3"]],
                          regions = chr_local,
                          context = "CG",
                          method = "noise_filter",
                          windowSize = 100,
                          kernelFunction = "triangular",
                          test = "score",
                          pValueThreshold = 0.01,
                          minCytosinesCount = 4,
                          minProportionDifference = 0.4,
                          minGap = 0,
                          minSize = 50,
                          minReadsPerCytosine = 4,
                          cores = 1)
    DMRsNeighbourhoodCG <- computeDMRs(methylationDataList[["WT"]],
                                       methylationDataList[["met1-3"]],
                                       regions = chr_local,
                                       context = "CG",
                                       method = "neighbourhood",
                                       test = "score",
                                       pValueThreshold = 0.01,
                                       minCytosinesCount = 4,
                                       minProportionDifference = 0.4,
                                       minGap = 200,
                                       minSize = 1,
                                       minReadsPerCytosine = 4,
                                       cores = 1)


    # --- Targeted DMR Filtering and Annotation [] ---
    # Key functions: filterDMRs
    data(GEs)
    genes <- GEs[which(GEs$type == "gene")]
    DMRsGenesCG <- filterDMRs(methylationDataList[["WT"]],
                              methylationDataList[["met1-3"]],
                              potentialDMRs = genes[overlapsAny(genes, chr_local)],
                              context = "CG",
                              test = "score",
                              pValueThreshold = 0.01,
                              minCytosinesCount = 4,
                              minProportionDifference = 0.4,
                              minReadsPerCytosine = 3,
                              cores = 1)


    # --- DMR Merging and Downstream Analysis [] ---
    # Key functions: mergeDMRsIteratively, analyseReadsInsideRegionsForCondition
    DMRsNoiseFilterCGMerged <- mergeDMRsIteratively(DMRsNoiseFilterCG,
                                                    minGap = 200,
                                                    respectSigns = TRUE,
                                                    methylationDataList[["WT"]],
                                                    methylationDataList[["met1-3"]],
                                                    context = "CG",
                                                    minProportionDifference = 0.4,
                                                    minReadsPerCytosine = 4,
                                                    pValueThreshold = 0.01,
                                                    test="score")
    DMRsNoiseFilterCGreadsCHH <- analyseReadsInsideRegionsForCondition(
                                  DMRsNoiseFilterCGMerged,
                                  methylationDataList[["WT"]], context = "CHH",
                                  label = "WT")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dmrcaller_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dmrcaller_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dmrcaller_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DMRCALLER:", paste0("    dmrcaller: ", packageVersion("DMRcaller"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmrcaller_results.csv
    touch ${prefix}_dmrcaller_output.rds
    echo "BIOC_DMRCALLER:" > versions.yml
    echo "    dmrcaller: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DMRCALLER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DMRCALLER(ch_input)

    emit:
    results  = BIOC_DMRCALLER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DMRCALLER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DMRCALLER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DMRCALLER.out.versions  // channel: path(versions.yml)
}
