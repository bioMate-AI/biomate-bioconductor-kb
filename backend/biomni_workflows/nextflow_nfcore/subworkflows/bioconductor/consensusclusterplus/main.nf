#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ConsensusClusterPlus 1.70.0
// Consensus clustering for unsupervised molecular subtype
// discovery in genomic data (Monti et al., 2003).
//
// Source : https://bioconductor.org/packages/ConsensusClusterPlus
// Reference: Monti S et al. (2003) J Classification 20:107-136.
//            DOI: 10.1023/A:1023949509487
// Upstream  : (none — base R only)
// Downstream: survival, survminer (downstream survival analysis)
//
// Install: BiocManager::install("ConsensusClusterPlus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CONSENSUSCLUSTERPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-consensusclusterplus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-consensusclusterplus:1.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-consensusclusterplus:1.70.0--r44_0'}"

    input:
    tuple val(meta), path(expr_matrix_rds)   // RDS file: numeric matrix (genes x samples)
    val max_k                                  // maximum number of clusters to test (default: 8)
    val n_reps                                 // bootstrap resampling iterations   (default: 500)

    output:
    tuple val(meta), path("${meta.id}_cluster_assignments.csv"), emit: assignments
    tuple val(meta), path("${meta.id}_icl_scores.csv")         , emit: icl_scores
    tuple val(meta), path("${meta.id}_consensus_plots.pdf")    , emit: plots, optional: true
    tuple val(meta), path("${meta.id}_optimal_k.txt")          , emit: optimal_k
    path "versions.yml"                                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def maxK   = max_k  ?: 8
    def reps   = n_reps ?: 500
    """
    #!/usr/bin/env Rscript
    library(ConsensusClusterPlus)

    # Load expression matrix
    d <- readRDS("${expr_matrix_rds}")
    if (!is.matrix(d)) d <- as.matrix(d)

    # Median-center genes (rows) — standard pre-processing step
    d <- sweep(d, 1, apply(d, 1, median, na.rm = TRUE))

    # Run consensus clustering
    result <- ConsensusClusterPlus(
        d,
        maxK       = ${maxK},
        reps       = ${reps},
        pItem      = 0.8,
        pFeature   = 1,
        clusterAlg = "km",
        distance   = "pearson",
        seed       = 42,
        plot       = "pdf",
        title      = "${prefix}_consensus_plots"
    )

    # Calculate ICL (item and cluster consensus)
    icl <- calcICL(result)

    # Select optimal k by minimum PAC score (proportion of ambiguous clusterings)
    # PAC = fraction of consensus values in (0.1, 0.9) — lower is better
    pac_scores <- sapply(2:${maxK}, function(k) {
        cc  <- result[[k]][["consensusMatrix"]]
        pac <- cc[upper.tri(cc)]
        mean(pac > 0.1 & pac < 0.9)
    })
    best_k <- which.min(pac_scores) + 1
    writeLines(as.character(best_k), "${prefix}_optimal_k.txt")

    # Extract cluster assignments for optimal k
    assignments <- data.frame(
        sample  = names(result[[best_k]][["consensusClass"]]),
        cluster = result[[best_k]][["consensusClass"]],
        stringsAsFactors = FALSE
    )
    write.csv(assignments, "${prefix}_cluster_assignments.csv", row.names = FALSE)

    # ICL scores table
    icl_df <- as.data.frame(icl[["clusterConsensus"]])
    write.csv(icl_df, "${prefix}_icl_scores.csv", row.names = FALSE)

    # versions.yml
    writeLines(
        c("BIOC_CONSENSUSCLUSTERPLUS:",
          paste0("    consensusclusterplus: ", packageVersion("ConsensusClusterPlus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "sample,cluster" > ${prefix}_cluster_assignments.csv
    echo "k,clusterConsensus" > ${prefix}_icl_scores.csv
    echo "4" > ${prefix}_optimal_k.txt
    echo "BIOC_CONSENSUSCLUSTERPLUS:" > versions.yml
    echo "    consensusclusterplus: 0.0.0" >> versions.yml
    """
}


// ─── Standalone entry workflow ───────────────────────────────────────────────

workflow {
    ch_input = Channel.of(
        [[id: 'test'],
         file(params.expr_matrix_rds ?: 'NO_FILE')]
    )

    BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW(
        ch_input,
        params.max_k  ?: 8,
        params.n_reps ?: 500
    )

    BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.assignments.view { meta, f ->
        "Cluster assignments written: ${f}"
    }
    BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.optimal_k.view { meta, f ->
        "Optimal k written: ${f}"
    }
}

workflow BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(expr_matrix.rds) ]
    max_k     // val: maximum clusters to test (default 8)
    n_reps    // val: bootstrap resampling iterations (default 500)

    main:
    ch_versions = Channel.empty()

    BIOC_CONSENSUSCLUSTERPLUS(ch_input, max_k, n_reps)
    ch_versions = ch_versions.mix(BIOC_CONSENSUSCLUSTERPLUS.out.versions)

    emit:
    assignments = BIOC_CONSENSUSCLUSTERPLUS.out.assignments  // [ meta, cluster_assignments.csv ]
    icl_scores  = BIOC_CONSENSUSCLUSTERPLUS.out.icl_scores   // [ meta, icl_scores.csv ]
    plots       = BIOC_CONSENSUSCLUSTERPLUS.out.plots         // [ meta, consensus_plots.pdf ] (optional)
    optimal_k   = BIOC_CONSENSUSCLUSTERPLUS.out.optimal_k    // [ meta, optimal_k.txt ]
    versions    = ch_versions
}


// Convenience alias for patient stratification context
workflow PATIENT_STRATIFICATION {
    take:
    expr_matrix  // channel: [ val(meta), path(expr_matrix.rds) ]
    max_k        // val: maximum clusters to test (default 8)
    n_reps       // val: bootstrap resampling iterations (default 500)

    main:
    BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW(expr_matrix, max_k, n_reps)

    emit:
    assignments = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.assignments
    icl_scores  = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.icl_scores
    plots       = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.plots
    optimal_k   = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.optimal_k
    versions    = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.versions
}
