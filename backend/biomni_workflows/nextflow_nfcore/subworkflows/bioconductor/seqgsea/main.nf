#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SeqGSEA
// The package generally provides methods for gene set enrichment analysis of high-throughput RNA-Seq d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SeqGSEA/inst/doc/SeqGSEA.R
// Upstream  : doParallel
// Downstream: none
//
// Install: BiocManager::install("SeqGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqgsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqgsea:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqgsea:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqgsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqgsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqgsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DENBStat4GSEA)
    library(DENBStatPermut4GSEA)
    library(DENBTest)
    library(DEpermutePval)
    library(DSpermute4GSEA)
    library(DSpermutePval)
    library(DSresultGeneTable)
    library(GSEAresultTable)
    library(GSEnrichAnalyze)
    library(jsonlite)

    # --- Readcountset [] ---
    # Key functions: rnbinom, runif
    rcounts <- cbind(t(sapply(1:10, function(x) {rnbinom(5, size=10, prob=runif(1))} )),
                     t(sapply(1:10, function(x) {rnbinom(5, size=10, prob=runif(1))} )))
    colnames(rcounts) <- c(paste("S", 1:5, sep=""), paste("C", 1:5, sep=""))
    geneIDs <- c(rep("G1", 4), rep("G2", 6))
    exonIDs <- c(paste("E", 1:4, sep=""), paste("E", 1:6, sep=""))
    # --- Rcs Example [] ---
    # Key functions: data
    data(RCS_example, package="SeqGSEA")
    RCS_example
    # --- Geneid [] ---
    # Key functions: geneID
    length(unique(geneID(RCS_example)))
    # --- Exontestability [] ---
    # Key functions: exonTestability
    RCS_example <- exonTestability(RCS_example, cutoff = 5)
    # --- Dsanalysis [] ---
    # Key functions: estiExonNBstat, estiGeneNBstat, fData
    RCS_example <- estiExonNBstat(RCS_example)
    RCS_example <- estiGeneNBstat(RCS_example)
    head(fData(RCS_example)[, c("exonIDs", "geneIDs", "testable", "NBstat")])
    # --- Dsperm [] ---
    # Key functions: genpermuteMat, DSpermute4GSEA
    permuteMat <- genpermuteMat(RCS_example, times=20)
    RCS_example <- DSpermute4GSEA(RCS_example, permuteMat)
    head(RCS_example@permute_NBstat_gene)
    # --- Dsscores [] ---
    # Key functions: normFactor, scoreNormalization
    DSscore.normFac <- normFactor(RCS_example@permute_NBstat_gene)
    DSscore <- scoreNormalization(RCS_example@featureData_gene$NBstat,
                                  DSscore.normFac)
    DSscore.perm <- scoreNormalization(RCS_example@permute_NBstat_gene,
                                       DSscore.normFac)
    # --- Dspval [] ---
    # Key functions: DSpermutePval, DSresultGeneTable
    RCS_example <- DSpermutePval(RCS_example, permuteMat)
    head(DSresultGeneTable(RCS_example))
    # --- Genecount [] ---
    # Key functions: getGeneCount
    geneCounts <- getGeneCount(RCS_example)
    dim(geneCounts) # 182  20
    head(geneCounts)
    # --- Deseq [] ---
    # Key functions: label, runDESeq
    label <- label(RCS_example)
    dds <- runDESeq(geneCounts, label)
    # --- Dsnb [] ---
    # Key functions: DENBStat4GSEA
    DEGres <- DENBStat4GSEA(dds)
    DEGres[1:5, "NBstat"]
    # --- Dsnbpermut [] ---
    # Key functions: DENBStatPermut4GSEA
    DEpermNBstat <- DENBStatPermut4GSEA(dds, permuteMat)
    DEpermNBstat[1:5, 1:10]
    # --- Descores [] ---
    # Key functions: normFactor, scoreNormalization
    DEscore.normFac <- normFactor(DEpermNBstat)
    DEscore <- scoreNormalization(DEGres$NBstat, DEscore.normFac)
    DEscore.perm <- scoreNormalization(DEpermNBstat, DEscore.normFac)
    DEscore[1:5]
    DEscore.perm[1:5, 1:10]
    # --- Depval [] ---
    # Key functions: DEpermutePval
    DEGres <- DEpermutePval(DEGres, DEpermNBstat)
    DEGres[1:6, c("NBstat", "perm.pval", "perm.padj")]
    # --- Depval2 [] ---
    # Key functions: DENBTest, DEpermutePval
    DEGres <- DENBTest(dds)
    DEGres <- DEpermutePval(DEGres, DEpermNBstat)
    DEGres[1:6, c("NBstat", "pval", "padj", "perm.pval", "perm.padj")]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqgsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqgsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqgsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQGSEA:", paste0("    seqgsea: ", packageVersion("SeqGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqgsea_results.csv
    touch ${prefix}_seqgsea_output.rds
    echo "BIOC_SEQGSEA:" > versions.yml
    echo "    seqgsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQGSEA(ch_input)

    emit:
    results  = BIOC_SEQGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQGSEA.out.versions  // channel: path(versions.yml)
}
