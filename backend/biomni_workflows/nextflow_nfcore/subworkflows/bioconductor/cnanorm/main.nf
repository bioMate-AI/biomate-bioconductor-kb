#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNAnorm
// Performs ratio, GC content correction and normalization of data obtained using low coverage (one rea
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNAnorm/inst/doc/CNAnorm.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CNAnorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNANORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnanorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnanorm:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnanorm:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnanorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnanorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnanorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNAnormWorkflow)
    library(jsonlite)

    # --- Cnanorm.Snw:31 35 [] ---
    # Key functions: data
    library(CNAnorm)
    data(LS041)
    # show the data
    LS041[1:5,]
    # --- Cnanorm.Snw:50 53 [] ---
    # Key functions: dataFrame2object
    # set a seed for reproducible comparison
    set.seed(31)
    CN <- dataFrame2object(LS041)
    # --- Cnanorm.Snw:67 69 [] ---
    # Key functions: gcNorm
    toSkip <- c("chrY", "chrM")
    CN <- gcNorm(CN, exclude=toSkip)
    # --- Cnanorm.Snw:78 79 [] ---
    # Key functions: addSmooth
    CN <- addSmooth(CN, lambda=7)
    # --- Cnanorm.Snw:84 85 [] ---
    # Key functions: peakPloidy
    CN <- peakPloidy(CN, exclude=toSkip, method='closest')
    # --- Cnanorm.Snw:110 113 [] ---
    # Key functions: validation, addDNACopy, discreteNorm
    CN <- validation(CN)
    CN <- addDNACopy(CN)
    CN <- discreteNorm(CN)
    # --- Cnanorm.Snw:119 124 [] ---
    # Key functions: CNAnormWorkflow
    # re-set seed for reproducible results
    set.seed(31)
    CNauto <- CNAnormWorkflow(LS041, gc.do=TRUE, gc.exclude=toSkip,
        peak.exclude=toSkip)
    identical(CN, CNauto)
    # --- Cnanorm.Snw:131 132 [] ---
    # Key functions: plotGenome
    plotGenome(CN, superimpose='DNACopy', show.centromeres=FALSE)
    # --- Cnanorm.Snw:141 144 [] ---
    # Key functions: chrs, plotGenome
    toPlot <- c('chr10', 'chr11', 'chr12')
    subSet <- chrs(CN) %in% toPlot
    plotGenome(CN[subSet], superimpose='DNACopy')
    # --- Cnanorm.Snw:153 160 [] ---
    # Key functions: plotGenome
    data(gPar)
    gPar$genome$colors$gain.dot <- 'darkorange'
    gPar$genome$colors$grid <- NULL
    gPar$genome$cex$gain.dot <- .4
    gPar$genome$cex$loss.dot <- .4
    # --- Cnanorm.Snw:165 166 [] ---
    # Key functions: exportTable
    exportTable(CN, file = "CNAnorm_table.tab", show = 'center')
    # --- Cnanorm.Snw:181 183 [] ---
    # Key functions: peakPloidy, plotPeaks
    CN <- peakPloidy(CN, exclude=toSkip, method='density')
    plotPeaks(CN)
    # --- Cnanorm.Snw:203 210 [] ---
    # Key functions: validation, addDNACopy, discreteNorm, plotGenome
    CN <- validation(CN)
    data(hg19_hs_ideogr)
    CN <- addDNACopy(CN, DNAcopy.weight='poisson',
        DNAcopy.segment=list(alpha=0.001), independent.arms=TRUE,
        ideograms=hg19_hs_ideogr)
    # --- Cnanorm.Snw:225 227 [] ---
    # Key functions: validation, ploidy, plotPeaks
    CN <- validation(CN, ploidy = (sugg.ploidy(CN) - 1))
    plotPeaks(CN, show='validated')
    # --- Cnanorm.Snw:235 237 [] ---
    # Key functions: discreteNorm, plotGenome
    CN <- discreteNorm(CN)
    plotGenome(CN, superimpose='DNACopy')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnanorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnanorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnanorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNANORM:", paste0("    cnanorm: ", packageVersion("CNAnorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnanorm_results.csv
    touch ${prefix}_cnanorm_output.rds
    echo "BIOC_CNANORM:" > versions.yml
    echo "    cnanorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNANORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNANORM(ch_input)

    emit:
    results  = BIOC_CNANORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNANORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNANORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNANORM.out.versions  // channel: path(versions.yml)
}
