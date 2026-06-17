#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isoformswitchanalyzer — high_level_two_part_analysis
// Perform a complete isoform switch analysis using high-level wrapper functions to import, test, extract sequences, integrate external annotations, and predict co
// Input: salmon_quant_dir, annotation.gtf, transcript_sequences.fasta, cpc2_result.txt, pfam_results.txt, iupred2a_result.txt.gz, signalP_results.txt
// Container: quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.10.0--r45h01b2380_0
// R packages: IsoformSwitchAnalyzeR, VennDiagram
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.10.0--r45h01b2380_0"

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
    .bm_deps <- c("IsoformSwitchAnalyzeR", "VennDiagram")
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
    
    # Load required libraries
    library(IsoformSwitchAnalyzeR)
    
    # Define input file paths as specified by the user
    salmon_quant_dir <- "salmon_quant_dir"
    annotation_gtf <- "annotation.gtf"
    transcript_sequences_fasta <- "transcript_sequences.fasta"
    cpc2_result <- "cpc2_result.txt"
    pfam_results <- "pfam_results.txt"
    iupred2a_result <- "iupred2a_result.txt.gz"
    signalP_results <- "signalP_results.txt"
    
    # --- Import isoform expression data ---
    salmonQuant <- importIsoformExpression(
        parentDir = salmon_quant_dir
    )
    
    # --- Create a design matrix ---
    myDesign <- data.frame(
        sampleID = colnames(salmonQuant\$abundance)[-1],
        condition = gsub('_.*', '', colnames(salmonQuant\$abundance)[-1])
    )
    
    # --- Build the switchAnalyzeRlist ---
    aSwitchList <- importRdata(
        isoformCountMatrix   = salmonQuant\$counts,
        isoformRepExpression = salmonQuant\$abundance,
        designMatrix         = myDesign,
        isoformExonAnnoation = annotation_gtf,
        isoformNtFasta       = transcript_sequences_fasta,
        fixStringTieAnnotationProblem = TRUE,
        showProgress = FALSE
    )
    
    # Handle potential NA values in dIF before subsetting to prevent errors
    if ("dIF" %in% colnames(aSwitchList\$isoformFeatures)) {
        aSwitchList\$isoformFeatures\$dIF[is.na(aSwitchList\$isoformFeatures\$dIF)] <- 0
    }
    
    # Subset the switch list for isoforms with significant usage changes
    aSwitchList <- subsetSwitchAnalyzeRlist(
        switchAnalyzeRlist = aSwitchList,
        subset = abs(aSwitchList\$isoformFeatures\$dIF) > 0.1
    )
    
    # --- Run Part 1 analysis (filtering, testing, ORF annotation, ---
    aSwitchList <- isoformSwitchAnalysisPart1(
        switchAnalyzeRlist   = aSwitchList,
        outputSequences      = FALSE, 
        prepareForWebServers = FALSE  
    )
    
    # Extract and display initial switch summary
    extractSwitchSummary( aSwitchList )
    
    # --- Run Part 2 analysis (integrating external results and ---
    aSwitchList <- isoformSwitchAnalysisPart2(
      switchAnalyzeRlist        = aSwitchList, 
      n                         = 10,    
      removeNoncodinORFs        = TRUE,
      pathToCPC2resultFile      = cpc2_result,
      pathToPFAMresultFile      = pfam_results,
      pathToIUPred2AresultFile  = iupred2a_result,
      pathToSignalPresultFile   = signalP_results,
      outputPlots               = FALSE  
    )
    
    # --- Extract top switching genes with predicted consequences ---
    top_switches <- extractTopSwitches(aSwitchList, filterForConsequences = TRUE, n=3)
    
    # Write meaningful results to output files
    saveRDS(aSwitchList, file = "isoform_switch_list_analyzed.rds")
    
    switch_summary <- extractSwitchSummary(aSwitchList)
    write.csv(switch_summary, file = "switch_summary.csv", row.names = FALSE)
    
    write.csv(top_switches, file = "top_switching_genes.csv", row.names = FALSE)
    
    # Generate and save a switch plot for the top gene if available
    if (nrow(top_switches) > 0) {
        top_gene <- top_switches\$gene_name[1]
        if (is.na(top_gene) || top_gene == "") {
            top_gene <- top_switches\$gene_id[1]
        }
        
        conds <- unique(aSwitchList\$designMatrix\$condition)
        
        pdf("top_isoform_switch_plot.pdf", onefile = FALSE, height = 6, width = 9)
        if (length(conds) >= 2) {
            switchPlot(aSwitchList, gene = top_gene, condition1 = conds[1], condition2 = conds[2])
        } else {
            switchPlot(aSwitchList, gene = top_gene)
        }
        dev.off()
    }

    writeLines(c(
        '"BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS":',
        paste0('        isoformswitchanalyzer: ', as.character(packageVersion("isoformswitchanalyzer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_high_level_two_part_analysis.csv versions.yml
    """
}

workflow BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ salmon_quant_dir, annotation.gtf, transcript_sequences.fasta, cpc2_result.txt, pfam_results.txt, iupred2a_result.txt.gz, signalP_results.txt ] ]

    main:
    BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.tables
    plots    = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.plots
    objects  = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.objects
    versions = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.versions
}
