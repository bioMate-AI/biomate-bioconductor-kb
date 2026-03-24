#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DExMA
// performing all the steps of gene expression meta-analysis considering the possible existence of miss
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DExMA/inst/doc/DExMA.R
// Upstream  : Biobase, swamp
// Downstream: none
//
// Install: BiocManager::install("DExMA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEXMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dexma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dexma:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dexma:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dexma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dexma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dexma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DExMA)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(DExMA)
    data("DExMAExampleData")
    # --- Createobjectma [] ---
    # Key functions: createObjectMA
    newObjectMA <- createObjectMA(listEX=listMatrixEX,
                                    listPheno = listPhenodatas,
                                    namePheno=phenoGroups,
                                    expGroups=phenoCases,
                                    refGroups = phenoControls)
    # --- Data [] ---
    # Key functions: pData
    data("DExMAExampleData")
    ExpressionSetStudy5
    library(Biobase)
    pData(ExpressionSetStudy5)
    # --- Elementobjectma [] ---
    # Key functions: elementObjectMA
    newElem <-elementObjectMA(expressionMatrix = ExpressionSetStudy5,
                                groupPheno = "condition",
                                expGroup = c("Diseased", "ill"),
                                refGroup = c("Healthy", "control"))
    head(newElem[[1]])
    # --- Allsameid [] ---
    # Key functions: allSameID
    newObjectMA <- allSameID(newObjectMA, finalID="GeneSymbol", organism = "Homo sapiens")
    rownames(newObjectMA$Study1$mExpres)[1:20]
    rownames(newObjectMA$Study2$mExpres)[1:20]
    rownames(newObjectMA$Study3$mExpres)[1:20]
    rownames(newObjectMA$Study4$mExpres)[1:20]
    # --- Datalog [] ---
    # Key functions: dataLog
    newObjectMA <- dataLog(newObjectMA)
    head(newObjectMA[[1]][[1]])
    # --- Heterogeneitytest [] ---
    # Key functions: heterogeneityTest
    heterogeneityTest(newObjectMA)
    # --- Nrow [] ---
    # Key functions: missGenesImput
    nrow(newObjectMA$Study1[[1]])
    nrow(newObjectMA$Study2[[1]])
    imputation <- missGenesImput(maObject, k =7)
    maObject_imput <- imputation$objectMA
    # --- Metaanalysisde [] ---
    # Key functions: metaAnalysisDE
    resultsMA <- metaAnalysisDE(newObjectMA, typeMethod="REM",
                                missAllow=0.3, proportionData=0.50)
    # --- Makeheatmap [] ---
    # Key functions: makeHeatmap
    makeHeatmap(objectMA=newObjectMA, resMA=resultsMA, scaling = "zscor",
                regulation = "all", numSig=40,
                fdrSig = 0.05, logFCSig = 1.5, show_rownames = TRUE)
    # --- Apply [] ---
    # Key functions: frame, prince
    library(swamp)
    pheno <- listPhenodatas$Study2
    pheno <- pheno[,apply(pheno,2,function(x) length(table(x)))>1]
    # Character variables must be converted in numeric
    pheno <- data.frame(apply(pheno, 2, factor), stringsAsFactors = TRUE)
    # --- Batchremove [] ---
    # Key functions: batchRemove
    listMatrixEX$Study2 <- batchRemove(listMatrixEX$Study2, listPhenodatas$Study2,
                                        formula=~gender+race,
                                        mainCov = "race", nameGroup="condition")
    head(listMatrixEX$Study2)
    # --- Calculatees [] ---
    # Key functions: calculateES
    effects <- calculateES(newObjectMA)
    head(effects$ES)
    head(effects$Var)
    head(effects$logFC)
    # --- Pvalueindanalysis [] ---
    # Key functions: pvalueIndAnalysis
    pvalues <- pvalueIndAnalysis(newObjectMA)
    head(pvalues$p)
    head(pvalues$logFC)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dexma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dexma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dexma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEXMA:", paste0("    dexma: ", packageVersion("DExMA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dexma_results.csv
    touch ${prefix}_dexma_output.rds
    echo "BIOC_DEXMA:" > versions.yml
    echo "    dexma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEXMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEXMA(ch_input)

    emit:
    results  = BIOC_DEXMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEXMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEXMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEXMA.out.versions  // channel: path(versions.yml)
}
