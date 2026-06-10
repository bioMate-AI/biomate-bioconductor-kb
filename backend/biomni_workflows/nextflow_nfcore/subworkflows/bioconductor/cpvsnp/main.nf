#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cpvSNP — glossi_analysis
// Perform gene set analysis on independent (LD-pruned) SNP p-values using the GLOSSI method.
// Input: arrayData.csv, gene_sets.gmt, independent_snps.txt
// Container: quay.io/biocontainers/bioconductor-cpvsnp:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, TxDb.Hsapiens.UCSC.hg19.knownGene, cpvSNP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Convert GWAS data frame to a GRanges object using createArrayData. 2. Map gene IDs in the GeneSetCollection to SNP IDs using geneT

nextflow.enable.dsl = 2

process BIOC_CPVSNP_GLOSSI_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    library(cpvSNP)
    library(GSEABase)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    
    # 1. Read user input files from the working directory
    arrayData <- read.csv("arrayData.csv", stringsAsFactors = FALSE)
    geneSets <- getGmt("gene_sets.gmt")
    indep <- read.table("independent_snps.txt", header = FALSE, stringsAsFactors = FALSE)
    
    # 2. Convert GWAS data frame to a GRanges object using createArrayData
    arrayDataGR <- createArrayData(arrayData, positionName = "Position")
    
    # 3. Map gene IDs in the GeneSetCollection to SNP IDs using geneToSNPList and a transcript database
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    genesHg19 <- genes(txdb)
    snpsGSC <- geneToSNPList(geneSets, arrayDataGR, genesHg19)
    
    # 4. Subset the GWAS GRanges to independent SNPs and extract named p-values
    pvals <- arrayDataGR\$P[is.element(arrayDataGR\$SNP, indep\$V1)]
    names(pvals) <- arrayDataGR\$SNP[is.element(arrayDataGR\$SNP, indep\$V1)]
    
    # 5. Run GLOSSI using glossi
    gRes <- glossi(pvals, snpsGSC)
    
    # 6. Extract results using pValue, degreesOfFreedom, and statistic
    p_values <- pValue(gRes)
    dfs <- degreesOfFreedom(gRes)
    stats <- statistic(gRes)
    
    # Create a summary data frame and write to a CSV file
    results_df <- data.frame(
      GeneSet = names(p_values),
      PValue = unlist(p_values),
      DegreesOfFreedom = unlist(dfs),
      Statistic = unlist(stats),
      row.names = NULL,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "glossi_results.csv", row.names = FALSE)
    
    # Save the GLOSSIResultCollection object as an RDS file
    saveRDS(gRes, "glossi_results.rds")
    
    # 7. Visualize results using plotPvals and save to a PDF file
    pdf("glossi_pvals_plot.pdf")
    plotPvals(gRes, main = "GLOSSI P-values")
    dev.off()

    writeLines(c(
        '"BIOC_CPVSNP_GLOSSI_ANALYSIS":',
        paste0('    cpvSNP: ', as.character(packageVersion('cpvSNP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glossi_analysis.csv versions.yml
    """
}

workflow BIOC_CPVSNP_GLOSSI_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arrayData.csv, gene_sets.gmt, independent_snps.txt ] ]

    main:
    BIOC_CPVSNP_GLOSSI_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.tables
    plots    = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.plots
    objects  = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.objects
    versions = BIOC_CPVSNP_GLOSSI_ANALYSIS.out.versions
}
