#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OMICsPCA
// OMICsPCA is an analysis pipeline designed to integrate multi OMICs experiments done on various subje
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OMICsPCA/inst/doc/vignettes.R
// Upstream  : MultiAssayExperiment, OMICsPCAdata, cluster, factoextra, ggplot2
// Downstream: none
//
// Install: BiocManager::install("OMICsPCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICSPCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicspca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicspca:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicspca:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicspca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicspca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicspca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OMICsPCA)
    library(jsonlite)

    # --- Descriptor [] ---
    # Key functions: descriptor
    ---------------------------------------------------------------------
    descriptor(name = multi_assay,
    factors = c(
    "H2az",
    "H3k4me1","H3k9ac"),
    # --- Chart Correlation [] ---
    # Key functions: chart_correlation
    ---------------------------------------------------------------------
    chart_correlation(name = multi_assay, Assay = "H2az",
    groups = "WE", choice = "hist", bins = 10,
    groupinfo = groupinfo)
    # --- Analyse Individuals [] ---
    # Key functions: analyse_individuals
    ---------------------------------------------------------------------
    # selecting top 40 TSS groups according to their contribution on
    # PC 1 and PC 2 using the argument "select.ind"
    selected <- analyse_individuals(name = PCAlist,
    Assay = "H3k4me1",
    # --- Example [] ---
    # Key functions: example
    ---------------------------------------------------------------------
    # The TSSs used in this example (each row) are obtained by combining
    # many neighboring TSSs together. The combinations should be uncombined
    # to find the corresponding annotations.
    names  <- gsub(";",",",paste(as.character(selected$data$name),
    # --- Plot Integrated Density [] ---
    # Key functions: plot_integrated_density, functions, densityplot
    ---------------------------------------------------------------------
    densityplot <- plot_integrated_density(name = name, PC = 1,
    groups = c("WE","RE","IntE","NE"), groupinfo = groupinfo)
    # additional graphical functions (e.g. xlim, ylim, theme) may be
    #added with densityplot (see section VIII. Density analysis)
    # --- Plot Integrated Density 3D [] ---
    # Key functions: plot_integrated_density_3D
    ---------------------------------------------------------------------
    plot_integrated_density_3D(name = name, PC1 = 1, PC2 = 2,
    group = c("RE","RE"), gridsize = 100, static = TRUE,
    groupinfo = groupinfo)
    # --- Extract [] ---
    # Key functions: extract
    ---------------------------------------------------------------------
    # extracting data from integrated PCA
    data <- extract(name = name, PC = c(1:4),
    groups = c("WE","RE"), integrated = TRUE, rand = 600,
    groupinfo = groupinfo)
    # --- Extract [] ---
    # Key functions: extract, cluster, plot3d, frame
    ---------------------------------------------------------------------
    data <- extract(name = name, PC = c(1:4),
    groups = c("WE","RE"), integrated = TRUE, rand = 1000,
    groupinfo = groupinfo)
    library(factoextra)
    # --- Daisy [] ---
    # Key functions: daisy, silhouette, windows
    ---------------------------------------------------------------------
    #### Using silhouette index
    # calculating the distance matrix
    library(cluster)
    dist <- daisy(data)
    # --- Cluster Boxplot [] ---
    # Key functions: cluster_boxplot, xlab, ylab, ggtitle, theme, element_text, guides, guide_legend
    ---------------------------------------------------------------------
    bp <- cluster_boxplot(name = multi_assay,
    Assay = "H2az", clusterobject = clustered_data,
    clustercolumn = 5)
    bp <- bp+xlab("Cell lines") + ylab(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicspca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicspca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicspca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSPCA:", paste0("    omicspca: ", packageVersion("OMICsPCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicspca_results.csv
    touch ${prefix}_omicspca_output.rds
    echo "BIOC_OMICSPCA:" > versions.yml
    echo "    omicspca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSPCA(ch_input)

    emit:
    results  = BIOC_OMICSPCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSPCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSPCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSPCA.out.versions  // channel: path(versions.yml)
}
