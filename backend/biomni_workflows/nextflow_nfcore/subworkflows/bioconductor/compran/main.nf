#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ComPrAn — peptide_to_protein_workflow
// Perform a full analysis starting from raw peptide-level tables to clean, filter, select representative peptides, normalize, cluster, and visualize SILAC complex
// Input: peptide_input.txt
// Container: quay.io/biocontainers/bioconductor-compran:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComPrAn
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import peptide data
//  * 2. [Core Analysis] Clean and filter data
//  * 3. [Core Analysis] Split modifications and simplify protein rows
//  * 4. [Core Analysis] Select representative peptides
//  * 5. [Core Analysis] Generate normalized protein tables
//  * 6. [Core Analysis] Perform hierarchical clustering
//  * 7. [Visualization & Output] Assign clusters and export results
//  * 8. [Visualization & Output] Visualize peptide and cluster summaries

nextflow.enable.dsl = 2

process BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("ComPrAn")
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
        library(ComPrAn)
        
        # Define input file path (exactly as requested)
        inputFile <- "peptide_input.txt"
        
        # 1. Import peptide data
        peptides <- peptideImport (inputFile)
        
        # 2. Clean and filter data
        peptides <- cleanData (peptides, fCol = "Search ID" )
        peptides <- toFilter (peptides, rank = 1 )
        
        # 3. Split modifications and simplify protein rows
        peptides <- splitModLab (peptides)
        peptides <- simplifyProteins (peptides)
        
        # 4. Select representative peptides
        peptide_index <- pickPeptide (peptides)
        
        # Define protein and dynamically determine max_frac for visualization
        protein <- "P52815"
        
        max_frac <- 23 # Default fallback
        if (is.data.frame(peptides) && "Search ID" %in% colnames(peptides)) {
          max_frac <- max(as.numeric(peptides[["Search ID"]]), na.rm = TRUE)
        }
        
        # Robust fallback: If the default protein "P52815" is not present in the user's dataset,
        # dynamically select the first available protein to prevent plotting failures.
        tryCatch({
          df_check <- NULL
          if (is.data.frame(peptide_index)) {
            df_check <- peptide_index
          } else if (is.list(peptide_index)) {
            for (el in peptide_index) {
              if (is.data.frame(el)) {
                df_check <- el
                break
              }
            }
          }
          if (!is.null(df_check)) {
            acc_col <- grep("Accession|Protein", colnames(df_check), value = TRUE, ignore.case = TRUE)
            if (length(acc_col) > 0) {
              available_proteins <- unique(df_check[[acc_col[1]]])
              if (!(protein %in% available_proteins) && length(available_proteins) > 0) {
                protein <- as.character(available_proteins[1])
              }
            }
          }
        }, error = function(e) {
          warning("Could not dynamically resolve protein ID; falling back to default 'P52815'.")
        })
        
        # Open PDF device to capture all plots
        pdf("compran_analysis_plots.pdf", width = 10, height = 8)
        
        # Generate peptide plot
        tryCatch({
          print(allPeptidesPlot (peptide_index,protein, max_frac = max_frac))
        }, error = function(e) {
          message("Skipping allPeptidesPlot due to error: ", e\$message)
        })
        
        # 5. Generate normalized protein tables
        listOnlyOneLabState <- onlyInOneLabelState (peptide_index)
        forAnalysis <- getNormTable (peptide_index, purpose = "analysis" )
        forExport <- getNormTable (peptide_index, purpose = "export" )
        
        # 6. Perform hierarchical clustering
        clusteringDF <- clusterComp (forAnalysis, scenar = "A" , PearsCor = "centered" )
        
        # 7. Assign clusters and export results
        labTab_clust <- assignClusters ( .listDf = clusteringDF, sample = "labeled" , method = 'average' , cutoff = 0.85 )
        unlabTab_clust <- assignClusters ( .listDf = clusteringDF, sample = "unlabeled" , method = 'average' , cutoff = 0.85 )
        
        # 8. Visualize cluster summaries
        tryCatch({
          print(makeBarPlotClusterSummary (labTab_clust, name = 'labeled' ))
        }, error = function(e) {
          message("Skipping labeled cluster summary plot due to error: ", e\$message)
        })
        
        tryCatch({
          print(makeBarPlotClusterSummary (unlabTab_clust, name = 'unlabeled' ))
        }, error = function(e) {
          message("Skipping unlabeled cluster summary plot due to error: ", e\$message)
        })
        
        # Close PDF device
        dev.off()
        
        # Export cluster assignments
        tableForClusterExport <- exportClusterAssignments (labTab_clust,unlabTab_clust)
        
        # Write output files
        write.table(forExport, "normalized_proteins_export.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
        write.table(tableForClusterExport, "cluster_assignments.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
        
        # Save R objects for downstream flexibility
        saveRDS(listOnlyOneLabState, "listOnlyOneLabState.rds")
        saveRDS(forAnalysis, "forAnalysis.rds")
        saveRDS(clusteringDF, "clusteringDF.rds")
        saveRDS(labTab_clust, "labTab_clust.rds")
        saveRDS(unlabTab_clust, "unlabTab_clust.rds")
        
        cat("ComPrAn pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW":',
        paste0('    ComPrAn: ', as.character(packageVersion('ComPrAn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peptide_to_protein_workflow.csv versions.yml
    """
}

workflow BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptide_input.txt ] ]

    main:
    BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW.out.tables
    plots    = BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW.out.plots
    objects  = BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW.out.objects
    versions = BIOC_COMPRAN_PEPTIDE_TO_PROTEIN_WORKFLOW.out.versions
}
