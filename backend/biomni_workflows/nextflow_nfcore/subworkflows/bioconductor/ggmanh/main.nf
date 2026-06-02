#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggmanh
// Manhattan plot and QQ Plot are commonly used to visualize the end result of Genome Wide Association 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggmanh/inst/doc/ggmanh.R
// Upstream  : BiocManager
// Downstream: none
//
// Install: BiocManager::install("ggmanh")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGMANH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggmanh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggmanh:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggmanh:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggmanh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggmanh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggmanh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggmanh)
    library(jsonlite)

    # --- Data Preprocessing [Data Preprocessing] ---
    # Key functions: manhattan_data_preprocess
    simdata <- data.frame(
        "chromosome" = factor(sample(c(1:22, "X"), size = 1000, replace = TRUE),
                              levels = c(1:22, "X")),
        "position" = sample(1:100000000, size = 1000),
        "P.value" = rbeta(1000, shape1 = 5, shape2 = 1)^7
    )
    mpdata <- manhattan_data_preprocess(
        x = simdata,
        pval.colname = "P.value",
        chr.colname = "chromosome",
        pos.colname = "position"
    )

    # --- Genome-wide Manhattan Plotting [Visualisation] ---
    # Key functions: manhattan_plot
    mpdata$label <- ""
    sig_idx <- mpdata$P.value < 5e-5
    mpdata$label[sig_idx] <- sprintf("Label: %i", seq_len(sum(sig_idx)))
    g_manh <- manhattan_plot(
        x = mpdata,
        pval.colname = "P.value",
        chr.colname = "chromosome",
        pos.colname = "position",
        plot.title = "Simulated GWAS Manhattan Plot",
        rescale = TRUE,
        label.colname = "label"
    )

    # --- Chromosome Zoom Visualization [Visualisation] ---
    # Key functions: manhattan_plot
    g_chr5 <- manhattan_plot(
        x = mpdata,
        chromosome = 5,
        pval.colname = "P.value",
        chr.colname = "chromosome",
        pos.colname = "position",
        plot.title = "Chromosome 5 Zoom"
    )

    # --- Binned Data Preprocessing [Data Preprocessing] ---
    # Key functions: binned_manhattan_preprocess
    mpdata_binned <- binned_manhattan_preprocess(
        x = mpdata,
        pval.colname = "P.value",
        chr.colname = "chromosome",
        pos.colname = "position",
        bins.x = 7,
        bins.y = 100,
        chr.gap.scaling = 0.5,
        show.message = FALSE,
        summarise.expression.list = list(
            max_log10p ~ max(-log10(P.value)),
            signif ~ ifelse(max(P.value) < 5e-8, "Significant", "Not")
        )
    )

    # --- Binned Manhattan Plotting [Visualisation] ---
    # Key functions: binned_manhattan_plot
    g_binned <- binned_manhattan_plot(
        x = mpdata_binned,
        pval.colname = "P.value",
        chr.colname = "chromosome",
        pos.colname = "position",
        bins.x = 7,
        bins.y = 100,
        bin.outline = TRUE,
        show.legend = FALSE,
        plot.title = "Binned Manhattan Plot"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggmanh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggmanh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggmanh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGMANH:", paste0("    ggmanh: ", packageVersion("ggmanh"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggmanh_results.csv
    touch ${prefix}_ggmanh_output.rds
    echo "BIOC_GGMANH:" > versions.yml
    echo "    ggmanh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGMANH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGMANH(ch_input)

    emit:
    results  = BIOC_GGMANH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGMANH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGMANH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGMANH.out.versions  // channel: path(versions.yml)
}
