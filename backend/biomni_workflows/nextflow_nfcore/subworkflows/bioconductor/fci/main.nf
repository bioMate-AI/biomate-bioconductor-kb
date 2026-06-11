#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fCI — single_omic_deg_analysis
// Identify differentially expressed genes from a single-omic dataset (e.g., transcriptomics or proteomics) with control and case replicates.
// Input: Supp_Dataset_part_2.txt, fci.data
// Container: quay.io/biocontainers/bioconductor-fci:1.40.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: fCI
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Normalize data (optional, e.g., total library size or trimmed sum normalization); 2. Initialize NPCI object; 3. Find DEGs using co

nextflow.enable.dsl = 2

process BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS {
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
            
    # Load the required Bioconductor package
    suppressPackageStartupMessages(library(fCI))
    
    # Define input file paths
    filename <- "Supp_Dataset_part_2.txt"
    
    # Verify that the required input files exist
    if (!file.exists(filename)) {
      stop(paste("Required input file missing:", filename))
    }
    
    # Read the input file robustly
    fci.data <- tryCatch({
      readRDS(filename)
    }, error = function(e) {
      # If not RDS, attempt to read as a tab-delimited or CSV table
      df <- tryCatch({
        read.table(filename, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
      }, error = function(e2) {
        read.csv(filename, header = TRUE, stringsAsFactors = FALSE)
      })
      # If the first column is non-numeric (e.g., gene names), set as row names
      if (ncol(df) > 0 && !is.numeric(df[[1]])) {
        rownames(df) <- df[[1]]
        df <- df[-1]
      }
      df
    })
    fci.data <- as.data.frame(fci.data)
    
    # 1. Normalize data
    fci.data = total.library.size.normalization(fci.data)
    
    # Save the normalized data frame
    write.csv(fci.data, "normalized_fci_data.csv", row.names = TRUE)
    
    # 2. Initialize NPCI object and find targets using control and case column indices
    fci = new("NPCI")
    fci = find.fci.targets(fci, c(1,2,3), c(4,5,6), fci.data)
    
    # 3. Extract and display identified DEGs
    Diff.Expr.Genes = show.targets(fci)
    print("Differentially Expressed Genes (Full Set):")
    print(head(Diff.Expr.Genes))
    
    # Save identified DEGs to a CSV file
    if (!is.null(Diff.Expr.Genes)) {
      write.csv(Diff.Expr.Genes, "Diff_Expr_Genes.csv", row.names = FALSE)
    }
    
    # Save the NPCI object
    saveRDS(fci, "fci_object.rds")
    
    # 4. Plot kernel density distributions to a PDF file
    pdf("fci_kernel_density_plots.pdf")
    figures(fci)
    dev.off()
    
    # 5. Find targets with a subset of samples
    fci = find.fci.targets(fci, c(1,2), 5, fci.data)
    Diff.Expr.Genes_subset = show.targets(fci)
    print("Differentially Expressed Genes (Subset):")
    print(head(Diff.Expr.Genes_subset))
    
    if (!is.null(Diff.Expr.Genes_subset)) {
      write.csv(Diff.Expr.Genes_subset, "Diff_Expr_Genes_subset.csv", row.names = FALSE)
    }
    
    # 6. Alternative shortcut function to find DEGs
    Diff.Expr.Genes = fCI.call.by.index(c(1,2,3), c(4,5,6), filename)
    print("Differentially Expressed Genes (Call by Index):")
    print(head(Diff.Expr.Genes))
    
    if (!is.null(Diff.Expr.Genes)) {
      write.csv(Diff.Expr.Genes, "Diff_Expr_Genes_call_by_index.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS":',
        paste0('    fCI: ', as.character(packageVersion('fCI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_omic_deg_analysis.csv versions.yml
    """
}

workflow BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Supp_Dataset_part_2.txt, fci.data ] ]

    main:
    BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS.out.tables
    plots    = BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS.out.plots
    objects  = BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS.out.objects
    versions = BIOC_FCI_SINGLE_OMIC_DEG_ANALYSIS.out.versions
}
