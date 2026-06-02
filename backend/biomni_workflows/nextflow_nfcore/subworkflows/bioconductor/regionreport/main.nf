#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regionReport
// Generate HTML or PDF reports to explore a set of regions such as the results from annotation-agnosti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regionReport/inst/doc/bumphunterExample.R
// Upstream  : GenomicRanges, RefManageR, bumphunter, derfinder, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("regionReport")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONREPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regionreport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regionreport:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regionreport:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_regionreport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regionreport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regionreport_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(regionReport)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Differential Expression Report with DESeq2 [] ---
    # Key functions: deseq2Report
    counts <- matrix(rnbinom(100, mu = 10, size = 10), ncol = 4)
    coldata <- data.frame(group = factor(c("A", "A", "B", "B")))
    dds <- DESeq2::DESeqDataSetFromMatrix(
        countData = counts,
        colData = coldata,
        design = ~ group
    )
    dds <- DESeq2::DESeq(dds)
    regionreport::deseq2Report(
        dds = dds,
        project = "DESeq2 Analysis Report",
        outdir = "deseq2_report",
        output = "index"
    )


    # --- Differential Expression Report with edgeR [] ---
    # Key functions: edgeReport
    counts <- matrix(rnbinom(100, mu = 10, size = 10), ncol = 4)
    group <- factor(c("A", "A", "B", "B"))
    dge <- edgeR::DGEList(counts = counts, group = group)
    dge <- edgeR::calcNormFactors(dge)
    regionreport::edgeReport(
        dge = dge,
        project = "edgeR Analysis Report",
        outdir = "edger_report",
        output = "index"
    )


    # --- Derfinder Coverage Report [] ---
    # Key functions: derfinderReport
    regionreport::derfinderReport(
        prefix = "derfinder_results",
        outdir = "derfinder_report",
        project = "Derfinder Analysis Report",
        browse = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regionreport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regionreport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regionreport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONREPORT:", paste0("    regionreport: ", packageVersion("regionReport"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regionreport_results.csv
    touch ${prefix}_regionreport_output.rds
    echo "BIOC_REGIONREPORT:" > versions.yml
    echo "    regionreport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONREPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_REGIONREPORT(ch_input)

    emit:
    results  = BIOC_REGIONREPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONREPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONREPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONREPORT.out.versions  // channel: path(versions.yml)
}
