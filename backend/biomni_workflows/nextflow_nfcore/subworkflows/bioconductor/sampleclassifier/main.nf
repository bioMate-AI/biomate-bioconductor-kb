#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sampleClassifier
// The package is designed to classify microarray RNA-seq gene expression profiles.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sampleClassifier/inst/doc/sampleClassifier.R
// Upstream  : sampleClassifierData
// Downstream: none
//
// Install: BiocManager::install("sampleClassifier")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SAMPLECLASSIFIER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sampleclassifier"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sampleclassifier:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sampleclassifier:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sampleclassifier_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sampleclassifier_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sampleclassifier_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sampleClassifier)
    library(jsonlite)

    # --- Load Rnaseqdata [] ---
    # Key functions: assay
    library(sampleClassifierData)
    data("se_rnaseq_refmat")
    rnaseq_refmat <- assay(se_rnaseq_refmat)
    # --- Load Microdata 1 [] ---
    # Key functions: assay
    library(sampleClassifierData)
    data("se_micro_refmat")
    micro_refmat <- assay(se_micro_refmat)
    dim(micro_refmat)
    # --- Load Microdata 2 [] ---
    # Key functions: assay
    data("se_micro_testmat")
    micro_testmat <- assay(se_micro_testmat)
    dim(micro_testmat)
    # --- Classify Microdata [] ---
    # Key functions: classifyProfile
    res1.list <- classifyProfile(ref_matrix=micro_refmat, query_mat=micro_testmat,
    chip1="hgu133plus2",chip2="hgu133a", write2File=FALSE)
    # --- Heatmap [] ---
    # Key functions: heatmap
    get.heatmap(res1.list)
    # --- Classify Microdata Svm [] ---
    # Key functions: svm
    res1.svm.df <- classifyProfile.svm(ref_matrix=micro_refmat, query_mat=micro_testmat,
    chip1="hgu133plus2",chip2="hgu133a")
    res1.svm.df
    # --- Classify Rnaseq [] ---
    # Key functions: assay
    library(sampleClassifierData)
    data("se_rnaseq_refmat")
    rnaseq_refmat <- assay(se_rnaseq_refmat)
    dim(rnaseq_refmat)
    # --- Load Testrnaseq [] ---
    # Key functions: assay
    data("se_rnaseq_testmat")
    rnaseq_testmat <- assay(se_rnaseq_testmat)
    dim(rnaseq_testmat)
    # --- Classify Rnaseq2 [] ---
    # Key functions: rnaseq
    res2.list <- classifyProfile.rnaseq(ref_matrix=rnaseq_refmat, query_mat=rnaseq_testmat,
    gene.ids.type="ensembl",write2File=FALSE)
    # --- Heatmap2 [] ---
    # Key functions: heatmap
    get.heatmap(res2.list)
    # --- Show Results3 [] ---
    # Key functions: svm
    res2.svm.df <- classifyProfile.rnaseq.svm(ref_matrix=rnaseq_refmat, query_mat=rnaseq_testmat,
    gene.ids.type="ensembl")
    res2.svm.df
    # --- Show Results4 [] ---
    # Key functions: unlist
    misclas.inds <- which(as.character(res2.svm.df[,1])!=as.character(res2.svm.df[,2]))
    colnames(res2.svm.df) <- c("query_real_class","predicted_class_by_SVM")
    pred.classifyProfile.rnaseq <- as.character(unlist(lapply(res2.list[which(names(res2.list) %in%
    as.character(res2.svm.df[misclas.inds,1]))],"[",1,1,drop=TRUE)))
    comp.df <- cbind(res2.svm.df[misclas.inds,],

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sampleclassifier_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sampleclassifier_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sampleclassifier_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SAMPLECLASSIFIER:", paste0("    sampleclassifier: ", packageVersion("sampleClassifier"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sampleclassifier_results.csv
    touch ${prefix}_sampleclassifier_output.rds
    echo "BIOC_SAMPLECLASSIFIER:" > versions.yml
    echo "    sampleclassifier: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SAMPLECLASSIFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SAMPLECLASSIFIER(ch_input)

    emit:
    results  = BIOC_SAMPLECLASSIFIER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SAMPLECLASSIFIER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SAMPLECLASSIFIER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SAMPLECLASSIFIER.out.versions  // channel: path(versions.yml)
}
