#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ANF
// This package is used for complex patient clustering by integrating multi-omic data through affinity 
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/ANF/inst/doc/ANF.html
// Upstream  : ExperimentHub, MASS, igraph
// Downstream: none
//
// Install: BiocManager::install("ANF")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-anf:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-anf:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ANF)
    library(ARI)
    library(ExperimentHub)
    library(Surv)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: mvrnorm, diag, runif
    library(MASS)
    true.class = rep(c(1,2),each=100)
    feature.mat1 = mvrnorm(100, rep(0, 20), diag(runif(20,0.2,2)))
    feature.mat2 = mvrnorm(100, rep(0.5, 20), diag(runif(20,0.2,2)))
    feature1 = rbind(feature.mat1, feature.mat2)
    # --- Code Block 2 [] ---
    # Key functions: kmeans, compare
    library(igraph)
    set.seed(1)
    km = kmeans(feature1, 2)
    compare(km$cluster, true.class, method='nmi')
    # --- Code Block 3 [] ---
    # Key functions: dist, affinity_matrix, spectral_clustering, compare
    library(ANF)
    d = dist(feature1)
    d = as.matrix(d)
    A1 = affinity_matrix(d, 10)
    labels = spectral_clustering(A1, 2)
    # --- Code Block 4 [] ---
    # Key functions: ExperimentHub, query
    library(ExperimentHub)
    eh <- ExperimentHub()
    myfiles <- query(eh, "HarmonizedTCGAData")
    Wall <- myfiles[[1]]
    project_ids <- myfiles[[2]]
    # --- Code Block 5 [] ---
    # Key functions: spectral_clustering
    affinity.mat <- Wall[["adrenal_gland"]][["log.sel"]][["fpkm"]]
    labels <- spectral_clustering(affinity.mat, k = 2)
    # --- Code Block 6 [] ---
    # Key functions: factor
    true.disease.types <- as.factor(project_ids[rownames(affinity.mat)])
    table(labels, true.disease.types)
    # --- Code Block 8 [] ---
    # Key functions: compare, Surv, survdiff, pchisq
    nmi <- igraph::compare(true.disease.types, labels, method = "nmi")
    adjusted.rand = igraph::compare(true.disease.types, labels, method = "adjusted.rand")
    # we can also calculate p-value using `surv.plot` data
    surv.plot <- surv.plot[rownames(affinity.mat), ]
    f <- survival::Surv(surv.plot$time, !surv.plot$censored)
    # --- Code Block 9 [] ---
    # Key functions: eval_clu
    res <- eval_clu(project_ids, w = affinity.mat, surv = surv.plot)
    # --- Code Block 11 [] ---
    # Key functions: eval_clu
    res <- eval_clu(project_ids, w = Wall$uterus$raw.all$fpkm)
    # --- Code Block 13 [] ---
    # Key functions: ANF, spectral_clustering, ARI, eval_clu
    # fuse three matrices: "fpkm" (gene expression), "mirnas" (miRNA expression) and "methy450" (DNA methylation)
    fused.mat <- ANF(Wall = Wall$uterus$raw.all)
    # Spectral clustering on fused patient affinity matrix
    labels <- spectral_clustering(A = fused.mat, k = 2)
    # Or we can directly evaluate clustering results using function `eval_clu`, which calls `spectral_clustering` and calculate NMI and ARI (and p-value if patient survival data is available. `surv.plot` does not contain information for uterus cancer patients)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_anf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_anf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_anf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANF:", paste0("    anf: ", packageVersion("ANF"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anf_results.csv
    touch ${prefix}_anf_output.rds
    echo "BIOC_ANF:" > versions.yml
    echo "    anf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANF(ch_input)

    emit:
    results  = BIOC_ANF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANF.out.versions  // channel: path(versions.yml)
}
