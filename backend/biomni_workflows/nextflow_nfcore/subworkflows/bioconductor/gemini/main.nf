#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gemini
// GEMINI uses log-fold changes to model sample-dependent and independent effects, and uses a variation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gemini/inst/doc/gemini-quickstart.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("gemini")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEMINI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gemini"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gemini:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gemini:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gemini_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gemini_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gemini_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gemini)
    library(jsonlite)


    # --- Load Data [] ---
    # Key functions: gemini, counts, guide.annotation, sample.replicate.annotation
    library("gemini")
    data("counts", "guide.annotation", "sample.replicate.annotation", package = "gemini")
    knitr::kable(head(counts[,1:5]), caption = "Counts matrix", align = 'l')

    # --- Table23 Annotations [] ---
    # Key functions: gemini_create_input, samplename
    knitr::kable(head(sample.replicate.annotation), caption = "Sample/replicate annotations")
    knitr::kable(head(guide.annotation[,1:3]), caption = "Guide/gene annotation")
    Input <- gemini_create_input(counts.matrix = counts,
                        sample.replicate.annotation = sample.replicate.annotation,
                        guide.annotation = guide.annotation,
                        ETP.column = 'pDNA', 
                        gene.column.names = c("U6.gene", "H1.gene"),
                        sample.column.name = "samplename",
                        verbose = TRUE)

    # Note: ETP column can also be specified by column index 
    # (e.g. ETP.column = c(1))

    # --- Calc Lfc [] ---
    # Key functions: gemini_calculate_lfc, gemini_initialize
    Input %<>% gemini_calculate_lfc(normalize = TRUE, 
                                    CONSTANT = 32)
    Model <- gemini_initialize(Input = Input, 
                      nc_gene = "CD81", 
                      pattern_join = ';',
                      pattern_split = ';', 
                      cores = 1,
                      verbose = TRUE)

    # --- Inference Shortcut [] ---
    # Key functions: gemini, gemini_plot_mae
    data("Model", package = "gemini") # This is the result of running the above line
    gemini_plot_mae(Model)

    # --- Gemini Score [] ---
    # Key functions: gemini_score
    # Use non-interacting gene pairs as nc_pairs. 
    # A caveat here is that this set is constructed only using negative controls! 
    # This probably leads to biased sampling of the null distribution, 
    # thereby overestimating the number of significant hits, but still is useful in this case.
    nc_pairs <- grep("6T|HPRT", rownames(Model$s), value = TRUE)

    # An example of some nc_pairs...
    head(nc_pairs, n = 5)

    # --- Table5 Fdr [] ---
    # Key functions: gemini_boxplot
    knitr::kable(Score$fdr_strong[order(Score$fdr_strong[,"A549"], decreasing = FALSE)[1:10],], caption = "FDRs for top 10 interactions in A549")
    gemini_boxplot(Model = Model, 
                   g = "BRCA2",
                   h = "PARP1",
                   nc_gene = "CD81",
                   sample = "A549",
    			   show_inference = TRUE, 
    			   identify_guides = TRUE
    			   )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gemini_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gemini_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gemini_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEMINI:", paste0("    gemini: ", packageVersion("gemini"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gemini_results.csv
    touch ${prefix}_gemini_output.rds
    echo "BIOC_GEMINI:" > versions.yml
    echo "    gemini: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEMINI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEMINI(ch_input)

    emit:
    results  = BIOC_GEMINI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEMINI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEMINI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEMINI.out.versions  // channel: path(versions.yml)
}
