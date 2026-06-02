#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GIGSEA
// We presented the Genotype-imputed Gene Set Enrichment Analysis (GIGSEA), a novel method that uses GW
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GIGSEA/inst/doc/GIGSEA_tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GIGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GIGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gigsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gigsea:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gigsea:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gigsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gigsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gigsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GIGSEA)
    library(jsonlite)

    # --- Data Alignment and Intersection [] ---
    # Key functions: orderedIntersect
    data(heart.metaXcan, package="GIGSEA")
    data(MSigDB.KEGG.Pathway, package="GIGSEA")
    gene <- heart.metaXcan$gene_name
    fc <- heart.metaXcan$zscore
    weights <- (heart.metaXcan$n_snps_used /
                heart.metaXcan$n_snps_in_model) *
               heart.metaXcan$pred_perf_r2
    expr_data <- data.frame(gene, fc, weights)
    net <- MSigDB.KEGG.Pathway$net
    data_aligned <- orderedIntersect(x=expr_data, by.x=expr_data$gene,
                                     by.y=rownames(net))
    net_aligned <- orderedIntersect(x=net, by.x=rownames(net),
                                    by.y=expr_data$gene)


    # --- Single Gene Set Enrichment Analysis [] ---
    # Key functions: permutationSimpleLm, permutationSimpleLmMatrix
    data(heart.metaXcan, package="GIGSEA")
    data(MSigDB.KEGG.Pathway, package="GIGSEA")
    gene <- heart.metaXcan$gene_name
    fc <- heart.metaXcan$zscore
    weights <- (heart.metaXcan$n_snps_used /
                heart.metaXcan$n_snps_in_model) *
               heart.metaXcan$pred_perf_r2
    expr_data <- data.frame(gene, fc, weights)
    net <- MSigDB.KEGG.Pathway$net
    data_aligned <- orderedIntersect(x=expr_data, by.x=expr_data$gene,
                                     by.y=rownames(net))
    net_aligned <- orderedIntersect(x=net, by.x=rownames(net),
                                    by.y=expr_data$gene)
    sgsea_res_slow <- permutationSimpleLm(fc=data_aligned$fc,
                                          net=net_aligned,
                                          weights=data_aligned$weights,
                                          num=10)
    sgsea_res_fast <- permutationSimpleLmMatrix(fc=data_aligned$fc,
                                                net=net_aligned,
                                                weights=data_aligned$weights,
                                                num=10)


    # --- Multiple Gene Set Enrichment Analysis [] ---
    # Key functions: permutationMultipleLm, permutationMultipleLmMatrix
    data(heart.metaXcan, package="GIGSEA")
    data(MSigDB.KEGG.Pathway, package="GIGSEA")
    gene <- heart.metaXcan$gene_name
    fc <- heart.metaXcan$zscore
    weights <- (heart.metaXcan$n_snps_used /
                heart.metaXcan$n_snps_in_model) *
               heart.metaXcan$pred_perf_r2
    expr_data <- data.frame(gene, fc, weights)
    net <- MSigDB.KEGG.Pathway$net
    data_aligned <- orderedIntersect(x=expr_data, by.x=expr_data$gene,
                                     by.y=rownames(net))
    net_aligned <- orderedIntersect(x=net, by.x=rownames(net),
                                    by.y=expr_data$gene)
    mgsea_res_slow <- permutationMultipleLm(fc=data_aligned$fc,
                                            net=net_aligned,
                                            weights=data_aligned$weights,
                                            num=10)
    mgsea_res_fast <- permutationMultipleLmMatrix(fc=data_aligned$fc,
                                                  net=net_aligned,
                                                  weights=data_aligned$weights,
                                                  num=10)


    # --- One-step Weighted GSEA [] ---
    # Key functions: weightedGSEA
    data(heart.metaXcan, package="GIGSEA")
    gene <- heart.metaXcan$gene_name
    fc <- heart.metaXcan$zscore
    weights <- (heart.metaXcan$n_snps_used /
                heart.metaXcan$n_snps_in_model) *
               heart.metaXcan$pred_perf_r2
    expr_data <- data.frame(gene, fc, weights)
    weightedGSEA(expr_data, geneCol="gene", fcCol="fc",
                 weightCol="weights",
                 geneSet=c("MSigDB.KEGG.Pathway"),
                 permutationNum=10, outputDir="./GIGSEA_output")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gigsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gigsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gigsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GIGSEA:", paste0("    gigsea: ", packageVersion("GIGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gigsea_results.csv
    touch ${prefix}_gigsea_output.rds
    echo "BIOC_GIGSEA:" > versions.yml
    echo "    gigsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GIGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GIGSEA(ch_input)

    emit:
    results  = BIOC_GIGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GIGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GIGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GIGSEA.out.versions  // channel: path(versions.yml)
}
