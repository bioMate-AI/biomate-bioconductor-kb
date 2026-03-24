#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSAR
// Gene set analysis using specific alternative hypotheses. Tests for differential expression, scale an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSAR/inst/doc/GSAR.R
// Upstream  : ALL, Biobase, GSEABase, GSVAdata, MASS
// Downstream: none
//
// Install: BiocManager::install("GSAR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsar:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsar:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_gsar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KStest)
    library(TestGeneSets)
    library(WWtest)
    library(jsonlite)

    # --- Aperm [] ---
    # Key functions: aperm, findMST2
    ## The input of findMST2 must be a matrix with rows and columns
    ## respectively corresponding to genes and columns.
    ## Therefore, dataset must be transposed first.
    dataset <- aperm(dataset, c(2,1))
    MST2 <- findMST2(dataset)
    # --- Data [] ---
    # Key functions: data
    library(GSVAdata)
    data(p53DataSet)
    data(c2BroadSets)
    # --- List [] ---
    # Key functions: geneIds, unlist, array
    library(org.Hs.eg.db)
    library(GSEABase)
    C2 <- as.list(geneIds(c2BroadSets))
    len <- length(C2)
    genes.entrez <- unique(unlist(C2))
    # --- pathway [] ---
    # Key functions: pathway
    plotMST2.pathway(object=p53DataSet[c2.pathways[[path.index]],],
    group=c(rep(1,17), rep(2,33)), name="LU_TUMOR_VASCULATURE_UP",
    legend.size=1.2, leg.x=-1.2, leg.y=2,
    label.size=1, label.dist=0.8, cor.method="pearson")
    # --- Testgenesets [] ---
    # Key functions: TestGeneSets
    results <- TestGeneSets(object=p53DataSet, group=group.label,
    geneSets=c2.pathways[1:3], min.size=10, max.size=100, test="GSNCAtest")
    results
    # --- Data [] ---
    # Key functions: intersect, factor
    library(Biobase)
    library(genefilter)
    library(annotate)
    library(hgu95av2.db)
    library(ALL)
    # --- List [] ---
    # Key functions: geneIds, unlist, array, mappedkeys
    C2 <- as.list(geneIds(c2BroadSets))
    len <- length(C2)
    genes.entrez <- unique(unlist(C2))
    genes.symbol <- array("",c(length(genes.entrez),1))
    x <- org.Hs.egSYMBOL
    # --- Kcmlplot [] ---
    # Key functions: pathway
    plotMST2.pathway(object=KCMLpathway, group=group.label,
    name="KEGG_CHRONIC_MYELOID_LEUKEMIA", legend.size=1.2, leg.x=-1,
    leg.y=2, label.size=0.8, cor.method="pearson")
    # --- Data [] ---
    # Key functions: sampleNames
    library(tweeDEseqCountData)
    data(pickrell)
    data(annotEnsembl63)
    data(genderGenes)
    gender <- pickrell.eset$gender
    # --- Which [] ---
    # Key functions: na, exprs, cpm, rowMeans, rpkm
    library(edgeR)
    gene.indices <- which(!(is.na(annotEnsembl63$EntrezID) |
    is.na(annotEnsembl63$Length)))
    PickrellDataSet <- exprs(pickrell.eset)
    PickrellDataSet <- PickrellDataSet[gene.indices,]
    # --- Wwtest [] ---
    # Key functions: WWtest, KStest
    XYpathway <- rpkm.set[XYgenes,]
    group.label.pickrell <- (gender == "male") + 1
    WW_pvalue <- WWtest(XYpathway, group.label.pickrell)
    KS_pvalue <- KStest(XYpathway, group.label.pickrell)
    WW_pvalue

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSAR:", paste0("    gsar: ", packageVersion("GSAR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsar_results.csv
    touch ${prefix}_gsar_output.rds
    echo "BIOC_GSAR:" > versions.yml
    echo "    gsar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_GSAR(ch_input)

    emit:
    results  = BIOC_GSAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSAR.out.versions  // channel: path(versions.yml)
}
