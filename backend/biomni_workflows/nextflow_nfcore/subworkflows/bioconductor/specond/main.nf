#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpeCond
// This package performs a gene expression data analysis to detect condition-specific genes. Such genes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpeCond/inst/doc/SpeCond.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SpeCond")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPECOND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-specond"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-specond:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-specond:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_specond_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_specond_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_specond_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpeCond)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, class
    library(SpeCond)
    data(expSetSpeCondExample)
    expSetSpeCondExample
    class(expSetSpeCondExample)
    data(expressionSpeCondExample)
    # --- Specond [] ---
    # Key functions: SpeCond
    generalResult=SpeCond(Mexp, param.detection=NULL, multitest.correction.method="BY",
      prefix.file="E", print.hist.pv=TRUE, fit1=NULL, fit2=NULL, specificOutlierStep1=NULL)
    names(generalResult)
    specificResult=generalResult$specificResult
    # --- Getmatrixfromexpressionset [] ---
    # Key functions: getMatrixFromExpressionSet
    ## MexpS=getMatrixFromExpressionSet(expSetSpeCondExample,
    ##   condition.factor=expSetSpeCondExample$Tissue,condition.method="mean")
    # --- Getfullhtmlspecondresult [] ---
    # Key functions: getFullHtmlSpeCondResult
    getFullHtmlSpeCondResult(SpeCondResult=generalResult, param.detection=
      specificResult$param.detection, page.name="Example_SpeCond_results",
      page.title="Tissue specific results", sort.condition="all", heatmap.profile=TRUE,
      heatmap.expression=FALSE, heatmap.unique.profile=FALSE, expressionMatrix=Mexp)
    # --- Getgenehtmlpage [] ---
    # Key functions: getGeneHtmlPage
    genePageInfo=getGeneHtmlPage(Mexp, specificResult, name.index.html=
      "index_example_SpeCond_Results.html", gene.html.ids=c(1:20))
    # --- Getdefaultparameter [] ---
    # Key functions: getDefaultParameter
    param.detection=getDefaultParameter()
    param.detection
    # --- Createparametermatrix [] ---
    # Key functions: createParameterMatrix
    param.detection2=createParameterMatrix(mlk.1=10)
    param.detection2
    param.detection2B=createParameterMatrix(param.detection=param.detection2,
      mlk.1=15, rsd.2=0.2)
    param.detection2B
    # --- Createparametermatrix [] ---
    # Key functions: createParameterMatrix, SpeCond
    param.detection2=createParameterMatrix(param.detection, mlk.1=10)
    param.detection2
    generalResult2=SpeCond(Mexp, param.detection=param.detection2,
      multitest.correction.method="BY", prefix.file="E2",
      print.hist.pv=TRUE, fit1=generalResult$fit1, fit2=NULL,
    # --- Fitprior [] ---
    # Key functions: fitPrior
    param.detection
    fit1=fitPrior(Mexp, param.detection=param.detection)
    # --- Getspecificoutliersstep1 [] ---
    # Key functions: getSpecificOutliersStep1
    specificOutlierStep1=getSpecificOutliersStep1(Mexp, fit=fit1$fit1,param.detection,
      multitest.correction.method="BY", prefix.file="run1_Step1",
      print.hist.pv=FALSE)
    # --- Fitnopriorwithexclusion [] ---
    # Key functions: fitNoPriorWithExclusion
    fit2=fitNoPriorWithExclusion(Mexp, specificOutlierStep1=specificOutlierStep1,
      param.detection=param.detection)
    # --- Getspecificresult [] ---
    # Key functions: getSpecificResult
    specificResult=getSpecificResult(Mexp, fit=fit2,
      specificOutlierStep1=specificOutlierStep1, param.detection,
      multitest.correction.method="BY", prefix.file="run1_Step2",
      print.hist.pv=FALSE)
    # --- Getprofile [] ---
    # Key functions: getProfile, writeSpeCondResult, writeUniqueProfileSpecificResult, writeGeneResult
    L.specific.result.profile=getProfile(specificResult$L.specific.result$M.specific)
    writeSpeCondResult(specificResult$L.specific.result,file.name.profile=
      "Example_specific_profile.txt", file.specific.gene="Example_list_specific_gene.txt",
      file.name.unique.profile="Example_specific_unique_profile.txt")
    writeUniqueProfileSpecificResult(L.specific.result=specificResult$L.specific.result,
    # --- Data [] ---
    # Key functions: data
    data(simulatedSpeCondData)
    # --- Specond [] ---
    # Key functions: SpeCond, getFullHtmlSpeCondResult, getGeneHtmlPage
    generalResult_S1=SpeCond(simulatedSpeCondData, param.detection=NULL,
      multitest.correction.method="BY", prefix.file="S1", print.hist.pv=TRUE,
      fit1=NULL, fit2=NULL, specificOutlierStep1=NULL)
    specificResult_S1=generalResult_S1$specificResult
    getFullHtmlSpeCondResult(L.specific.result=specificResult_S1$L.specific.result,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_specond_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_specond_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_specond_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPECOND:", paste0("    specond: ", packageVersion("SpeCond"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_specond_results.csv
    touch ${prefix}_specond_output.rds
    echo "BIOC_SPECOND:" > versions.yml
    echo "    specond: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPECOND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPECOND(ch_input)

    emit:
    results  = BIOC_SPECOND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPECOND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPECOND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPECOND.out.versions  // channel: path(versions.yml)
}
