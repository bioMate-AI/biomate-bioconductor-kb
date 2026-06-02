#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MMDiff2
// This package detects statistically significant differences between read enrichment profiles in diffe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MMDiff2/inst/doc/MMDiff2.R
// Upstream  : MMDiffBamSubset, MotifDb
// Downstream: none
//
// Install: BiocManager::install("MMDiff2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MMDIFF2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mmdiff2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mmdiff2:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mmdiff2:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mmdiff2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mmdiff2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mmdiff2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MMDiff2)
    library(DBAmmd)
    library(Samples)
    library(jsonlite)

    # --- Data Initialization and Peak Loading ---
    # Key functions: DBAmmd, setRegions, getPeakReads
    ExperimentData <- list(genome = 'BSgenome.Mmusculus.UCSC.mm9',
                           dataDir = system.file("extdata",
                                                 package="MMDiffBamSubset"),
                           sampleSheet="Cfp1.csv")
    MetaData <- list('ExpData' = ExperimentData)
    MMD <- DBAmmd(MetaData)
    data('Cfp1-Peaks')
    MMD <- setRegions(MMD, Peaks)
    MMD <- getPeakReads(MMD)

    # --- Fragment Center Estimation and Histogram Computation ---
    # Key functions: estimateFragmentCenters, compHists
    MMD <- estimateFragmentCenters(MMD)
    MMD <- compHists(MMD, bin.length=20, whichPos="Center")

    # --- Distance Computation and Contrast Setup ---
    # Key functions: compDists, Samples, setContrast
    MMD <- compDists(MMD, dist.method = "MMD", run.parallel = FALSE)
    group1 <- Samples(MMD)$Condition == '1'
    names(group1) <- Samples(MMD)$SampleID
    group2 <- Samples(MMD)$Condition == '2'
    names(group2) <- Samples(MMD)$SampleID
    contrast <- list(group1=group1, group2=group2,
                     name1='WT,REsc', name2='Null')
    MMD <- setContrast(MMD, contrast=contrast)

    # --- Differential Testing and Results Reporting ---
    # Key functions: compPvals, reportResults
    MMD <- compPvals(MMD, dist.method='MMD')
    res <- reportResults(MMD)

    # --- Visualization of Peaks and Distances ---
    # Key functions: plotDists, plotDISTS4Peak
    Peak.ids <- names(res)
    plotDists(MMD, dist.method='MMD', whichContrast=1,
              diff.method='MMD.locfit', bUsePval=FALSE, th=0.1)
    if (length(Peak.ids) > 0) {
        plotDISTS4Peak(MMD, Peak.id=Peak.ids[1], dist.method='MMD',
                       whichContrast=1, Zoom=TRUE)
    }


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mmdiff2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mmdiff2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mmdiff2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MMDIFF2:", paste0("    mmdiff2: ", packageVersion("MMDiff2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mmdiff2_results.csv
    touch ${prefix}_mmdiff2_output.rds
    echo "BIOC_MMDIFF2:" > versions.yml
    echo "    mmdiff2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MMDIFF2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MMDIFF2(ch_input)

    emit:
    results  = BIOC_MMDIFF2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MMDIFF2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MMDIFF2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MMDIFF2.out.versions  // channel: path(versions.yml)
}
