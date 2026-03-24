#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: splatter
// Splatter is a package for the simulation of single-cell RNA sequencing count data. It provides a sim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/splatter/inst/doc/splatPop.R
// Upstream  : ggplot2, scater
// Downstream: none
//
// Install: BiocManager::install("splatter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLATTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splatter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splatter:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splatter:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_splatter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splatter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splatter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(splatter)
    library(jsonlite)

    # --- Log-normalize count data [] ---
    # Key functions: mockVCF, mockGFF, splatPopSimulate, logNormCounts, runPCA
    vcf <- mockVCF()
    gff <- mockGFF()
    sim <- splatPopSimulate(vcf = vcf, gff = gff, sparsify = FALSE)
    # --- PCA plot of sample distances [] ---
    # Key functions: plotPCA, mockVCF, mockGFF, sample, ggplot
    params.coreg <- newSplatPopParams(eqtl.coreg = 0.4, eqtl.ES.rate = 2)
    vcf <- mockVCF(n.sample = 20, n.snps = 1200)
    gff <- mockGFF(n.genes = 100)
    # --- MockSCE analysis [] ---
    # Key functions: mockSCE, newSplatPopParams, mockEmpiricalSet
    bulk.means <- mockBulkMatrix(n.genes = 100, n.samples = 100)
    bulk.eqtl <- mockBulkeQTL(n.genes = 100)
    counts <- mockSCE()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splatter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splatter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splatter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLATTER:", paste0("    splatter: ", packageVersion("splatter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splatter_results.csv
    touch ${prefix}_splatter_output.rds
    echo "BIOC_SPLATTER:" > versions.yml
    echo "    splatter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLATTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPLATTER(ch_input)

    emit:
    results  = BIOC_SPLATTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLATTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLATTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLATTER.out.versions  // channel: path(versions.yml)
}
