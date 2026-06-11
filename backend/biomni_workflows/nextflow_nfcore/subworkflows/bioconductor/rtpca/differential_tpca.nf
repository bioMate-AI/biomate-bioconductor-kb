#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rtpca — differential_tpca
// Identify protein-protein interactions that change significantly between two experimental conditions.
// Input: tpp_control_data.RData, tpp_treatment_data.RData, ppi_annotations.csv
// Container: quay.io/biocontainers/bioconductor-rtpca:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Rtpca, dplyr
// Visualizations: PCA plot, volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run differential TPCA using runDiffTPCA
//  * 2. [Visualization & Output] Plot a volcano plot of the differential results using plotDiffTpcaVolcano
//  * 3. [Core Analysis] Extract and inspect the results table using diffTpcaResultTable
//  * 4. [Visualization & Output] Plot melting profiles of candidate pairs using plotPPiProfiles

nextflow.enable.dsl = 2

process BIOC_RTPCA_DIFFERENTIAL_TPCA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(Rtpca)
    library(dplyr)
    library(TPP)
    
    # Helper function to load RData safely and extract the contained object
    load_rdata <- function(file) {
      env <- new.env()
      load(file, envir = env)
      objs <- as.list(env)
      if (length(objs) == 1) {
        return(objs[[1]])
      } else {
        return(objs)
      }
    }
    
    # Read user input files from the working directory
    control_data <- load_rdata("tpp_control_data.RData")
    treatment_data <- load_rdata("tpp_treatment_data.RData")
    string_ppi_cs_950_df <- read.csv("ppi_annotations.csv", stringsAsFactors = FALSE)
    
    # 1. Run differential TPCA using runDiffTPCA
    diffTPCA <- 
        runDiffTPCA(
            objList = control_data, 
            contrastList = treatment_data,
            ctrlCondName = "Control",
            contrastCondName = "Treatment",
            ppiAnno = string_ppi_cs_950_df)
    
    # Save the resulting object
    saveRDS(diffTPCA, file = "diffTPCA_results.rds")
    
    # 2. Plot a volcano plot of the differential results using plotDiffTpcaVolcano
    pdf("diff_tpca_volcano_plot.pdf", width = 7, height = 7)
    print(plotDiffTpcaVolcano(
        diffTPCA,
        setXLim = TRUE,
        xlimit = c(-0.5, 0.5)))
    dev.off()
    
    # 3. Extract and inspect the results table using diffTpcaResultTable
    results_full <- diffTpcaResultTable(diffTPCA)
    write.csv(results_full, "diff_tpca_results_full.csv", row.names = FALSE)
    
    results_summary <- head(diffTpcaResultTable(diffTPCA) %>% 
             arrange(p_value) %>% 
            dplyr::select(pair, rssC1_rssC2, f_stat, p_value, p_adj))
    write.csv(results_summary, "diff_tpca_results_summary.csv", row.names = FALSE)
    
    # Dynamically select the top pair from the results table
    top_pair_str <- as.character(results_summary\$pair[1])
    top_pair <- unlist(strsplit(top_pair_str, ":"))
    
    # 4. Plot melting profiles of candidate pairs using plotPPiProfiles
    tryCatch({
        pdf("ppi_profiles_plot.pdf", width = 7, height = 7)
        print(plotPPiProfiles(diffTPCA, pair = top_pair))
        dev.off()
    }, error = function(e) {
        dev.off()
        message("Could not plot PPI profiles for ", top_pair[1], " and ", top_pair[2], ": ", e\$message)
    })

    writeLines(c(
        '"BIOC_RTPCA_DIFFERENTIAL_TPCA":',
        paste0('    Rtpca: ', as.character(packageVersion('Rtpca')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_tpca.csv versions.yml
    """
}

workflow BIOC_RTPCA_DIFFERENTIAL_TPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tpp_control_data.RData, tpp_treatment_data.RData, ppi_annotations.csv ] ]

    main:
    BIOC_RTPCA_DIFFERENTIAL_TPCA(ch_input)

    emit:
    tables   = BIOC_RTPCA_DIFFERENTIAL_TPCA.out.tables
    plots    = BIOC_RTPCA_DIFFERENTIAL_TPCA.out.plots
    objects  = BIOC_RTPCA_DIFFERENTIAL_TPCA.out.objects
    versions = BIOC_RTPCA_DIFFERENTIAL_TPCA.out.versions
}
