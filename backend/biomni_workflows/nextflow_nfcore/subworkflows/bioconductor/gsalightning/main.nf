#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSALightning
// GSALightning provides a fast implementation of permutation-based gene set analysis for two-sample pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSALightning/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GSALightning")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSALIGHTNING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsalightning"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsalightning:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsalightning:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsalightning_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsalightning_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsalightning_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSALight)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(expression)
    data(sampleInfo)
    # --- Gsalight [] ---
    # Key functions: GSALight, factor
    ---------------------------------------------------------------------
    GSALightResults <- GSALight(eset = expression, fac = factor(sampleInfo$TN), gs = targetGenes,
    		   		   	       nperm = 1000, minsize = 10, rmGSGenes = 'gene')
    head(GSALightResults)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(expression)
    expression[1:4,1:3]
    # --- Gsalight [] ---
    # Key functions: GSALight, factor
    ---------------------------------------------------------------------
    GSALightResults <- GSALight(eset = expression, fac = factor(sampleInfo$TN), gs = targetGenes,
    		   		   	       nperm = 1000, rmGSGenes = 'gene')
    head(GSALightResults)
    # --- Permtestlight [] ---
    # Key functions: permTestLight, factor
    ---------------------------------------------------------------------
    singleGeneAnalysis <- permTestLight(eset = expression, fac = factor(sampleInfo$TN),
    		   		  	   	             nperm = 1000,  method = 'mean', verbose = TRUE)
    head(singleGeneAnalysis)
    # --- Wilcoxtest [] ---
    # Key functions: wilcoxTest, factor
    ---------------------------------------------------------------------
    singleWilcox <- wilcoxTest(eset = expression, fac = factor(sampleInfo$TN),
    		   		  	   	             tests = "unpaired")
    head(singleWilcox)
    # --- Gsalight [] ---
    # Key functions: GSALight
    ---------------------------------------------------------------------
    GSALightResultsPaired <- GSALight(eset = expression, fac = fac, gs = targetGenes,
    		   		   	       nperm = 1000, tests = 'paired', method = 'maxmean', restandardize = TRUE, minsize = 10,
    					       rmGSGenes = 'gene', verbose = FALSE)
    head(GSALightResultsPaired)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsalightning_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsalightning_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsalightning_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSALIGHTNING:", paste0("    gsalightning: ", packageVersion("GSALightning"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsalightning_results.csv
    touch ${prefix}_gsalightning_output.rds
    echo "BIOC_GSALIGHTNING:" > versions.yml
    echo "    gsalightning: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSALIGHTNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSALIGHTNING(ch_input)

    emit:
    results  = BIOC_GSALIGHTNING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSALIGHTNING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSALIGHTNING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSALIGHTNING.out.versions  // channel: path(versions.yml)
}
