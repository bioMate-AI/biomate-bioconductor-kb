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
    library(HTMLReport)
    library(jsonlite)

    # --- Loadlibrariesanddata [] ---
    # Key functions: data
    library(cpvSNP)
    data(geneSetAnalysis)
    names(geneSetAnalysis)
    # --- Createarraydata [] ---
    # Key functions: createArrayData
    arrayDataGR <- createArrayData(geneSetAnalysis[["arrayData"]],
        positionName="Position")
    class(arrayDataGR)
    # --- Genesets [] ---
    # Key functions: geneIds, details
    geneSets <- geneSetAnalysis[["geneSets"]]
    geneSets
    length(geneSets)
    head(geneIds(geneSets[[1]]))
    details(geneSets[[1]])
    # --- Genetosnplist [] ---
    # Key functions: genes, geneToSNPList
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    genesHg19 <- genes(txdb)
    snpsGSC <- geneToSNPList(geneSets, arrayDataGR, genesHg19)
    class(snpsGSC)
    # --- Createindepp [] ---
    # Key functions: element
    pvals <- arrayDataGR$P[is.element(arrayDataGR$SNP, indep$V1)]
    names(pvals) <- arrayDataGR$SNP[is.element(arrayDataGR$SNP, indep$V1)]
    head(pvals)
    # --- Glossi [] ---
    # Key functions: glossi, pValue, degreesOfFreedom, statistic
    gRes <- glossi(pvals, snpsGSC)
    gRes
    gRes2 <- glossi(pvals, snpsGSC[[1]])
    gRes2
    pValue(gRes)
    # --- Publishmultiple [] ---
    # Key functions: adjust, unlist, pValue, HTMLReport, publish, statistic, finish
    ## pvals <- p.adjust( unlist( pValue(gRes) ), method= "BH" )
    ## library(ReportingTools)
    ## report <- HTMLReport (shortName = "cpvSNP_glossiResult",
    ##         title = "GLOSSI Results", reportDirectory = "./reports")
    ## publish(geneSets, report, annotation.db = "org.Hs.eg",
    # --- Hapmap [] ---
    # Key functions: plink, element, geneIds, ld
    ## download.file(
    ##     url="http://hapmap.ncbi.nlm.nih.gov/genotypes/hapmap3_r3/plink_format/hapmap3_r3_b36_fwd.consensus.qc.poly.ped.gz",
    ##     destfile="hapmap3_r3_b36_fwd.consensus.qc.poly.ped.gz")
    ## download.file(
    ##     url="http://hapmap.ncbi.nlm.nih.gov/genotypes/hapmap3_r3/plink_format/hapmap3_r3_b36_fwd.consensus.qc.poly.map.gz",
    # --- Vegas [] ---
    # Key functions: vegas, unlist, simulatedStats, pValue, degreesOfFreedom, statistic
    ## ldMat <- geneSetAnalysis[["ldMat"]]
    ## vRes <- vegas(snpsGSC[1], arrayDataGR, ldMat)
    ## vRes
    ## summary(unlist(simulatedStats(vRes)))
    ##
    # --- Plotb [] ---
    # Key functions: plotPvals
    plotPvals(gRes, main="GLOSSI P-values")
    # --- Plot2 [] ---
    # Key functions: assocPvalBySetPlot
    pvals <- arrayDataGR$P
    names(pvals) <- arrayDataGR$SNP
    assocPvalBySetPlot(pvals, snpsGSC[[2]])
    # --- Sessinfo [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

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
