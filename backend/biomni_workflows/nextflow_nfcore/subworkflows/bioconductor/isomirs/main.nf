#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: isomiRs
// Characterization of miRNAs and isomiRs, clustering and differential expression.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/isomiRs/inst/doc/isomiRs.R
// Upstream  : DESeq2, clusterProfiler, pheatmap
// Downstream: none
//
// Install: BiocManager::install("isomiRs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOMIRS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isomirs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isomirs:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isomirs:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isomirs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isomirs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isomirs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IsomirDataSeqFromFiles)
    library(jsonlite)

    # --- Isomir Data Seq From Files [] ---
    # Key functions: IsomirDataSeqFromFiles
    ids <- IsomirDataSeqFromFiles(fn_list, design=de)
    # --- iso Counts [] ---
    # Key functions: isoCounts, isoPlot
    ids <- isoCounts(mirData)
    isoPlot(ids, type="all")
    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap
    library(pheatmap)
    ids = isoNorm(ids, formula = ~ condition)
    pheatmap(counts(ids, norm=TRUE)[1:100,],
    # --- MA plot of DE results [] ---
    # Key functions: isoDE, plotMA
    dds <- isoDE(ids, formula=~condition)
    library(DESeq2)
    plotMA(dds)
    # --- col Data [] ---
    # Key functions: colData
    dds = DESeqDataSetFromMatrix(counts(ids),
    colData(ids), design = ~condition)
    # --- Gene Ontology enrichment analysis [] ---
    # Key functions: enrichGO, isoPlotNet
    library(org.Mm.eg.db)
    library(clusterProfiler)
    data(isoExample)
    # --- find Targets [] ---
    # Key functions: findTargets
    mirna_ma <- data.frame(gene = names(gene_ex_rse)[1:20],
    mir = names(mirna_ex_rse))
    ma_ex <- findTargets(mirna_ex_rse, gene_ex_rse, mirna_ma)
    # --- mirna2targetscan [] ---
    # Key functions: mirna2targetscan
    library(targetscan.Hs.eg.db)
    mirna_ma <- mirna2targetscan(c("hsa-miR-34c-5p"))
    head(mirna_ma)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isomirs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isomirs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isomirs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOMIRS:", paste0("    isomirs: ", packageVersion("isomiRs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isomirs_results.csv
    touch ${prefix}_isomirs_output.rds
    echo "BIOC_ISOMIRS:" > versions.yml
    echo "    isomirs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOMIRS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOMIRS(ch_input)

    emit:
    results  = BIOC_ISOMIRS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOMIRS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOMIRS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOMIRS.out.versions  // channel: path(versions.yml)
}
