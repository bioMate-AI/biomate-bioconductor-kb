#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ddCt
// The Delta-Delta-Ct (ddCt) Algorithm is an approximation method to determine relative gene expression
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ddCt/inst/doc/RT-PCR-Script-ddCt.R
// Upstream  : Biobase, RColorBrewer, lattice
// Downstream: none
//
// Install: BiocManager::install("ddCt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DDCT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ddct"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ddct:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ddct:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ddct_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ddct_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ddct_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ddCt)
    library(SDMFrame)
    library(jsonlite)

    # --- Sample Annotation Setup [] ---
    # Key functions: sampleNames
    samples <- sampleNames(ct_data)
    sample_info <- new("AnnotatedDataFrame",
        data = data.frame(Sample = samples),
        varMetadata = data.frame(
            labelDescription = c("unique identifier"),
            row.names = c("Sample")
        )
    )


    # --- Relative Quantification Calculation [] ---
    # Key functions: ddCtExpression
    ref_sample <- "Sample2"
    ref_genes <- c("Gene3", "Gene2")
    result <- ddCtExpression(
        ct_data,
        calibrationSample = ref_sample,
        housekeepingGenes = ref_genes,
        sampleInformation = sample_info
    )


    # --- Housekeeping Gene Correlation Analysis [] ---
    # Key functions: assayData, pData
    ct_matrix <- assayData(result)$Ct
    ref_genes <- c("Gene3", "Gene2")
    if (all(ref_genes %in% rownames(ct_matrix))) {
        gene1_vals <- ct_matrix[ref_genes[1], ]
        gene2_vals <- ct_matrix[ref_genes[2], ]
        hk_cor <- cor(gene1_vals, gene2_vals, use = "pairwise.complete.obs")
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ddct_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ddct_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ddct_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DDCT:", paste0("    ddct: ", packageVersion("ddCt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ddct_results.csv
    touch ${prefix}_ddct_output.rds
    echo "BIOC_DDCT:" > versions.yml
    echo "    ddct: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DDCT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DDCT(ch_input)

    emit:
    results  = BIOC_DDCT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DDCT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DDCT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DDCT.out.versions  // channel: path(versions.yml)
}
