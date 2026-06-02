#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biomvRCNS
// In this package, a Hidden Semi Markov Model (HSMM) and one homogeneous segmentation model are design
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biomvRCNS/inst/doc/biomvRCNS.R
// Upstream  : Rsamtools
// Downstream: none
//
// Install: BiocManager::install("biomvRCNS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOMVRCNS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biomvrcns"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biomvrcns:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biomvrcns:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biomvrcns_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biomvrcns_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biomvrcns_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biomvRCNS)
    library(DataFrame)
    library(GRanges)
    library(IRanges)
    library(ScanBamParam)
    library(jsonlite)

    # --- Data Preparation [GRanges, DataFrame] ---
    # Key functions: GRanges, DataFrame
    data('coriell', package = 'biomvrcns')
    xgr <- GRanges(
        seqnames = coriell[, 2],
        IRanges(
            start = coriell[, 3],
            width = 1,
            names = coriell[, 1]
        )
    )
    values(xgr) <- DataFrame(coriell[, 4:5], row.names = NULL)
    xgr <- sort(xgr)

    # --- HSMM Segmentation [biomvRhsmm] ---
    # Key functions: biomvRhsmm
    rhsmm <- biomvRhsmm(
        x = xgr,
        maxbp = 1E5,
        J = 3,
        soj.type = 'gamma',
        com.emis = TRUE,
        emis.type = 'norm',
        prior.m = 'quantile',
        grp = c(1, 2)
    )

    # --- Alternative Segmentation [biomvRseg, biomvRmgmr] ---
    # Key functions: biomvRseg, biomvRmgmr
    rseg <- biomvRseg(
        x = xgr,
        maxbp = 4E4,
        maxseg = 10,
        family = 'norm',
        grp = c(1, 2)
    )
    rmgmrh <- biomvRmgmr(
        xgr,
        q = 0.9,
        high = TRUE,
        maxgap = 1000,
        minrun = 2500,
        grp = c(1, 2)
    )

    # --- DMR Detection [biomvRhsmm] ---
    # Key functions: biomvRhsmm
    data('variosm', package = 'biomvrcns')
    rhsmm_var <- biomvRhsmm(
        x = variosm,
        J = 6,
        maxbp = 100,
        emis.type = 'mvnorm',
        prior.m = 'cluster',
        maxgap = 100,
        com.emis = TRUE
    )
    DMRs <- GenomicRanges::reduce(
        rhsmm_var@res[mcols(rhsmm_var@res)[, 'STATE'] == '6'],
        min.gapwidth = 100
    )

    # --- Genomic Visualisation [biomvRGviz, plot] ---
    # Key functions: biomvRGviz, plot
    obj <- biomvRGviz(
        exprgr = xgr[seqnames(xgr) == '11', 'Coriell.05296'],
        seggr = rhsmm@res[mcols(rhsmm@res)[, 'SAMPLE'] == 'Coriell.05296'],
        tofile = FALSE
    )
    plot(rhsmm, tofile = FALSE)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biomvrcns_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biomvrcns_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biomvrcns_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOMVRCNS:", paste0("    biomvrcns: ", packageVersion("biomvRCNS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomvrcns_results.csv
    touch ${prefix}_biomvrcns_output.rds
    echo "BIOC_BIOMVRCNS:" > versions.yml
    echo "    biomvrcns: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOMVRCNS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOMVRCNS(ch_input)

    emit:
    results  = BIOC_BIOMVRCNS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOMVRCNS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOMVRCNS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOMVRCNS.out.versions  // channel: path(versions.yml)
}
