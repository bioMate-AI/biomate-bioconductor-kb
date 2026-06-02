#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RcisTarget
// RcisTarget identifies transcription factor binding motifs (TFBS) over-represented on a gene list. In
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RcisTarget/inst/doc/RcisTarget_MainTutorial.R
// Upstream  : DT, reshape2, visNetwork
// Downstream: none
//
// Install: BiocManager::install("RcisTarget")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCISTARGET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcistarget"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcistarget:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcistarget:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcistarget_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcistarget_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcistarget_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSet)
    library(Stangle)
    library(RcisTarget)
    library(jsonlite)


    # --- Libraries [] ---
    # Key functions: suppressPackageStartupMessages, citation, textVersion
    suppressPackageStartupMessages({
    library(RcisTarget)
    library(RcisTarget.hg19.motifDBs.cisbpOnly.500bp) 
    library(DT)
    library(data.table)
    #require(visNetwork)
    })
    print(citation("RcisTarget")[1], style="textVersion")

    # --- Gene Sets [] ---
    # Key functions: GeneSet, gene1, gene2, gene3, geneSetName, read.table, hypoxiaGeneSet.txt
    library(RcisTarget)
    geneSet1 <- c("gene1", "gene2", "gene3")
    geneLists <- list(geneSetName=geneSet1)
    # or: 
    # geneLists <- GSEABase::GeneSet(geneSet1, setName="geneSetName")
    txtFile <- paste(file.path(system.file('examples', package='RcisTarget')),
                     "hypoxiaGeneSet.txt", sep="/")
    geneLists <- list(hypoxia=read.table(txtFile, stringsAsFactors=FALSE)[,1])
    head(geneLists$hypoxia)

    # --- Load Annot [] ---
    # Key functions: showLogo
    # mouse:
    # data(motifAnnotations_mgi)

    # human:
    data(motifAnnotations_hgnc)
    motifAnnotations[199:202,]
    showLogo(motifAnnotations[(directAnnotation==TRUE) & keptInRanking 
                                   & (TF %in% c("HIF1A", "HIF2A", "EPAS1")), ])

    # --- Load Databases Cisbp Only [] ---
    # Key functions: calcAUC
    library(RcisTarget.hg19.motifDBs.cisbpOnly.500bp)
    # Rankings
    data(hg19_500bpUpstream_motifRanking_cispbOnly)
    motifRankings <- hg19_500bpUpstream_motifRanking_cispbOnly
    motifRankings

    # Annotations
    data(hg19_motifAnnotation_cisbpOnly) 
    motifAnnotations <- hg19_motifAnnotation_cisbpOnly
    motifs_AUC <- calcAUC(geneLists, motifRankings, nCores=1)

    # --- Auchistogram [] ---
    # Key functions: getAUC, abline, hypoxia, darkred, red, addMotifAnnotation, class, TF_lowConf
    auc <- getAUC(motifs_AUC)["hypoxia",]
    hist(auc, main="hypoxia", xlab="AUC histogram",
         breaks=100, col="#ff000050", border="darkred")
    nes3 <- (3*sd(auc)) + mean(auc)
    abline(v=nes3, col="red")
    motifEnrichmentTable <- addMotifAnnotation(motifs_AUC, nesThreshold=3,
         motifAnnot=motifAnnotations,
         highlightTFs=list(hypoxia=c("HIF1A", "EPAS1")))

    ## -----------------------------------------------------------------------------
    class(motifEnrichmentTable)
    dim(motifEnrichmentTable)
    head(motifEnrichmentTable[,-"TF_lowConf", with=FALSE])

    # --- Add Significant Genes [] ---
    # Key functions: addSignificantGenes, sample, par, getSignificantGenes, hypoxia, none, aprox
    motifEnrichmentTable_wGenes <- addSignificantGenes(motifEnrichmentTable,
                          rankings=motifRankings, 
                          geneSets=geneLists)
    dim(motifEnrichmentTable_wGenes)
    geneSetName <- "hypoxia"
    selectedMotifs <- c(sample(motifEnrichmentTable$motif, 2))
    par(mfrow=c(2,2))
    getSignificantGenes(geneLists[[geneSetName]], 
                        rankings=motifRankings,
                        signifRankingNames=selectedMotifs,
                        plotCurve=TRUE, maxRank=5000, genesFormat="none",
                        method="aprox")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcistarget_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcistarget_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcistarget_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCISTARGET:", paste0("    rcistarget: ", packageVersion("RcisTarget"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcistarget_results.csv
    touch ${prefix}_rcistarget_output.rds
    echo "BIOC_RCISTARGET:" > versions.yml
    echo "    rcistarget: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCISTARGET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCISTARGET(ch_input)

    emit:
    results  = BIOC_RCISTARGET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCISTARGET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCISTARGET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCISTARGET.out.versions  // channel: path(versions.yml)
}
