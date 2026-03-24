#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: prebs
// The prebs package aims at making RNA-sequencing (RNA-seq) data more comparable to microarray data. T
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/prebs/inst/doc/prebs.R
// Upstream  : affy, hgu133plus2probe, parallel
// Downstream: none
//
// Install: BiocManager::install("prebs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PREBS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-prebs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-prebs:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-prebs:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_prebs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_prebs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_prebs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(prebs)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: exprs
    ## write.table(exprs(prebs_values), file="prebs_values.txt", quote=FALSE)
    # --- Makecluster [] ---
    # Key functions: makeCluster, calc_prebs, stopCluster
    ## library("parallel")
    ## N_CORES = 2
    ## CLUSTER <- makeCluster(N_CORES)
    ## prebs_values <- calc_prebs(bam_files, custom_cdf_mapping1, cluster=CLUSTER)
    ## stopCluster(CLUSTER)
    # --- Calc Prebs [] ---
    # Key functions: calc_prebs
    ## prebs_values <- calc_prebs(bam_files, custom_cdf_mapping2)
    # --- Calc Prebs [] ---
    # Key functions: calc_prebs, exprs
    prebs_values <- calc_prebs(bam_files, manufacturer_cdf_mapping)
    head(exprs(prebs_values))
    # --- Calc Prebs [] ---
    # Key functions: calc_prebs
    ## prebs_values <- calc_prebs(bam_files, manufacturer_cdf_mapping,
    ##                            cdf_name="hgu133plus2cdf")
    # --- Frame [] ---
    # Key functions: frame
    library("hgu133plus2probe")
    probes <- as.data.frame(hgu133plus2probe)
    head(probes)
    # --- Substr [] ---
    # Key functions: xy2indices
    ## library("affy")
    ## probes <- probes[substr(probes$Probe.Set.Name,1,4) != "AFFX",]
    ## probes$Probe.ID <- xy2indices(probes$x, probes$y, cdf="hgu133plus2cdf")
    ## write.table(probes, file="probes.txt", quote=FALSE, row.names=FALSE, col.names=TRUE)
    # --- Table [] ---
    # Key functions: frame
    ## probe_mappings <- read.table("output_probe_mappings.map")
    ##
    ## colnames(probe_mappings) <- c("Probe.ID", "strand",
    ##                               "chr", "start", "seq", "match", "multiple")
    ##

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_prebs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_prebs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_prebs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PREBS:", paste0("    prebs: ", packageVersion("prebs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prebs_results.csv
    touch ${prefix}_prebs_output.rds
    echo "BIOC_PREBS:" > versions.yml
    echo "    prebs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PREBS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PREBS(ch_input)

    emit:
    results  = BIOC_PREBS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PREBS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PREBS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PREBS.out.versions  // channel: path(versions.yml)
}
