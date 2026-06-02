#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CAGEfightR
// CAGE is a widely used high throughput assay for measuring transcription start site (TSS) activity. C
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CAGEfightR/inst/doc/Introduction_to_CAGEfightR.R
// Upstream  : BiocParallel, Gviz, InteractionSet
// Downstream: CAGEWorkflow
//
// Install: BiocManager::install("CAGEfightR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAGEFIGHTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cagefightr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cagefightr:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cagefightr:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(cluster_object)

    output:
    tuple val(meta), path("${meta.id}_cagefightr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cagefightr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cagefightr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CAGEfightR)
    library(jsonlite)


    # --- Citation [] ---
    # Key functions: citation, BigWigFileList, exampleDesign, extdata, SeqinfoForUCSCGenome, quantifyCTSSs, mm9, quickTSSs
    citation("CAGEfightR")
    # Load the example data
    data("exampleDesign")
    head(exampleDesign)

    # Locate files on your harddrive
    bw_plus <- system.file("extdata", 
                           exampleDesign$BigWigPlus, 
                           package = "CAGEfightR")
    # --- Quick Links [] ---
    # Key functions: rowRanges, findLinks, enhancer, counts, clusterType, kendall, assay, calcTPM
    # Set TSSs as reference points
    rowRanges(RSE)$clusterType <- factor(rowRanges(RSE)$clusterType,
                                         levels=c("TSS", "enhancer"))

    # Find pairs and calculate kendall correlation between them
    links <- findLinks(RSE, 
                       inputAssay="counts", 
                       maxDist=5000, 
                       directional="clusterType",
                       method="kendall")
    data(exampleCTSSs)
    exampleCTSSs
    head(assay(exampleCTSSs))
    rowRanges(exampleCTSSs)
    exampleCTSSs <- calcTPM(exampleCTSSs, inputAssay="counts", outputAssay="TPM", outputColumn="subsetTags")
    # Library sizes
    colData(exampleCTSSs)

    # TPM values
    head(assay(exampleCTSSs, "TPM"))

    # --- Naive Tc [] ---
    # Key functions: clusterUnidirectionally, clusterBidirectionally, calcBidirectionality, quantifyClusters, rowRanges, counts, subsetBySupport
    simple_TCs <- clusterUnidirectionally(exampleCTSSs, 
                                         pooledCutoff=0, 
                                         mergeDist=20)
    # Use a higher cutoff for clustering
    higher_TCs <- clusterUnidirectionally(exampleCTSSs, 
                                         pooledCutoff=0.1, 
                                         mergeDist=20)

    # Use CTSSs pre-filtered on support. 
    prefiltered_TCs <- clusterUnidirectionally(supportedCTSSs, 
                                         pooledCutoff=0, 
                                         mergeDist=20)
    simple_TCs
    BCs <- clusterBidirectionally(exampleCTSSs, balanceThreshold=0.95)
    BCs
    # Calculate number of bidirectional samples
    BCs <- calcBidirectionality(BCs, samples=exampleCTSSs)

    # Summarize
    table(BCs$bidirectionality)

    # --- Support On Tpm [] ---
    # Key functions: calcTPM, subsetBySupport, totalTags, assignTxID, txID, rowRanges, assignTxType, txType
    # Calculate TPM using pre-calculated total tags:
    exampleUnidirectional <- calcTPM(exampleUnidirectional, 
                                     totalTags = "totalTags")

    # Only TSSs expressed at more than 1 TPM in more than 2 samples
    exampleUnidirectional <- subsetBySupport(exampleUnidirectional,
                                             inputAssay="TPM",
                                             unexpressed=1,
                                             minSamples=2)
    library(TxDb.Mmusculus.UCSC.mm9.knownGene)
    txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene
    txdb
    exampleUnidirectional <- assignTxID(exampleUnidirectional,
                                        txModels=txdb,
                                        outputColumn="txID")
    rowRanges(exampleUnidirectional)[5:6]
    exampleUnidirectional <- assignTxType(exampleUnidirectional,
                                          txModels=txdb,
                                          outputColumn="txType")
    # --- Naive Links [] ---
    # Key functions: findLinks, kendall, rowRanges, colData, combineClusters, calcTPM, enhancer, object1
    library(InteractionSet)
    TC_pairs <- findLinks(exampleUnidirectional, 
                          inputAssay="TPM", 
                          maxDist=10000, 
                          method="kendall")

    TC_pairs
    # Mark the type of cluster
    rowRanges(exampleUnidirectional)$clusterType <- "TSS"
    rowRanges(exampleBidirectional)$clusterType <- "enhancer"

    # Merge the dataset
    colData(exampleBidirectional) <- colData(exampleUnidirectional)
    SE <- combineClusters(object1=exampleUnidirectional, 
                          object2=exampleBidirectional,
                          removeIfOverlapping="object1")

    # --- Row Data [] ---
    # Key functions: rowData, calcComposition, rowRanges, composition, geneID, exampleCTSSs, exampleUnidirectional, exampleBidirectional
    rowData(genelevel)
    # Remove TSSs not belonging to any genes
    intragenicTSSs <- subset(exampleUnidirectional, !is.na(geneID))

    # Calculate composition: 
    # The number of samples expressing TSSs above 10% of the total gene expression.
    intragenicTSSs <- calcComposition(intragenicTSSs,
                                      outputColumn="composition",
                                      unexpressed=0.1,
                                      genes="geneID")

    # Remove TSSs with a composition score less than 3
    intragenicTSSs <- subset(intragenicTSSs, composition > 2)
    library(Gviz)

    data("exampleCTSSs")
    data("exampleUnidirectional")
    data("exampleBidirectional")
    # Calculate pooled CTSSs
    exampleCTSSs <- calcTPM(exampleCTSSs, totalTags="totalTags")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cagefightr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cagefightr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cagefightr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAGEFIGHTR:", paste0("    cagefightr: ", packageVersion("CAGEfightR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cagefightr_results.csv
    touch ${prefix}_cagefightr_output.rds
    echo "BIOC_CAGEFIGHTR:" > versions.yml
    echo "    cagefightr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAGEFIGHTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(cluster_object) ]

    main:
    BIOC_CAGEFIGHTR(ch_input)

    emit:
    results  = BIOC_CAGEFIGHTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAGEFIGHTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAGEFIGHTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAGEFIGHTR.out.versions  // channel: path(versions.yml)
}
