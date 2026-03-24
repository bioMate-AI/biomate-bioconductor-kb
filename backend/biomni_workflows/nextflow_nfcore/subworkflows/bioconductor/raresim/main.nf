#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RAREsim
// Haplotype simulations of rare variant genetic data that emulates real data can be performed with RAR
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RAREsim/inst/doc/RAREsim_Vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RAREsim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RARESIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-raresim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-raresim:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-raresim:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_raresim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_raresim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_raresim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RAREsim)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # load the target data
    data("nvariant_afr")
    print(nvariant_afr, row.names  =  FALSE)
    # --- Fit Nvariant [] ---
    # Key functions: fit_nvariant
    ---------------------------------------------------------------------
    nvar <- fit_nvariant(nvariant_afr)
    nvar
    # --- Nvariant [] ---
    # Key functions: nvariant
    ---------------------------------------------------------------------
    nvariant(phi = nvar$phi, omega = nvar$omega, N = 8128)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # load the data
    data("afs_afr")
    print(afs_afr)
    # --- Fit Afs [] ---
    # Key functions: fit_afs
    ---------------------------------------------------------------------
    af <- fit_afs(Observed_bin_props = afs_afr)
    print(af)
    # --- Afs [] ---
    # Key functions: afs
    ---------------------------------------------------------------------
    afs(mac_bins = mac, pop = 'AFR')
    # --- Expected Variants [] ---
    # Key functions: expected_variants
    ---------------------------------------------------------------------
    bin_estimates <- expected_variants(Total_num_var = 865.0634, mac_bin_prop = af$Fitted_results)
    print(bin_estimates)
    # --- Expected Variants [] ---
    # Key functions: expected_variants, nvariant, afs
    ---------------------------------------------------------------------
    bin_estimates <- expected_variants(Total_num_var =
                                         19.029*nvariant(phi = 0.1638108,
                                                         omega = 0.6248848, N = 8128),
                                       mac_bin_prop = afs(mac_bins = mac, pop = 'AFR'))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_raresim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_raresim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_raresim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RARESIM:", paste0("    raresim: ", packageVersion("RAREsim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raresim_results.csv
    touch ${prefix}_raresim_output.rds
    echo "BIOC_RARESIM:" > versions.yml
    echo "    raresim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RARESIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RARESIM(ch_input)

    emit:
    results  = BIOC_RARESIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RARESIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RARESIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RARESIM.out.versions  // channel: path(versions.yml)
}
