#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cogena
// cogena is a workflow for co-expressed gene-set enrichment analysis. It aims to discovery smaller sca
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cogena/inst/doc/cogena-vignette_html.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cogena")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COGENA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cogena"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cogena:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cogena:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_cogena_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cogena_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cogena_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cogena)
    library(jsonlite)


    # --- Import Data [] ---
    # Key functions: load_all
    # library(cogena)
    devtools::load_all("./")
    data(Psoriasis)
    # objects in the Psoriasis dataset.
    # Note: label of interest should follow the control label as this
    # will affect the direction of gene regulation.
    # For instance use factor (c("Normal", "Cancer", "Normal"),
    # levels=c("Normal", "Cancer")), instead of factor(c("Normal",
    # "Cancer","Normal")) since "Cancer" is the label of interest.
    ls()

    # --- Gene List Annotation [] ---
    # Key functions: c2.cp.kegg.v7.01.symbols.gmt.xz, c5.bp.v7.0.symbols.gmt.xz, extdata, cogena, hierarchical, kmeans, diana, fanny
    # KEGG Pathway gene set
    annoGMT <- "c2.cp.kegg.v7.01.symbols.gmt.xz"
    # GO biological process gene set
    # annoGMT <- "c5.bp.v7.0.symbols.gmt.xz"
    annofile <- system.file("extdata", annoGMT, package="cogena")

    # the number of clusters. It can be a vector.
    # nClust <- 2:20
    nClust <- 10
    # Making factor "Psoriasis" behind factor "ct" means Psoriasis Vs Control
    # Co-expression Analysis
    genecl_result <- coExp(DEexprs, nClust=nClust, clMethods=clMethods, 
                           metric=metric, method=method, ncore=ncore)

    # Enrichment (Pathway) analysis for the co-expressed genes
    clen_res <- clEnrich(genecl_result, annofile=annofile, sampleLabel=sampleLabel)
    summary(clen_res)

    # --- Cogena Result Analysis [] ---
    # Key functions: summary, enrichment, pam
    summary(clen_res)
    # Here we consider the "pam" method and 10 clusters.
    # Always make the number as character, please!
    enrichment.table <- enrichment(clen_res, "pam", "10")

    # --- Heatmap Cluster [] ---
    # Key functions: heatmapCluster, pam, heatmapPEI
    # Always make the number as character, please!
    heatmapCluster(clen_res, "pam", "10", maintitle="Psoriasis")
    # The enrichment score for 10 clusters, together with Down-regulated,
    # Up-regulated and All DE genes. The values shown in Figure 2 is the -log2(FDR).
    #
    # Always make the number as character, please!

    heatmapPEI(clen_res, "pam", "10", printGS=FALSE, maintitle="Pathway analysis for Psoriasis")

    # --- Heatmap Pei B [] ---
    # Key functions: heatmapPEI, pam, circle, clEnrich, clEnrich_one, extdata, cogena
    heatmapPEI(clen_res, "pam", "10", printGS=FALSE, maintitle="Pathway analysis for Psoriasis", geom="circle")
    # A comprehensive way
    # cmapDn100_cogena_result <- clEnrich(genecl_result, 
    # annofile=system.file("extdata", "CmapDn100.gmt.xz", package="cogena"), 
    # sampleLabel=sampleLabel)

    # A quick way
    # Based on the pathway analysis results
    cmapDn100_cogena_result <- clEnrich_one(genecl_result, "pam", "10", 
        annofile=system.file("extdata", "CmapDn100.gmt.xz", package="cogena"), 
        sampleLabel=sampleLabel)

    # --- Drp Figure [] ---
    # Key functions: heatmapPEI, pam, heatmapCmap
    heatmapPEI(cmapDn100_cogena_result, "pam", "10", printGS=FALSE, 
               orderMethod = "7", maintitle="Drug repositioning for Psoriasis")

    # Results based on cluster 5.
    # heatmapPEI(cmapDn100_cogena_result, "pam", "10", printGS=FALSE, 
    #           orderMethod = "5", maintitle="Drug repositioning for Psoriasis")

    # Results based on cluster 9, containing down-regulated genes.
    # heatmapPEI(cmapUp100_cogena_result, "pam", "10", printGS=FALSE, 
    #           orderMethod = "9", maintitle="Drug repositioning for Psoriasis")
    heatmapCmap(cmapDn100_cogena_result, "pam", "10", printGS=FALSE, 
                orderMethod = "7", maintitle="Drug repositioning for Psoriasis")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cogena_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cogena_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cogena_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COGENA:", paste0("    cogena: ", packageVersion("cogena"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cogena_results.csv
    touch ${prefix}_cogena_output.rds
    echo "BIOC_COGENA:" > versions.yml
    echo "    cogena: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COGENA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_COGENA(ch_input)

    emit:
    results  = BIOC_COGENA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COGENA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COGENA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COGENA.out.versions  // channel: path(versions.yml)
}
