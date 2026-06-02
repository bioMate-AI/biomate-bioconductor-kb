#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cpvSNP
// Gene set analysis methods exist to combine SNP-level association p-values into gene sets, calculatin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cpvSNP/inst/doc/cpvSNP.R
// Upstream  : ReportingTools
// Downstream: none
//
// Install: BiocManager::install("cpvSNP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CPVSNP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cpvsnp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cpvsnp:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cpvsnp:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cpvsnp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cpvsnp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cpvsnp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cpvSNP)
    library(HTMLReport)
    library(jsonlite)

    # --- Gene to SNP Mapping [] ---
    # Key functions: geneToSNPList
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    genesHg19 <- GenomicFeatures::genes(txdb)
    geneSets <- geneSetAnalysis[["geneSets"]]
    snpsGSC <- geneToSNPList(geneSets, arrayDataGR, genesHg19)


    # --- Gene Set Association Analysis [] ---
    # Key functions: glossi, pValue, degreesOfFreedom, statistic
    indep <- geneSetAnalysis[["indepSNPs"]]
    pvals <- arrayDataGR$P[is.element(arrayDataGR$SNP, indep$V1)]
    names(pvals) <- arrayDataGR$SNP[is.element(arrayDataGR$SNP, indep$V1)]
    gRes <- glossi(pvals, snpsGSC)
    gRes_p <- pValue(gRes)
    gRes_df <- degreesOfFreedom(gRes)
    gRes_stat <- statistic(gRes)


    # --- Visualisation of Association P-values [] ---
    # Key functions: plotPvals, assocPvalBySetPlot
    plotPvals(gRes, main = "GLOSSI P-values")
    all_pvals <- arrayDataGR$P
    names(all_pvals) <- arrayDataGR$SNP
    assocPvalBySetPlot(all_pvals, snpsGSC[[2]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cpvsnp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cpvsnp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cpvsnp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CPVSNP:", paste0("    cpvsnp: ", packageVersion("cpvSNP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cpvsnp_results.csv
    touch ${prefix}_cpvsnp_output.rds
    echo "BIOC_CPVSNP:" > versions.yml
    echo "    cpvsnp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CPVSNP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CPVSNP(ch_input)

    emit:
    results  = BIOC_CPVSNP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CPVSNP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CPVSNP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CPVSNP.out.versions  // channel: path(versions.yml)
}
