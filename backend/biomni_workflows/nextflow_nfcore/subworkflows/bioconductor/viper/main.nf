#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: viper
// Inference of protein activity from gene expression data, including the VIPER and msVIPER algorithms
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/viper/inst/doc/viper.R
// Upstream  : none
// Downstream: vulcan, aracne.networks
//
// Install: BiocManager::install("viper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VIPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-viper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-viper:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-viper:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_viper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_viper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_viper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(viper)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: aracne2regulon
    data(bcellViper, package="bcellViper")
    adjfile <- system.file("aracne", "bcellaracne.adj", package = "bcellViper")
    regul <- aracne2regulon(adjfile, dset, verbose = FALSE)
    # --- Rowttest [] ---
    # Key functions: rowTtest
    signature <- rowTtest(dset, "description", c("CB", "CC"), "N")
    # --- Qnorm [] ---
    # Key functions: qnorm
    signature <- (qnorm(signature$p.value/2, lower.tail = FALSE) *
                    sign(signature$statistic))[, 1]
    # --- Ttestnull [] ---
    # Key functions: ttestNull
    nullmodel <- ttestNull(dset, "description", c("CB", "CC"), "N", per = 1000,
                           repos = TRUE, verbose = FALSE)
    # --- Msviper [] ---
    # Key functions: msviper
    mrs <- msviper(signature, regulon, nullmodel, verbose = FALSE)
    # --- Ledge [] ---
    # Key functions: ledge
    mrs <- ledge(mrs)
    summary(mrs)
    # --- Bootstrapttest [] ---
    # Key functions: bootstrapTtest, msviper
    signature <- bootstrapTtest(dset, "description", c("CB", "CC"), "N", verbose = FALSE)
    mrs <- msviper(signature, regulon, nullmodel, verbose = FALSE)
    # --- Bootstrapmsviper [] ---
    # Key functions: bootstrapmsviper
    mrs <- bootstrapmsviper(mrs, "mode")
    # --- Shadow [] ---
    # Key functions: shadow
    mrshadow <- shadow(mrs, regulators = 25, verbose = FALSE)
    # --- Msvipercombinatorial [] ---
    # Key functions: msviperCombinatorial
    mrs <- msviperCombinatorial(mrs, regulators = 25, verbose = FALSE)
    # --- Msvipersynergy [] ---
    # Key functions: msviperSynergy
    mrs <- msviperSynergy(mrs, verbose = FALSE)
    # --- Viper [] ---
    # Key functions: viper
    vpres <- viper(dset, regulon, verbose = FALSE)
    # --- Rowttest [] ---
    # Key functions: rowTtest, frame, signif
    tmp <- rowTtest(vpres, "description", c("CB", "CC"), "N")
    data.frame(Gene = rownames(tmp$p.value), t = round(tmp$statistic, 2),
    "p-value" = signif(tmp$p.value, 3))[order(tmp$p.value)[1:10], ]
    # --- Vipersignature [] ---
    # Key functions: viperSignature, viper
    vpsig <- viperSignature(dset, "description", "N", verbose = FALSE)
    vpres <- viper(vpsig, regulon, verbose = FALSE)
    # --- Euviper [] ---
    # Key functions: pData, exprs, dist, heatmap
    pos <- pData(vpres)[["description"]] %in% c("M", "CB", "CC")
    d1 <- exprs(vpres)[, pos]
    colnames(d1) <- pData(vpres)[["description"]][pos]
    dd <- dist(t(d1), method = "euclidean")
    heatmap(as.matrix(dd), Rowv = as.dendrogram(hclust(dd, method = "average")), symm = T)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_viper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_viper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_viper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VIPER:", paste0("    viper: ", packageVersion("viper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_viper_results.csv
    touch ${prefix}_viper_output.rds
    echo "BIOC_VIPER:" > versions.yml
    echo "    viper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VIPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VIPER(ch_input)

    emit:
    results  = BIOC_VIPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VIPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VIPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VIPER.out.versions  // channel: path(versions.yml)
}
