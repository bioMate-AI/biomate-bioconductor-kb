#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compSPOT — mutation_hotspot_analysis
// Identify significant mutation hotspots from genomic regions, compare hotspot burden between patient groups, and correlate mutation burden with clinical risk fac
// Input: mutation_data.csv, regions_data.csv
// Container: quay.io/biocontainers/bioconductor-compspot:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: compSPOT
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the mutation and genomic region datasets
//  * 2. [Core Analysis] Identify significant mutation hotspots using find_hotspots
//  * 3. [Core Analysis] Filter the identified hotspots for downstream analysis
//  * 4. [Core Analysis] Compare mutation hotspot burden between defined groups using compare_groups
//  * 5. [Core Analysis] Perform exploratory data analysis of mutation hotspot burden against clinical features using compare_features

nextflow.enable.dsl = 2

process BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("compSPOT")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required library
        library(compSPOT)
        
        # 1. Load the mutation and genomic region datasets from the working directory
        mutation_data <- read.csv("mutation_data.csv", stringsAsFactors = FALSE)
        regions_data <- read.csv("regions_data.csv", stringsAsFactors = FALSE)
        
        # 2. Identify significant mutation hotspots using find_hotspots
        significant_spots <- find_hotspots(data = mutation_data, 
                                           regions = regions_data, 
                                           pvalue = 0.05, threshold = 0.2, 
                                           include_genes = TRUE, 
                                           rank = TRUE)
        
        # Print the head of the significant spots table
        print("Significant Spots (Head):")
        print(head(significant_spots[[1]]))
        
        # Save the significant spots table to CSV
        write.csv(significant_spots[[1]], "significant_spots.csv", row.names = FALSE)
        saveRDS(significant_spots, "significant_spots.rds")
        
        # 3. Filter the identified hotspots for downstream analysis
        hotspots <- subset(significant_spots[[1]], type == "Hotspot")
        
        # 4. Compare mutation hotspot burden between defined groups using compare_groups
        unique_groups <- unique(na.omit(mutation_data\$Group))
        group1 <- if (length(unique_groups) >= 1) unique_groups[1] else "High-Risk"
        group2 <- if (length(unique_groups) >= 2) unique_groups[2] else "Low-Risk"
        
        group_comp <- compare_groups(data = mutation_data, 
                                     regions = hotspots, pval = 0.05, 
                                     threshold = 0.2, 
                                     name1 = group1, 
                                     name2 = group2, 
                                     include_genes = TRUE)
        
        # Print the group comparison table
        print("Group Comparison Results:")
        print(group_comp[[1]])
        
        # Save group comparison results
        write.csv(group_comp[[1]], "group_comparison.csv", row.names = FALSE)
        saveRDS(group_comp, "group_comparison.rds")
        
        # If a plot is returned in the group comparison list, attempt to save it
        if (length(group_comp) >= 2) {
          tryCatch({
            pdf("group_comparison_plot.pdf", width = 8, height = 6)
            print(group_comp[[2]])
            dev.off()
          }, error = function(e) {
            warning("Could not save group comparison plot: ", e\$message)
          })
        }
        
        # 5. Perform exploratory data analysis of mutation hotspot burden against clinical features using compare_features
        standard_cols <- c("Chromosome", "Position", "Sample", "Gene", "Group")
        features <- setdiff(colnames(mutation_data), standard_cols)
        
        # Ensure only features present in the mutation dataset are passed
        available_features <- features[features %in% colnames(mutation_data)]
        
        if (length(available_features) > 0) {
          feature_example <- compare_features(data = mutation_data, 
                                              regions = regions_data, 
                                              feature = available_features)
          
          # Save feature comparison results
          saveRDS(feature_example, "feature_comparison.rds")
          
          # If feature_example contains plots, attempt to save them
          tryCatch({
            pdf("feature_comparison_plots.pdf", width = 10, height = 8)
            if (inherits(feature_example, "list")) {
              for (i in seq_along(feature_example)) {
                print(feature_example[[i]])
              }
            } else {
              print(feature_example)
            }
            dev.off()
          }, error = function(e) {
            warning("Could not save feature comparison plots: ", e\$message)
          })
        } else {
          warning("None of the specified clinical features were found in the mutation dataset.")
        }
        
        print("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS":',
        paste0('    compSPOT: ', as.character(packageVersion('compSPOT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mutation_hotspot_analysis.csv versions.yml
    """
}

workflow BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mutation_data.csv, regions_data.csv ] ]

    main:
    BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS.out.tables
    plots    = BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS.out.plots
    objects  = BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS.out.objects
    versions = BIOC_COMPSPOT_MUTATION_HOTSPOT_ANALYSIS.out.versions
}
