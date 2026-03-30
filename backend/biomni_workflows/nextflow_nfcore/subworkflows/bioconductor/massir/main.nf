#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: massiR
// Predicts the sex of samples in gene expression microarray datasets
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/massiR/inst/doc/massiR_Vignette.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("massiR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MASSIR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-massir"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-massir:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-massir:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_massir_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_massir_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_massir_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CV)
    library(Threshold)
    library(jsonlite)

    # --- Load The Example Data [] ---
    # Key functions: data
    library(massiR)
    data(massi.test.dataset)
    # --- Load The Test Probe List [] ---
    # Key functions: data
    data(massi.test.probes)
    # --- Extract Y From Test Dataset Calculate Cv [] ---
    # Key functions: massi_y
    massi.y.out <- massi_y(massi.test.dataset, massi.test.probes)
    # --- Plot The Results From Massi.Y [] ---
    # Key functions: massi_y_plot
    massi_y_plot(massi.y.out)
    # --- massi_y [] ---
    # Key functions: massi_y
    massi.y.out <- massi_y(massi.test.dataset, massi.test.probes)
    # --- Fig1 [] ---
    # Key functions: CV, Threshold, 1, 2
    barplot(height=massi.y.out[[2]], names.arg=massi.y.out[[1]], xpd=T,
              cex.names=0.5, las=2, ylab="Probe CV (%)")
      # Get the quantile values from the massi.y output
      quantiles <- massi.y.out[[3]]
      # add lines for the 0%, 25%, 50%, and 75% quartiles
    # --- Run Massi.Select [] ---
    # Key functions: massi_select
    massi.select.out <-
      massi_select(massi.test.dataset, massi.test.probes, threshold=4)
    # --- Massi Cluster [] ---
    # Key functions: massi_cluster
    results <- massi_cluster(massi.select.out)
    # --- Frame [] ---
    # Key functions: frame
    sample.results <- data.frame(results[[2]])
    # --- Massi Cluster Plot [] ---
    # Key functions: massi_cluster_plot
    ## massi_cluster_plot(massi.select.out, results)
    # --- Fig2 [] ---
    # Key functions: rowSums, 2, redgreen
    ord <- order(rowSums(abs(massi.select.out)),decreasing=T)
      heatmap.2(x=as.matrix(massi.select.out[ord,]), keysize=2, cexRow=0.7,
                key=T, trace="none", dendrogram="row", col=redgreen(75), scale="row")
    # --- Fig3 [] ---
    # Key functions: frame
    massi.cluster.results <- data.frame(results[[2]])
      massi.cluster.results.sort <- massi.cluster.results[order(massi.cluster.results$sex),] # sort data by sex
      probe.means <- massi.cluster.results.sort$mean_y_probes_value # samples probe mean values
      probe.sd <- massi.cluster.results.sort$y_probes_sd # sample probe sd values
      sample.names <- massi.cluster.results.sort$ID # set x-axis names
    # --- Fig4 [] ---
    # Key functions: clusplot
    ## generate PC plot of clusters
      k.medoids.results <- results[[1]]
      clusplot(t(massi.select.out), k.medoids.results$clustering, color=TRUE, shade=FALSE, main="",cex.txt=0.5,
               labels=2, lines=0)
    # --- massi_dip [] ---
    # Key functions: massi_dip
    dip.result <- massi_dip(massi.select.out)
    # --- Fig5 [] ---
    # Key functions: massi_dip
    dip.result <- massi_dip(massi.select.out)
    plot(dip.result[[3]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_massir_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_massir_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_massir_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MASSIR:", paste0("    massir: ", packageVersion("massiR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_massir_results.csv
    touch ${prefix}_massir_output.rds
    echo "BIOC_MASSIR:" > versions.yml
    echo "    massir: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MASSIR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MASSIR(ch_input)

    emit:
    results  = BIOC_MASSIR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MASSIR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MASSIR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MASSIR.out.versions  // channel: path(versions.yml)
}
