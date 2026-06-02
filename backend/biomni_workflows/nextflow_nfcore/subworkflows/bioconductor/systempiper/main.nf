#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: systemPipeR
// systemPipeR is a multipurpose data analysis workflow environment that unifies R with command-line to
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/systemPipeR/inst/doc/systemPipeR.R
// Upstream  : BiocParallel, biomaRt, magrittr, pheatmap, txdbmaker
// Downstream: none
//
// Install: BiocManager::install("systemPipeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYSTEMPIPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-systempiper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-systempiper:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-systempiper:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_systempiper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_systempiper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_systempiper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFileList)
    library(DESeqDataSetFromMatrix)
    library(GOCluster_Report)
    library(SPRproject)
    library(SYSargsList)
    library(jsonlite)

    # --- show D F [] ---
    # Key functions: showDF
    targetspath <- system.file("extdata", "targets.txt", package = "systemPipeR")
    showDF(read.delim(targetspath, comment.char = "#"))
    # --- read Comp [] ---
    # Key functions: readComp
    readComp(file = targetspath, format = "vector", delim = "-")
    # --- S P Rproject [] ---
    # Key functions: SPRproject
    sal <- SPRproject(projPath = getwd(), overwrite = TRUE)
    # --- SPRproject dir [] ---
    # Key functions: SPRproject
    sal <- SPRproject(data = "data", param = "param", results = "results")
    # --- SPRproject logs [] ---
    # Key functions: SPRproject
    sal <- SPRproject(logs.dir= ".SPRproject", sys.file=".SPRproject/SYSargsList.yml")
    # --- SPRproject env [] ---
    # Key functions: SPRproject
    sal <- SPRproject(envir = new.env())
    # --- firstStep R [] ---
    # Key functions: appendStep, split
    appendStep(sal) <- LineWise(code = {
    mapply(function(x, y) write.csv(x, y),
    split(iris, factor(iris$Species)),
    # --- gzip secondStep [] ---
    # Key functions: appendStep, cmdlist, outfiles
    targetspath <- system.file("extdata/cwl/gunzip", "targets_gunzip.txt", package = "systemPipeR")
    appendStep(sal) <- SYSargsList(step_name = "gzip",
    dir_path = system.file("extdata/cwl", package = "systemPipeR"),
    # --- append Step [] ---
    # Key functions: appendStep
    appendStep(sal) <- SYSargsList(step_name = "gunzip",
    dir_path = system.file("extdata/cwl", package = "systemPipeR"),
    inputvars = c(gzip_file = "_FILE_PATH_", SampleName = "_SampleName_"),
    # --- targetsWF 3 [] ---
    # Key functions: targetsWF
    targetsWF(sal['gunzip'])
    # --- outfiles 2 [] ---
    # Key functions: outfiles
    outfiles(sal['gunzip'])
    # --- get Column [] ---
    # Key functions: getColumn
    getColumn(sal, step = "gunzip", 'outfiles')
    # --- Custom ggplot2 visualization [] ---
    # Key functions: appendStep, ggplot, geom_bar, geom_errorbar
    appendStep(sal) <- LineWise(code = {
    df <- lapply(getColumn(sal, step = "gunzip", 'outfiles'), function(x) read.delim(x, sep = ",")[-1])
    df <- do.call(rbind, df)
    # --- importWF rmd [] ---
    # Key functions: SPRproject, importWF
    sal_rmd <- SPRproject(logs.dir = ".SPRproject_rmd")
    sal_rmd <- importWF(sal_rmd,
    file_path = system.file("extdata", "spr_simple_wf.Rmd", package = "systemPipeR"))
    # --- importWF details [] ---
    # Key functions: stepsWF, dependency, cmdlist, codeLine, targetsWF
    stepsWF(sal_rmd)
    dependency(sal_rmd)
    cmdlist(sal_rmd)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_systempiper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_systempiper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_systempiper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYSTEMPIPER:", paste0("    systempiper: ", packageVersion("systemPipeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_systempiper_results.csv
    touch ${prefix}_systempiper_output.rds
    echo "BIOC_SYSTEMPIPER:" > versions.yml
    echo "    systempiper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYSTEMPIPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYSTEMPIPER(ch_input)

    emit:
    results  = BIOC_SYSTEMPIPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYSTEMPIPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYSTEMPIPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYSTEMPIPER.out.versions  // channel: path(versions.yml)
}
