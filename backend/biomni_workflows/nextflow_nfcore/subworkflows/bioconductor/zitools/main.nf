#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: zitools
// zitools allows for zero inflated count data analysis by either using down-weighting of excess zeros 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/zitools/inst/doc/zitools_tutorial.R
// Upstream  : DESeq2, microbiome, phyloseq, tidyverse
// Downstream: none
//
// Install: BiocManager::install("zitools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ZITOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-zitools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-zitools:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-zitools:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_zitools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_zitools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_zitools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(MissingValueHeatmap)
    library(jsonlite)

    # --- Dataset [] ---
    # Key functions: sample_data
    data("peerj32")
    sample_data(phyloseq)$time <- factor(sample_data(phyloseq)$time)
    # --- zi Main [] ---
    # Key functions: ziMain
    Zi <- ziMain(phyloseq)
    print(Zi)
    mean(Zi)
    # --- resample_deinflatedcounts [] ---
    # Key functions: resample_deinflatedcounts
    Zi <- resample_deinflatedcounts(Zi)
    boxplot(log2p(Zi), xlab = "samples", ylab = "log2(count+1)",
    main = paste("Iteration", i))
    # --- Run DESeq2 differential expression [] ---
    # Key functions: zi2deseq2, DESeq
    DDS <- zi2deseq2(Zi, ~time)
    DDS$Subject <- relevel(DDS$time, ref = "1")
    DDS <-  DESeq(DDS, test = "Wald", fitType = "local", sfType = "poscounts")
    # --- rownames_to_column [] ---
    # Key functions: rownames_to_column, arrange
    result_df<- cbind(as(result, "data.frame"),
    as(tax_table(phyloseq)[rownames(result), ], "matrix"))
    rownames_to_column(var = "OTU") %>%
    # --- Missing Value Heatmap [] ---
    # Key functions: MissingValueHeatmap
    MissingValueHeatmap(Zi2, xlab = "Sample")
    # --- plot PCA [] ---
    # Key functions: geom_point, xlim, ylim, xlab, ylab


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_zitools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_zitools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_zitools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ZITOOLS:", paste0("    zitools: ", packageVersion("zitools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zitools_results.csv
    touch ${prefix}_zitools_output.rds
    echo "BIOC_ZITOOLS:" > versions.yml
    echo "    zitools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ZITOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ZITOOLS(ch_input)

    emit:
    results  = BIOC_ZITOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ZITOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ZITOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ZITOOLS.out.versions  // channel: path(versions.yml)
}
