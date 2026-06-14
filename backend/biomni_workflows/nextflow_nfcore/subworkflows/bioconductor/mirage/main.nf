#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MiRaGE — mirna_regulation_inference
// Infer miRNA target gene regulation from mRNA expression profiles and identify significantly active miRNAs.
// Input: x_all_7a.csv
// Container: quay.io/biocontainers/bioconductor-mirage:1.52.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, MiRaGE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the gene expression data and format it into an ExpressionSet object with required sample_name and gene_id metadata
//  * 2. [Core Analysis] Run the MiRaGE analysis to compute P-values for miRNA target regulation
//  * 3. [Core Analysis] Perform multiple comparison correction on the resulting P-values to identify significantly active miRNAs

nextflow.enable.dsl = 2

process BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MiRaGE", "Biobase")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(MiRaGE)
        library(Biobase)
        
        # 1. Load the gene expression data and format it into an ExpressionSet object
        # Read the user input file from the working directory
        x_gene <- read.csv("x_all_7a.csv", sep="\t")
        
        # Construct the ExpressionSet object with required metadata
        gene_exp <- new("ExpressionSet", exprs=data.matrix(x_gene[,-1]))
        fData(gene_exp)[["gene_id"]] <- x_gene[,1]
        pData(gene_exp)[["sample_name"]] <- colnames(x_gene)[-1]
        
        # 2. Run the MiRaGE analysis to compute P-values for miRNA target regulation
        result <- MiRaGE(gene_exp, location="web", species="HS")
        
        # 3. Perform multiple comparison correction on the resulting P-values
        p_adj <- p.adjust(result\$P1[,2], method="BH")
        sig_mirnas <- result\$P1[,1][p.adjust(result\$P1[,2], method="BH")<0.05]
        
        # Write outputs
        # Save the raw results for both P0 (upregulation) and P1 (downregulation)
        write.csv(result\$P0, "mirage_P0_upregulation.csv", row.names=FALSE)
        write.csv(result\$P1, "mirage_P1_downregulation.csv", row.names=FALSE)
        
        # Save adjusted P-values summary for downregulation (P1)
        p1_summary <- data.frame(
          miRNA = result\$P1[,1],
          P_value = result\$P1[,2],
          Adjusted_P_value = p_adj
        )
        write.csv(p1_summary, "mirage_P1_adjusted_results.csv", row.names=FALSE)
        
        # Save the list of significantly active miRNAs (adjusted P < 0.05)
        writeLines(as.character(sig_mirnas), "significant_active_mirnas.txt")
        
        # Save the complete result object as an RDS file
        saveRDS(result, "mirage_results.rds")

    writeLines(c(
        '"BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE":',
        paste0('    MiRaGE: ', as.character(packageVersion('MiRaGE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_regulation_inference.csv versions.yml
    """
}

workflow BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x_all_7a.csv ] ]

    main:
    BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE(ch_input)

    emit:
    tables   = BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE.out.tables
    plots    = BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE.out.plots
    objects  = BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE.out.objects
    versions = BIOC_MIRAGE_MIRNA_REGULATION_INFERENCE.out.versions
}
