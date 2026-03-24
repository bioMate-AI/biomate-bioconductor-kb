#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: phenoTest
// Tools to test correlation between gene expression and phenotype in a way that is efficient, structur
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/phenoTest/inst/doc/phenoTest.R
// Upstream  : GSEABase
// Downstream: none
//
// Install: BiocManager::install("phenoTest")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHENOTEST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phenotest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phenotest:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phenotest:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phenotest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phenotest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phenotest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExpressionPhenoTest)
    library(GeneSet)
    library(GeneSetCollection)
    library(jsonlite)

    # --- Loadlibanddata [] ---
    # Key functions: data
    options(width=100)
    library(phenoTest)
    data(eset)
    eset
    # --- Preprocess [] ---
    # Key functions: rnorm, pData
    Tumor.size <- rnorm(ncol(eset),50,2)
    pData(eset) <- cbind(pData(eset),Tumor.size)
    pData(eset)[1:20,'lymph.node.status'] <- 'positive'
    # --- p Data [] ---
    # Key functions: pData
    head(pData(eset))
    survival <- matrix(c("Relapse","Months2Relapse"),ncol=2,byrow=TRUE)
    colnames(survival) <- c('event','time')
    vars2test <- list(survival=survival,categorical='lymph.node.status',continuous='Tumor.size')
    vars2test
    # --- Runexpressionphenotest [] ---
    # Key functions: ExpressionPhenoTest
    epheno <- ExpressionPhenoTest(eset,vars2test,p.adjust.method='none')
    epheno
    # --- Pvalueadjust [] ---
    # Key functions: method, pAdjust
    p.adjust.method(epheno)
    epheno <- pAdjust(epheno,method='BH')
    p.adjust.method(epheno)
    # --- Ephenosubsetbyname [] ---
    # Key functions: phenoNames
    phenoNames(epheno)
    epheno[,'Tumor.size']
    epheno[,2]
    # --- Ephenosubsetbyclass [] ---
    # Key functions: phenoClass
    phenoClass(epheno)
    epheno[,phenoClass(epheno)=='survival']
    # --- Ephenogetmeans [] ---
    # Key functions: getMeans
    head(getMeans(epheno))
    # --- Ephenogetsummaries [] ---
    # Key functions: getSummaryDif, getFc, getHr
    head(getSummaryDif(epheno))
    head(getFc(epheno))
    head(getHr(epheno))
    # --- Ephenogetsignif [] ---
    # Key functions: getSignif
    head(getSignif(epheno))
    # --- get Vars2test [] ---
    # Key functions: getVars2test
    getVars2test(epheno)
    # --- Getsignatures [] ---
    # Key functions: sample, featureNames
    set.seed(777)
    sign1 <- sample(featureNames(eset))[1:20]
    sign2 <- sample(featureNames(eset))[1:50]
    mySignature <- list(sign1,sign2)
    names(mySignature) <- c('My first signature','Another signature')
    # --- Makegenesets [] ---
    # Key functions: GeneSet, GeneSetCollection
    library(GSEABase)
    myGeneSetA <- GeneSet(geneIds=sign1, setName='My first signature')
    myGeneSetB <- GeneSet(geneIds=sign2, setName='Another signature')
    mySignature <- GeneSetCollection(myGeneSetA,myGeneSetB)
    mySignature
    # --- Barplotsignifsignatures [] ---
    # Key functions: barplotSignifSignatures
    barplotSignifSignatures(epheno[,'lymph.node.status'],mySignature,alpha=0.99)
    # --- Barplotsignatures [] ---
    # Key functions: barplotSignatures
    barplotSignatures(epheno[,'Tumor.size'],mySignature, ylim=c(0,1))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phenotest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phenotest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phenotest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHENOTEST:", paste0("    phenotest: ", packageVersion("phenoTest"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phenotest_results.csv
    touch ${prefix}_phenotest_output.rds
    echo "BIOC_PHENOTEST:" > versions.yml
    echo "    phenotest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHENOTEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHENOTEST(ch_input)

    emit:
    results  = BIOC_PHENOTEST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHENOTEST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHENOTEST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHENOTEST.out.versions  // channel: path(versions.yml)
}
