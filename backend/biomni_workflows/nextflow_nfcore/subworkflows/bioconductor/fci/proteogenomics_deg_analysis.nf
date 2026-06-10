#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fCI — proteogenomics_deg_analysis
// Identify co-regulated differentially expressed genes across multi-dimensional/integrated proteogenomics datasets.
// Input: proteoGenomics.txt
// Container: quay.io/biocontainers/bioconductor-fci:1.40.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: fCI
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize NPCI object; 2. Set fCI runtime variables (optional); 3. Find DEGs using lists of control and case indices across multi

nextflow.enable.dsl = 2

process BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS {
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
    library(fCI)
    
    # Define the input file path as specified by the user
    filename2 <- "proteoGenomics.txt"
    
    # Verify that the input file exists before proceeding
    if (!file.exists(filename2)) {
      stop(paste("Error: Required input file '", filename2, "' not found in the working directory.", sep=""))
    }
    
    # 1. Initialize NPCI object
    fci=new("NPCI")
    
    # 2. Set fCI runtime variables
    fci=setfCI(fci, 7:8, 11:12, seq(from=1.1,to=3,by=0.1), TRUE)
    
    # 3. Find DEGs using lists of control and case indices across multiple dimensions
    targets=find.fci.targets(fci, list(1:2, 7:8), list(5:6, 11:12), filename2)
    
    # 4. Extract and display co-regulated DEGs
    Diff.Expr.Genes=show.targets(targets)
    print("Differentially Expressed Genes (Head):")
    print(head(Diff.Expr.Genes))
    
    # Read and display the original proteogenomics data
    proteogenomic.data=read.csv(filename2, sep="\t")
    print("Proteogenomics Data (Head):")
    print(head(proteogenomic.data))
    
    # 5. Plot kernel density distributions and save to PDF
    pdf("kernel_density_plots.pdf", width=8, height=6)
    tryCatch({
      figures(targets)
    }, error = function(e) {
      message("Note: Kernel density plotting skipped or encountered an issue: ", e\$message)
    })
    dev.off()
    
    # Save meaningful results to output files
    write.csv(Diff.Expr.Genes, "differentially_expressed_genes.csv", row.names = FALSE)
    saveRDS(targets, "fci_targets.rds")
    
    print("Pipeline completed successfully. Outputs saved: 'differentially_expressed_genes.csv', 'fci_targets.rds', and 'kernel_density_plots.pdf'.")

    writeLines(c(
        '"BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS":',
        paste0('    fCI: ', as.character(packageVersion('fCI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteogenomics_deg_analysis.csv versions.yml
    """
}

workflow BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteoGenomics.txt ] ]

    main:
    BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS.out.tables
    plots    = BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS.out.plots
    objects  = BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS.out.objects
    versions = BIOC_FCI_PROTEOGENOMICS_DEG_ANALYSIS.out.versions
}
