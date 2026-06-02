#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RRHO
// The package is aimed at inference on the amount of agreement in two sorted lists using the Rank-Rank
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RRHO/inst/doc/RRHO.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RRHO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RRHO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rrho"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rrho:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rrho:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rrho_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rrho_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rrho_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Nominal)
    library(RRHOComparison)
    library(Vectorize)
    library(jsonlite)

    # --- Nominal [] ---
    # Key functions: Nominal, levelplot
    # Examine Nominal (-log) pvalues
      lattice::levelplot(RRHO.example$hypermat)
    # Note: If lattice is available try:
    # levelplot(RRHO.example$hypermat)
    # --- Pvalrrho [] ---
    # Key functions: pvalRRHO, the, Vectorize
    # FWER corrected pvalues using 50 random permutations:
    pval.testing <- pvalRRHO(RRHO.example, 50)
    pval.testing$pval
    # The sampling distribution of the minimum
    # of the (-log) nominal p-values:
    # --- Levelplot [] ---
    # Key functions: levelplot
    # Examine B-Y corrected pvalues
    # Note: probably nothing will be rejected in this
    # example as the data is generated from the null.
      lattice::levelplot(RRHO.example$hypermat.by)
    # --- Rhyper [] ---
    # Key functions: rhyper, pmin, phyper
    m<- 100 ; n<- 100; k<- 50
    data<- rhyper(1000, m, n, k)
    pvals<- pmin(phyper(data,m,n,k, lower.tail=TRUE),
                 phyper(data,m,n,k, lower.tail=FALSE))
    alpha<- 0.05
    # --- Function [] ---
    # Key functions: phyper
    getPval<- function(count,m,n,k){
      the.mean<- k*m/(m+n)
      if(count<the.mean){
        lower<- count
        upper<- 2*the.mean-count
    # --- Frame [] ---
    # Key functions: frame, runif, RRHOComparison
    size<- 500
    list1<- data.frame(
      GeneIdentifier=paste('gen',1:size, sep=''),
      RankingVal=-log(runif(size)))
    list2<- data.frame(
    # --- Levelplot [] ---
    # Key functions: levelplot
    ## The standard RRHO map between list1 and list 3.
    lattice::levelplot(rrho.comparison$hypermat1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rrho_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rrho_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rrho_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RRHO:", paste0("    rrho: ", packageVersion("RRHO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rrho_results.csv
    touch ${prefix}_rrho_output.rds
    echo "BIOC_RRHO:" > versions.yml
    echo "    rrho: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RRHO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RRHO(ch_input)

    emit:
    results  = BIOC_RRHO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RRHO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RRHO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RRHO.out.versions  // channel: path(versions.yml)
}
