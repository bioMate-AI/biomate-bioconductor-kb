#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MOSim — bulk_multi_omics_simulation
// Simulate bulk multi-omics data (RNA-seq and regulatory omics) using custom or default seed datasets and experimental designs.
// Input: custom_rnaseq.csv, custom_dnaseseq.csv, dnase_genes.csv, custom_tf.csv
// Container: quay.io/biocontainers/bioconductor-mosim:2.6.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MOSim, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare custom seed data and association lists using omicData
//  * 2. [Input & Preparation] Define simulation options for each omic using omicSim
//  * 3. [Core Analysis] Run the simulation using mosim
//  * 4. [Core Analysis] Retrieve settings and count matrices using omicSettings and omicResults
//  * 5. [Core Analysis] Generate experimental design matrix using experimentalDesign
//  * 6. [Visualization & Output] Plot profiles using plotProfile
//  * 7. [Core Analysis] Discretize regulator data if needed using discretize

nextflow.enable.dsl = 2

process BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(MOSim)
    library(ggplot2)
    
    # Read user input files from the working directory
    custom_rnaseq <- read.csv("custom_rnaseq.csv", row.names = 1)
    custom_dnaseseq <- read.csv("custom_dnaseseq.csv", row.names = 1)
    dnase_genes <- read.csv("dnase_genes.csv")
    custom_tf <- read.csv("custom_tf.csv")
    
    # 1. Prepare custom seed data and association lists using omicData
    rnaseq_customdata <- omicData("RNA-seq", data = custom_rnaseq)
    dnase_genes <- dnase_genes[dnase_genes\$ID %in% rownames(custom_dnaseseq), ]
    dnaseseq_customdata <- omicData("DNase-seq", data = custom_dnaseseq, associationList = dnase_genes)
    
    # 2. Define simulation options for each omic using omicSim
    # To avoid using default data, we define omics_list as a list of our custom omicData objects
    omics_list <- list(
        "RNA-seq" = rnaseq_customdata,
        "DNase-seq" = dnaseseq_customdata
    )
    
    # Dynamically adjust totalFeatures to match custom data size to prevent out-of-bounds errors
    total_features_rna <- min(2500, nrow(custom_rnaseq))
    total_features_dnase <- min(1500, nrow(custom_dnaseseq))
    
    omics_options <- c(omicSim("RNA-seq", totalFeatures = total_features_rna, depth = 74),
                       omicSim("DNase-seq",
                               totalFeatures = total_features_dnase,
                               regulatorEffect = list(
                                    'activator' = 0.68,
                                    'repressor' = 0.3,
                                    'NE' = 0.02
                                )))
    
    # 3. Run the simulation using mosim
    set.seed(12345)
    multi_simulation <- mosim(omics = omics_list,
                              omicsOptions = omics_options,
                              TFtoGene = custom_tf)
    
    # 4. Retrieve settings and count matrices using omicSettings and omicResults
    rnaseq_settings <- omicSettings(multi_simulation, "RNA-seq")
    all_settings <- omicSettings(multi_simulation)
    dnase_settings <- omicSettings(multi_simulation, "DNase-seq",
                                   association = TRUE)
    rnaseq_simulated <- omicResults(multi_simulation, "RNA-seq")
    all_simulated <- omicResults(multi_simulation)
    
    # 5. Generate experimental design matrix using experimentalDesign
    rnaseq_simulation <- mosim(omics = list("RNA-seq" = rnaseq_customdata))
    design_matrix <- experimentalDesign(rnaseq_simulation)
    
    # 6. Plot profiles using plotProfile
    rna_id <- head(rnaseq_settings\$ID, 1)
    dnase_id <- head(dnase_settings\$settings[['DNase-seq']]\$ID, 1)
    
    tryCatch({
        profile_plot <- plotProfile(multi_simulation,
                                    omics = c("RNA-seq", "DNase-seq"),
                                    featureIDS = list(
                                        "RNA-seq" = rna_id,
                                        "DNase-seq" = dnase_id
                                    ))
        ggsave("profile_plot.pdf", plot = profile_plot)
    }, error = function(e) {
        message("plotProfile failed: ", e\$message)
    })
    
    # 7. Discretize regulator data if needed using discretize
    tryCatch({
        discrete_DNase <- discretize(all_simulated, "DNase-seq")
        write.csv(discrete_DNase, "discrete_DNase.csv", row.names = TRUE)
    }, error = function(e) {
        message("discretize failed: ", e\$message)
    })
    
    # Save outputs
    write.csv(rnaseq_settings, "rnaseq_settings.csv", row.names = FALSE)
    write.csv(rnaseq_simulated, "rnaseq_simulated.csv", row.names = TRUE)
    write.csv(design_matrix, "design_matrix.csv", row.names = TRUE)
    saveRDS(multi_simulation, "multi_simulation.rds")

    writeLines(c(
        '"BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION":',
        paste0('    MOSim: ', as.character(packageVersion('MOSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_multi_omics_simulation.csv versions.yml
    """
}

workflow BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ custom_rnaseq.csv, custom_dnaseseq.csv, dnase_genes.csv, custom_tf.csv ] ]

    main:
    BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION(ch_input)

    emit:
    tables   = BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION.out.tables
    plots    = BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION.out.plots
    objects  = BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION.out.objects
    versions = BIOC_MOSIM_BULK_MULTI_OMICS_SIMULATION.out.versions
}
