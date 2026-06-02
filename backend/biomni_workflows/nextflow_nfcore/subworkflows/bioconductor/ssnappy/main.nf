#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sSNAPPY
// A single sample pathway perturbation testing method for RNA-seq data. The method propagates changes 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sSNAPPY/inst/doc/sSNAPPY.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sSNAPPY")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSNAPPY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ssnappy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ssnappy:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ssnappy:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ssnappy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ssnappy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ssnappy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sSNAPPY)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: setequal, datatable
    data(logCPM_example)
    data(metadata_example)
    # check if samples included in the logCPM matrix and metadata dataframe are identical
    setequal(colnames(logCPM_example), metadata_example$sample)
    # View sample metadata
    # --- Ssfc [] ---
    # Key functions: levels, weight_ss_fc
    # Check that the baseline level of the treatment column is the control
    levels(metadata_example$treatment)[1]
    #compute weighted single sample logFCs
    # --- Lowess [] ---
    # Key functions: frame, mutate, ggplot, aes, geom_point, geom_smooth, labs
    logCPM_example %>%
        as.data.frame() %>%
    # --- Retrieve Topology [] ---
    # Key functions: retrieve_topology
    gsTopology <- retrieve_topology(database = "kegg", species = "hsapiens")
    head(names(gsTopology))
    # --- Gstopology Sub [] ---
    # Key functions: retrieve_topology
    gsTopology_sub <- retrieve_topology(
      database = "kegg",
      species = "hsapiens",
      keyword = "metabolism")
    head(names(gsTopology_sub))
    # --- Gstopology Mult [] ---
    # Key functions: retrieve_topology
    gsTopology_mult <- retrieve_topology(
      database = c("kegg", "reactome"),
      species = "hsapiens",
      keyword = c("metabolism", "estrogen"))
    names(gsTopology_mult)
    # --- Permutedscore [] ---
    # Key functions: generate_permuted_scores
    set.seed(123)
    # --- Normalisedscores [] ---
    # Key functions: normalise_by_permu
    normalisedScores <- normalise_by_permu(permutedScore, pathwayPertScore, sortBy = "pvalue")
    # --- Dt Indi [] ---
    # Key functions: filter
    normalisedScores %>%
        dplyr::filter(adjPvalue < 0.05)
    # --- Fit [] ---
    # Key functions: left_join, split, lm, frame
    fit <- normalisedScores %>%
        left_join(metadata_example) %>%
        split(f = .$gs_name) %>%
        lapply(function(x)lm(robustZ ~ 0 + treatment, data = x)) %>%
        lapply(summary)
    # --- Treat Sig Dt [] ---
    # Key functions: filter, mutate_at, vars, mutate_if, mutate, ifelse, select
    treat_sig %>%
        dplyr::filter(FDR < 0.05) %>%
        mutate_at(vars(c("Treatment", "gs_name")), as.factor) %>%
        mutate_if(is.numeric, sprintf, fmt = '%#.4f') %>%
        mutate(Direction = ifelse(Estimate < 0, "Inhibited", "Activation")) %>%
    # --- Annotation Df [] ---
    # Key functions: filter, mutate, cut, select, left_join
    annotation_df <- normalisedScores %>%
        dplyr::filter(gs_name == "kegg.Proteoglycans in cancer") %>%
    # --- Top500 Fc [] ---
    # Key functions: str_detect, ifelse
    meanFC <- weightedFC$weighted_logFC %>%
        .[, str_detect(colnames(.), "E2", negate = TRUE)] %>%
        apply(1, mean )
    top500_gene <- meanFC %>%
        abs() %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ssnappy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ssnappy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ssnappy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SSNAPPY:", paste0("    ssnappy: ", packageVersion("sSNAPPY"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ssnappy_results.csv
    touch ${prefix}_ssnappy_output.rds
    echo "BIOC_SSNAPPY:" > versions.yml
    echo "    ssnappy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SSNAPPY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SSNAPPY(ch_input)

    emit:
    results  = BIOC_SSNAPPY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SSNAPPY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SSNAPPY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SSNAPPY.out.versions  // channel: path(versions.yml)
}
