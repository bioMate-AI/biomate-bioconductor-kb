#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSEAlm
// Models and methods for fitting linear models to gene expression data, together with tools for comput
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSEAlm/inst/doc/GSEAlm.R
// Upstream  : ALL, GOstats, RColorBrewer, Rgraphviz, annotate
// Downstream: none
//
// Install: BiocManager::install("GSEAlm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEALM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsealm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsealm:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsealm:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsealm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsealm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsealm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSEAlm)
    library(CooksDPerGene)
    library(D)
    library(GSNormalize)
    library(jsonlite)

    # --- Chromosome Mapping and Incidence Matrix ---
    # Key functions: makeChrBandGraph, makeChrBandInciMat
    minBandSize <- 5
    haveMAP <- sapply(mget(featureNames(esetASub), hgu95av2MAP),
                      function(x) !all(is.na(x)))
    workingEset <- esetASub[haveMAP, ]
    entrezUniv <- unlist(mget(featureNames(workingEset), hgu95av2ENTREZID))
    AgraphChr <- makeChrBandGraph("hgu95av2.db", univ = entrezUniv)
    AmatChr <- makeChrBandInciMat(AgraphChr)
    AmatChr3 <- AmatChr[rowSums(AmatChr) >= minBandSize, ]
    egIds <- sapply(featureNames(workingEset),
                    function(x) hgu95av2ENTREZID[[x]])
    idx <- match(egIds, colnames(AmatChr))
    AmatChr3 <- AmatChr3[, idx]
    colnames(AmatChr3) <- featureNames(workingEset)

    # --- Linear Modeling Per Gene ---
    # Key functions: lmPerGene
    workingEset$mol.biol <- relevel(workingEset$mol.biol, ref = "NEG")
    lmPhen <- lmPerGene(workingEset, ~mol.biol)
    lmEsts <- lmPhen$tstat[2, ]
    lmExpand <- lmPerGene(workingEset, ~mol.biol + sex + kinet)
    lmExpandTees <- t(lmExpand$tstat[2:4, ])

    # --- Residual Analysis and Diagnostics ---
    # Key functions: getResidPerGene, resplot
    lmPhenRes <- getResidPerGene(lmPhen)
    resplot(resmat = exprs(lmPhenRes), fac = workingEset$mol,
            cex.main = 0.7, cex.axis = 0.6, horiz = TRUE,
            lims = c(-5, 5), xname = "", col = 5, cex = 0.3)
    lmExpandRes <- getResidPerGene(lmExpand, type = "extStudent")

    # --- Gene Set Normalization ---
    # Key functions: GSNormalize
    lmExpandBandTees <- GSNormalize(lmExpandTees, AmatChr3)
    GSresidExpand <- GSNormalize(exprs(lmExpandRes), AmatChr3)

    # --- Permutation-Based Inference ---
    # Key functions: gsealmPerm
    nperm <- 125
    flagp <- 0.01
    AgraphChr3 <- subGraph(c("ORGANISM:Homo sapiens", rownames(AmatChr3)),
                           AgraphChr)
    ChrLeaves <- leaves(AgraphChr3, "out")
    ChrLeaves <- ChrLeaves[ChrLeaves %in% rownames(AmatChr3)]
    LeafGenes <- which(colSums(AmatChr3[ChrLeaves, ]) > 0)
    pvalsExpand <- gsealmPerm(workingEset[LeafGenes, ],
                              ~mol.biol + sex + kinet,
                              AmatChr3[ChrLeaves, LeafGenes],
                              nperm = nperm, removeShift = TRUE)

    # --- Influence Diagnostics ---
    # Key functions: CooksDPerGene, GSNormalize
    cookie1 <- CooksDPerGene(lmPhen)
    cookie3 <- CooksDPerGene(lmExpand)
    BandCooks1 <- GSNormalize(cookie1, AmatChr3, fun2 = identity)
    BandCooks3 <- GSNormalize(cookie3, AmatChr3, fun2 = identity)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsealm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsealm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsealm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSEALM:", paste0("    gsealm: ", packageVersion("GSEAlm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsealm_results.csv
    touch ${prefix}_gsealm_output.rds
    echo "BIOC_GSEALM:" > versions.yml
    echo "    gsealm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSEALM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSEALM(ch_input)

    emit:
    results  = BIOC_GSEALM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSEALM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSEALM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSEALM.out.versions  // channel: path(versions.yml)
}
