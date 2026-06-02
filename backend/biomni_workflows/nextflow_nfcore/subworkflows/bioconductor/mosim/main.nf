#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MOSim
// MOSim package simulates multi-omic experiments that mimic regulatory mechanisms within the cell, all
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MOSim/inst/doc/MOSim.R
// Upstream  : devtools, ggplot2
// Downstream: none
//
// Install: BiocManager::install("MOSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosim:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosim:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MOSim)
    library(jsonlite)


    # --- Code2 [] ---
    # Key functions: mosim
    library(MOSim)

    omic_list <- c("RNA-seq")

    rnaseq_simulation <- mosim(omics = omic_list)
    rnaseq_simulation <- mosim(omics = c("RNA-seq"),
                               times = 0,
                               numberGroups = 2,
                               numberReps = 4)

    # --- Code6 [] ---
    # Key functions: omicData, mosim, sampleData
    # Take a subset of the included dataset for illustration
    # purposes. We could also load it from a csv file or RData,
    # as long as we transform it to have 1 column named "Counts"
    # and the identifiers as row names.
    data("sampleData")

    custom_rnaseq <- head(sampleData$SimRNAseq$data, 100)

    # In this case, 'custom_rnaseq' is a data frame with
    # the structure:
    # Select a subset of the available data as a custom dataset
    data("sampleData")

    custom_dnaseseq <- head(sampleData$SimDNaseseq$data, 100)

    # Retrieve a subset of the default association list.
    dnase_genes <- sampleData$SimDNaseseq$idToGene
    dnase_genes <- dnase_genes[dnase_genes$ID %in%
                                   rownames(custom_dnaseseq), ]

    # --- Code8 [] ---
    # Key functions: mosim, sampleData, omics
    # Select a subset of the available data as a custom dataset
    data("sampleData")

    custom_tf <- head(sampleData$SimRNAseq$TFtoGene, 100)
    #      TF             TFgene         LinkedGene
    # 1  Aebp2 ENSMUSG00000030232 ENSMUSG00000000711
    # 2  Aebp2 ENSMUSG00000030232 ENSMUSG00000001157
    # 3  Aebp2 ENSMUSG00000030232 ENSMUSG00000001211
    # 4  Aebp2 ENSMUSG00000030232 ENSMUSG00000001227
    # 5  Aebp2 ENSMUSG00000030232 ENSMUSG00000001305
    # Select a subset of the available data as a custom dataset
    data("sampleData")

    custom_cpgs <- head(sampleData$SimMethylseq$idToGene, 100)

    # The ID column will be splitted using the "_" char
    # assuming <chr>_<start>_<end>.
    #
    # These positions will be considered as CpG sites
    # and used to generate CpG islands and other elements.

    # --- Code11 [] ---
    # Key functions: omicSim, mosim, omicData
    omics_list <- c("RNA-seq", "DNase-seq")

    # In R concatenaning two lists creates another one merging
    # its elements, we use that for 'omicsOptions' parameter.
    # --- Code13 [] ---
    # Key functions: settings, omicSettings, omics
    # This will be a data frame with RNA-seq settings (DE flag, profiles)
    rnaseq_settings <- omicSettings(multi_simulation, "RNA-seq")

    # This will be a list containing all the simulated omics (RNA-seq
    # and DNase-seq in this case)
    all_settings <- omicSettings(multi_simulation)
    # This will be a list with 3 keys: settings, association and regulators
    dnase_settings <- omicSettings(multi_simulation, "DNase-seq",
                                   association = TRUE)

    # --- Code15 [] ---
    # Key functions: omicResults, mosim, experimentalDesign
    # multi_simulation is an object returned by mosim function.

    # This will be a data frame with RNA-seq counts
    rnaseq_simulated <- omicResults(multi_simulation, "RNA-seq")

    #                    Group1.Time0.Rep1 Group1.Time0.Rep2 Group1.Time0.Rep3 ...
    # ENSMUSG00000073155              4539              5374              5808 ...
    # ENSMUSG00000026251                 0                 0                 0 ...
    # ENSMUSG00000040472              2742              2714              2912 ...
    # ENSMUSG00000021598              5256              4640              5130 ...
    # Generate a simulation object
    omic_list <- c("RNA-seq")
    rnaseq_simulation <- mosim(omics = omic_list)

    # This will be a data frame with RNA-seq counts
    design_matrix <- experimentalDesign(rnaseq_simulation)
    design_matrix

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSIM:", paste0("    mosim: ", packageVersion("MOSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosim_results.csv
    touch ${prefix}_mosim_output.rds
    echo "BIOC_MOSIM:" > versions.yml
    echo "    mosim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSIM(ch_input)

    emit:
    results  = BIOC_MOSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSIM.out.versions  // channel: path(versions.yml)
}
