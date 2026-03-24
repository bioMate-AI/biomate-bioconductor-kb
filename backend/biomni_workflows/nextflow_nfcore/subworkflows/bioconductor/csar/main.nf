#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CSAR
// Statistical tools for ChIP-seq data analysis. The package includes the statistical method described 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CSAR/inst/doc/CSAR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CSAR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CSAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-csar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-csar:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-csar:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_csar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_csar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_csar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPseqScore)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: mappedReads2Nhits
    library(CSAR)
    data("CSAR-dataset");
    head(sampleSEP3_test)
    head(controlSEP3_test)
    nhitsS<-mappedReads2Nhits(sampleSEP3_test,file="sampleSEP3_test",chr=c("CHR1v01212004"),chrL=c(10000))
    # --- Runscore [] ---
    # Key functions: ChIPseqScore, sigWin, score2wig, distance2Genes, genesWithPeaks
    test<-ChIPseqScore(control=nhitsC,sample=nhitsS,file="test",times=10000)
    test$filenames
    win<-sigWin(test)
    head(win)
    score2wig(test,file="test.wig",times=10000)
    # --- Runpermutation [] ---
    # Key functions: permutatedWinScores, getPermutatedWinScores, getThreshold, values
    permutatedWinScores(nn=1,sample=sampleSEP3_test,control=controlSEP3_test,fileOutput="test",chr=c("CHR1v01212004"),chrL=c(100000))
    permutatedWinScores(nn=2,sample=sampleSEP3_test,control=controlSEP3_test,fileOutput="test",chr=c("CHR1v01212004"),chrL=c(100000))
    nulldist<-getPermutatedWinScores(file="test",nn=1:2)
    getThreshold(winscores=values(win)$score,permutatedScores=nulldist,FDR=.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_csar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_csar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_csar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CSAR:", paste0("    csar: ", packageVersion("CSAR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_csar_results.csv
    touch ${prefix}_csar_output.rds
    echo "BIOC_CSAR:" > versions.yml
    echo "    csar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CSAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CSAR(ch_input)

    emit:
    results  = BIOC_CSAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CSAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CSAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CSAR.out.versions  // channel: path(versions.yml)
}
