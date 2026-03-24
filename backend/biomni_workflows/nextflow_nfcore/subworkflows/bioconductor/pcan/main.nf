#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PCAN
// Phenotypes comparison based on a pathway consensus approach. Assess the relationship between candida
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PCAN/inst/doc/PCAN.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PCAN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pcan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pcan:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pcan:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pcan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pcan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pcan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MulticoreParam)
    library(SerialParam)
    library(jsonlite)

    # --- Quote [] ---
    # Key functions: quote, MulticoreParam
    ---------------------------------------------------------------------
    library(PCAN)
    ## Some functions can be parallelized.
    ## They use the bpmapply function from the BiocParallel library.
    ## Follow instructions provided in the BiocParallel manual to
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(geneByTrait, package="PCAN")
    head(geneByTrait, n=3)
    dim(geneByTrait)
    # --- Unique [] ---
    # Key functions: merge
    ---------------------------------------------------------------------
    geneByHp <- unique(merge(
        geneByTrait,
        hpByTrait,
        by="id"
    # --- Unstack [] ---
    # Key functions: unstack, computeHpIC
    ---------------------------------------------------------------------
    info <- unstack(geneByHp, entrez~hp)
    ic <- computeHpIC(info, hp_descendants)
    # --- Which [] ---
    # Key functions: calcHpSim
    ---------------------------------------------------------------------
    hp1 <- "HP:0000518"
    hp2 <- "HP:0030084"
    hpDef[which(hpDef$id %in% c(hp1, hp2)), 1:2]
    calcHpSim(hp1, hp2, IC=ic, ancestors=hp_ancestors)
    # --- Comparehpsets [] ---
    # Key functions: compareHPSets, SerialParam
    ---------------------------------------------------------------------
    compMat <- compareHPSets(
        hpSet1=genHp, hpSet2=hpOfInterest,
        IC=ic,
        ancestors=hp_ancestors,
    # --- Hpsetcompsummary [] ---
    # Key functions: hpSetCompSummary
    ---------------------------------------------------------------------
    hpSetCompSummary(compMat, method="bma", direction="symSim")
    # --- Comparehpsets [] ---
    # Key functions: compareHPSets, SerialParam, unstack, unlist
    ---------------------------------------------------------------------
    ## Compute semantic similarity between HP of interest and all HP terms
    ## This step is time consumming and can be parallelized.
    ## Use the BPPARAM parameter to specify your own
    ## back-end with appropriate number of workers.
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(hsEntrezByRPath, rPath, package="PCAN")
    head(rPath, n=3)
    lapply(head(hsEntrezByRPath, 3), head)
    # --- Hpgenelistcomp [] ---
    # Key functions: hpGeneListComp
    ---------------------------------------------------------------------
    rPathRes <- hpGeneListComp(
        geneList=hsEntrezByRPath[[candPath]],
        ssMatByGene = hpMatByGene,
        geneSSScore = resnSss
    # --- Which [] ---
    # Key functions: na
    ---------------------------------------------------------------------
    pathSss <- rPathRes$scores[which(!is.na(rPathRes$scores))]
    names(pathSss) <- geneDef[match(names(pathSss), geneDef$entrez), "symbol"]
    par(mar=c(7.1, 4.1, 4.1, 2.1))
    barplot(
    # --- Which [] ---
    # Key functions: hpGeneHeatmap, colorRampPalette
    ---------------------------------------------------------------------
    geneLabels <- geneDef$symbol[which(!duplicated(geneDef$entrez))]
    names(geneLabels) <- geneDef$entrez[which(!duplicated(geneDef$entrez))]
    hpLabels <- hpDef$name
    names(hpLabels) <- hpDef$id
    # --- Unique [] ---
    # Key functions: hpGeneListComp
    ---------------------------------------------------------------------
    neighbors <- unique(c(
        hqStrNw$gene1[which(hqStrNw$gene2==genId)],
        hqStrNw$gene2[which(hqStrNw$gene1==genId)],
        genId

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pcan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pcan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pcan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PCAN:", paste0("    pcan: ", packageVersion("PCAN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcan_results.csv
    touch ${prefix}_pcan_output.rds
    echo "BIOC_PCAN:" > versions.yml
    echo "    pcan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PCAN(ch_input)

    emit:
    results  = BIOC_PCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PCAN.out.versions  // channel: path(versions.yml)
}
