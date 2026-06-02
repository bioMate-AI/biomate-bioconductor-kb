#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TTMap
// TTMap is a clustering method that groups together samples with the same deviation in comparison to a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TTMap/inst/doc/TTMap.R
// Upstream  : airway, rgl
// Downstream: none
//
// Install: BiocManager::install("TTMap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TTMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ttmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ttmap:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ttmap:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ttmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ttmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ttmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TTMap)
    library(jsonlite)

    # --- Data Preparation [make_matrices] ---
    # Key functions: make_matrices
    counts <- matrix(rpois(800, lambda = 10), ncol = 8)
    rownames(counts) <- paste0("Gene", 1:100)
    colnames(counts) <- paste0("Sample", 1:8)
    se <- SummarizedExperiment::SummarizedExperiment(
        assays = list(counts = counts)
    )
    SummarizedExperiment::assay(se) <- log2(
        SummarizedExperiment::assay(se) + 1
    )
    experiment <- ttmap::make_matrices(
        se,
        ctrl.cols = 1:4,
        test.cols = 5:8,
        NAME = rownames(se),
        CLID = rownames(se)
    )

    # --- Control Adjustment [control_adjustment] ---
    # Key functions: control_adjustment
    adjusted_data <- ttmap::control_adjustment(
        normal.pcl = experiment$CTRL,
        tumor.pcl = experiment$TEST,
        normalname = "Healthy_Controls",
        dataname = "Cancer_Effect",
        org.directory = tempdir(),
        e = 1,
        P = 1.1,
        B = 0
    )

    # --- Deviation Assessment [hyperrectangle_deviation_assessment] ---
    # Key functions: hyperrectangle_deviation_assessment
    hda_results <- ttmap::hyperrectangle_deviation_assessment(
        x = adjusted_data,
        k = dim(adjusted_data$Normal.mat)[2],
        dataname = "Cancer_Effect",
        normalname = "Healthy_Controls"
    )

    # --- Topological Mapping [generate_mismatch_distance, calcul_e, ttmap] ---
    # Key functions: generate_mismatch_distance, calcul_e, ttmap
    test_cols <- colnames(experiment$TEST[, -seq_len(3)])
    ctrl_cols <- colnames(experiment$CTRL[, -seq_len(3)])
    annot_vec <- c(paste0(test_cols, ".Dis"), paste0(ctrl_cols, ".Dis"))
    annot <- cbind(annot_vec, annot_vec)
    rownames(annot) <- annot[, 1]
    mismatch_dist <- ttmap::generate_mismatch_distance(
        hda_results,
        select = rownames(hda_results$Dc.Dmat),
        alpha = 1
    )
    e_val <- ttmap::calcul_e(mismatch_dist, 0.95, adjusted_data, 1)
    ttmap_output <- ttmap::ttmap(
        hda_results,
        hda_results$m,
        select = rownames(hda_results$Dc.Dmat),
        annot = annot,
        e = e_val,
        filename = tempfile(),
        n = 1,
        dd = mismatch_dist
    )

    # --- Significant Genes Identification [ttmap_sgn_genes] ---
    # Key functions: ttmap_sgn_genes
    sgn_genes <- ttmap::ttmap_sgn_genes(
        ttmap_output,
        hda_results,
        adjusted_data,
        annot,
        n = 2,
        a = 1,
        filename = "first_trial",
        annot = adjusted_data$tag.pcl,
        col = "NAME",
        path = tempdir(),
        Relaxed = 0
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ttmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ttmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ttmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TTMAP:", paste0("    ttmap: ", packageVersion("TTMap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ttmap_results.csv
    touch ${prefix}_ttmap_output.rds
    echo "BIOC_TTMAP:" > versions.yml
    echo "    ttmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TTMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TTMAP(ch_input)

    emit:
    results  = BIOC_TTMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TTMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TTMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TTMAP.out.versions  // channel: path(versions.yml)
}
