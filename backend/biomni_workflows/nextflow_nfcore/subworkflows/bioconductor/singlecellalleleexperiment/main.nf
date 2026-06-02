#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SingleCellAlleleExperiment
// Defines a S4 class that is based on SingleCellExperiment. In addition to the usual gene layer the ob
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SingleCellAlleleExperiment/inst/doc/scae_intro.R
// Upstream  : AnnotationDbi, DropletUtils, ggplot2, patchwork, scaeData
// Downstream: none
//
// Install: BiocManager::install("SingleCellAlleleExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLECELLALLELEEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singlecellalleleexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singlecellalleleexperiment:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-singlecellalleleexperiment:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_singlecellalleleexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singlecellalleleexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singlecellalleleexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellAlleleExperiment)
    library(jsonlite)


    # --- Warning=false [] ---
    # Key functions: read_allele_counts, metadata, example_data, yes, knee_info
    scae <- read_allele_counts(example_data_10k$dir,
                               sample_names="example_data",
                               filter_mode="yes",
                               lookup_file=lookup,
                               barcode_file=example_data_10k$barcodes,
                               gene_file=example_data_10k$features,
                               matrix_file=example_data_10k$matrix,
                               log=TRUE)
    scae

    ## -----------------------------------------------------------------------------
    metadata(scae)[["knee_info"]]

    # --- Warning=false [] ---
    # Key functions: metadata, scale_x_log10, scale_y_log10, annotation_logticks, geom_hline, knee_info, red, dodgerblue
    knee_df <- metadata(scae)[["knee_info"]]$knee_df
    knee_point <- metadata(scae)[["knee_info"]]$knee_point
    inflection_point <- metadata(scae)[["knee_info"]]$inflection_point

    ggplot(knee_df, aes(x=rank, y=total)) +
           geom_point() +
           geom_line(aes(y=fitted), color="red") +
           scale_x_log10() +
           scale_y_log10() +
           annotation_logticks() +
           labs(x="Barcode rank", y="Total UMI count") +
           geom_hline(yintercept=S4Vectors::metadata(knee_df)$knee,
                      color="dodgerblue", linetype="dashed") +
           geom_hline(yintercept=S4Vectors::metadata(knee_df)$inflection,
                      color="forestgreen", linetype="dashed") +

    # --- Warning=false [] ---
    # Key functions: read_allele_counts, rowData, example_data, custom
    #  #this is the object used in the further workflow
    #  scae <- read_allele_counts(example_data_10k$dir,
    #                             sample_names="example_data",
    #                             filter_mode="custom",
    #                             lookup_file=lookup,
    #                             barcode_file=example_data_10k$barcodes,
    #                             gene_file=example_data_10k$features,
    #                             matrix_file=example_data_10k$matrix,
    #                             filter_threshold=282)
    #  scae

    ## -----------------------------------------------------------------------------
    rowData(scae)

    ## -----------------------------------------------------------------------------

    # --- Eval=false [] ---
    # Key functions: runTSNE, reducedDimNames, PCA_f, TSNE_f
    #  set.seed(18)
    #  scae <- runTSNE(scae, dimred="PCA_f",  name="TSNE_f")

    ## -----------------------------------------------------------------------------
    reducedDimNames(scae)

    # --- Fig3 [] ---
    # Key functions: plotReducedDim, TSNE_g
    tsne <- "TSNE_g"

    tsne_g_a  <- plotReducedDim(scae, dimred=tsne, colour_by="HLA-DRB1") +
                 ggtitle("HLA-DRB1 gene")

    tsne_g_a1 <- plotReducedDim(scae, dimred=tsne, colour_by="DRB1*07:01:01:01") + 
                 ggtitle("Allele DRB1*07:01:01:01")

    tsne_g_a2 <- plotReducedDim(scae, dimred=tsne, colour_by="DRB1*13:01:01:01") + 
                 ggtitle("Allele DRB1*13:01:01:01")

    p2 <- tsne_g_a + tsne_g_a1 + tsne_g_a2
    p2

    ## -----------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singlecellalleleexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singlecellalleleexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singlecellalleleexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGLECELLALLELEEXPERIMENT:", paste0("    singlecellalleleexperiment: ", packageVersion("SingleCellAlleleExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singlecellalleleexperiment_results.csv
    touch ${prefix}_singlecellalleleexperiment_output.rds
    echo "BIOC_SINGLECELLALLELEEXPERIMENT:" > versions.yml
    echo "    singlecellalleleexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGLECELLALLELEEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINGLECELLALLELEEXPERIMENT(ch_input)

    emit:
    results  = BIOC_SINGLECELLALLELEEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGLECELLALLELEEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGLECELLALLELEEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGLECELLALLELEEXPERIMENT.out.versions  // channel: path(versions.yml)
}
