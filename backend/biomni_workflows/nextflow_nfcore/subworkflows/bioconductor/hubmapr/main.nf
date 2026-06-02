#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HuBMAPR
// 'HuBMAP' provides an open, global bio-molecular atlas of the human body at the cellular level. The `
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HuBMAPR/inst/doc/hubmapr_vignettes.R
// Upstream  : dplyr, ggplot2, pryr, tidyr
// Downstream: none
//
// Install: BiocManager::install("HuBMAPR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HUBMAPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hubmapr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hubmapr:1.0.8--r44_0' :
        'quay.io/biocontainers/bioconductor-hubmapr:1.0.8--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hubmapr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hubmapr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hubmapr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HuBMAPR)
    library(jsonlite)

    # --- Metadata and Schema Inspection [] ---
    # Key functions: datasets_default_columns, organ, dataset_metadata, sample_metadata, donor_metadata
    default_cols <- datasets_default_columns(as = "character")
    organs_list <- organ()
    ds_meta <- dataset_metadata("993bb1d6fa02e2755fd69613bb9d6e08")
    sm_meta <- sample_metadata("8ecdbdc3e2d04898e2563d666658b6a9")
    dn_meta <- donor_metadata("b2c75c96558c18c9e13ba31629f541b6")


    # --- Entity Detail and Provenance Tracking [] ---
    # Key functions: dataset_detail, uuid_provenance, dataset_derived, sample_derived
    target_uuid <- "3e4c568d9ce8df9d73b8cddcf8d0fec3"
    detail_info <- dataset_detail(uuid = target_uuid)
    provenance_info <- uuid_provenance(uuid = target_uuid)
    derived_datasets <- dataset_derived(uuid = target_uuid)
    derived_samples <- sample_derived(
        uuid = "35e16f13caab262f446836f63cf4ad42",
        entity_type = "Sample"
    )


    # --- Collection and Publication Data Association [] ---
    # Key functions: collection_data, publication_data, collection_information, publication_information
    coll_uuid <- "8ecdbdc3e2d04898e2563d666658b6a9"
    pub_uuid <- "b2c75c96558c18c9e13ba31629f541b6"
    coll_data <- collection_data(uuid = coll_uuid)
    pub_data <- publication_data(uuid = pub_uuid, entity_type = "Dataset")
    coll_info <- collection_information(uuid = coll_uuid)
    pub_info <- publication_information(uuid = pub_uuid)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hubmapr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hubmapr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hubmapr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HUBMAPR:", paste0("    hubmapr: ", packageVersion("HuBMAPR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hubmapr_results.csv
    touch ${prefix}_hubmapr_output.rds
    echo "BIOC_HUBMAPR:" > versions.yml
    echo "    hubmapr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HUBMAPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HUBMAPR(ch_input)

    emit:
    results  = BIOC_HUBMAPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HUBMAPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HUBMAPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HUBMAPR.out.versions  // channel: path(versions.yml)
}
