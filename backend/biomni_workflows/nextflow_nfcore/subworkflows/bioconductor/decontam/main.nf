#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: decontam
// Simple statistical identification of contaminating sequence features in marker-gene or metagenomics 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/decontam/inst/doc/decontam_intro.R
// Upstream  : phyloseq, ggplot2
// Downstream: none
//
// Install: BiocManager::install("decontam")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECONTAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-decontam"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-decontam:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-decontam:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_decontam_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_decontam_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_decontam_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(decontam)
    library(jsonlite)

    # --- Inspect Library Sizes [] ---
    # Key functions: ggplot
    df <- as.data.frame(sample_data(ps)) # Put sample_data into a ggplot-friendly data.frame
    df$LibrarySize <- sample_sums(ps)
    df <- df[order(df$LibrarySize),]
    # --- Identify Contaminants by Frequency [] ---
    # Key functions: plot_frequency, xlab
    plot_frequency(ps, taxa_names(ps)[c(1,3)], conc="quant_reading") +
    xlab("DNA Concentration (PicoGreen fluorescent intensity)")
    # --- Define Negative Controls [] ---
    # Key functions: sample_data
    sample_data(ps)$is.neg <- sample_data(ps)$Sample_or_Control == "Control Sample"
    contamdf.prev <- isContaminant(ps, method="prevalence", neg="is.neg")
    table(contamdf.prev$contaminant)
    # --- Inspect Library Sizes [] ---
    # Key functions: ggplot, xlab
    ps.pa <- transform_sample_counts(ps, function(abund) 1*(abund>0))
    ps.pa.neg <- prune_samples(sample_data(ps.pa)$Sample_or_Control == "Control Sample", ps.pa)
    ps.pa.pos <- prune_samples(sample_data(ps.pa)$Sample_or_Control == "True Sample", ps.pa)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_decontam_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_decontam_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_decontam_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DECONTAM:", paste0("    decontam: ", packageVersion("decontam"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decontam_results.csv
    touch ${prefix}_decontam_output.rds
    echo "BIOC_DECONTAM:" > versions.yml
    echo "    decontam: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DECONTAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DECONTAM(ch_input)

    emit:
    results  = BIOC_DECONTAM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DECONTAM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DECONTAM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DECONTAM.out.versions  // channel: path(versions.yml)
}
