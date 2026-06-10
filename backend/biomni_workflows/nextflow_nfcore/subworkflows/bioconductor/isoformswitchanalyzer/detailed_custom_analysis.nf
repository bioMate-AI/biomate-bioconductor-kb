#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isoformswitchanalyzer — detailed_custom_analysis
// Perform a highly customized, step-by-step isoform switch analysis using individual functions for filtering, testing, sequence extraction, and specific external 
// Input: salmon_quant_dir, annotation.gtf, transcript_sequences.fasta, cpat_results.txt, cpc2_result.txt, pfam_results.txt, signalP_results.txt, iupred2a_result.txt.gz, netsurfp3_result.csv.gz, deeploc2.csv, DeepTMHMM.gff3
// Container: quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.10.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS {
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
    .bm_deps <- c("IsoformSwitchAnalyzeR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(IsoformSwitchAnalyzeR)
    
    # 1. Import isoform expression data
    salmonQuant <- importIsoformExpression(
        parentDir = "salmon_quant_dir",
        addIsofomIdAsColumn = TRUE
    )
    
    # 2. Create a design matrix
    myDesign <- data.frame(
        sampleID = colnames(salmonQuant\$abundance)[-1],
        condition = gsub('_.*', '', colnames(salmonQuant\$abundance)[-1])
    )
    
    # 3. Build the switchAnalyzeRlist
    aSwitchList <- importRdata(
        isoformCountMatrix   = salmonQuant\$counts,
        isoformRepExpression = salmonQuant\$abundance,
        designMatrix         = myDesign,
        isoformExonAnnoation = "annotation.gtf",
        isoformNtFasta       = "transcript_sequences.fasta",
        showProgress = FALSE
    )
    
    # 4. Filter out lowly expressed features
    exampleSwitchListFiltered <- preFilter(
        switchAnalyzeRlist = aSwitchList,
        isoCount = 10,
        min.Count.prop = 0.7,
        IFcutoff = 0.1,
        min.IF.prop = 0.5,
        removeSingleIsoformGenes = TRUE
    )
    
    # 5. Test for differential transcript usage
    exampleSwitchListAnalyzed <- isoformSwitchTestDEXSeq(
        switchAnalyzeRlist = exampleSwitchListFiltered,
        reduceToSwitchingGenes=TRUE
    )
    
    # 6. Extract nucleotide and amino acid sequences
    exampleSwitchListAnalyzed <- extractSequence(
        exampleSwitchListAnalyzed, 
        pathToOutput = getwd(),
        writeToFile=TRUE 
    )
    
    # 7. Import external sequence analysis results
    exampleSwitchListAnalyzed <- analyzeCPAT(
        switchAnalyzeRlist   = exampleSwitchListAnalyzed,
        pathToCPATresultFile = "cpat_results.txt",
        codingCutoff         = 0.725, 
        removeNoncodinORFs   = TRUE   
    )
    
    exampleSwitchListAnalyzed <- analyzeCPC2(
        switchAnalyzeRlist   = exampleSwitchListAnalyzed,
        pathToCPC2resultFile = "cpc2_result.txt",
        removeNoncodinORFs   = TRUE   
    )
    
    exampleSwitchListAnalyzed <- analyzePFAM(
        switchAnalyzeRlist   = exampleSwitchListAnalyzed,
        pathToPFAMresultFile = "pfam_results.txt",
        showProgress=FALSE
    )
    
    exampleSwitchListAnalyzed <- analyzeSignalP(
        switchAnalyzeRlist       = exampleSwitchListAnalyzed,
        pathToSignalPresultFile  = "signalP_results.txt"
    )
    
    exampleSwitchListAnalyzed <- analyzeIUPred2A(
        switchAnalyzeRlist        = exampleSwitchListAnalyzed,
        pathToIUPred2AresultFile = "iupred2a_result.txt.gz",
        showProgress = FALSE
    )
    
    exampleSwitchListAnalyzed <- analyzeNetSurfP3(
        switchAnalyzeRlist = exampleSwitchListAnalyzed,
        pathToNetSurfP3resultFile = "netsurfp3_result.csv.gz",
        showProgress = FALSE
    )
    
    exampleSwitchListAnalyzed <- analyzeDeepLoc2(
        switchAnalyzeRlist = exampleSwitchListAnalyzed,
        pathToDeepLoc2resultFile = "deeploc2.csv",
        quiet = FALSE
    )
    
    exampleSwitchListAnalyzed <- analyzeDeepTMHMM(
        switchAnalyzeRlist   = exampleSwitchListAnalyzed,
        pathToDeepTMHMMresultFile = "DeepTMHMM.gff3",
        showProgress=FALSE
    )
    
    # 8. Analyze alternative splicing
    exampleSwitchListAnalyzed <- analyzeAlternativeSplicing(
        switchAnalyzeRlist = exampleSwitchListAnalyzed,
        quiet=TRUE
    )
    
    # 9. Predict functional consequences
    consequencesOfInterest <- c('intron_retention','coding_potential','NMD_status','domains_identified','ORF_seq_similarity')
    exampleSwitchListAnalyzed <- analyzeSwitchConsequences(
        exampleSwitchListAnalyzed,
        consequencesToAnalyze = consequencesOfInterest, 
        dIFcutoff = 0.4, 
        showProgress=FALSE
    )
    
    # Save final switchAnalyzeRlist object
    saveRDS(exampleSwitchListAnalyzed, file = "isoform_switch_results.rds")
    
    # Extract and save top switches
    top_switches <- extractTopSwitches(
        exampleSwitchListAnalyzed,
        filterForConsequences = TRUE,
        n = Inf
    )
    write.csv(top_switches, file = "top_isoform_switches.csv", row.names = FALSE)
    
    # Extract and save switch summary
    switch_summary <- extractSwitchSummary(exampleSwitchListAnalyzed)
    write.csv(switch_summary, file = "isoform_switch_summary.csv", row.names = FALSE)
    
    # Generate and save plots for top switches
    pdf("isoform_switch_plots.pdf", onefile = TRUE, width = 9, height = 6)
    if (nrow(top_switches) > 0) {
        for (i in seq_len(min(10, nrow(top_switches)))) {
            tryCatch({
                switchPlot(
                    exampleSwitchListAnalyzed,
                    gene = top_switches\$gene_name[i],
                    condition1 = top_switches\$condition_1[i],
                    condition2 = top_switches\$condition_2[i]
                )
            }, error = function(e) {
                message("Could not plot gene: ", top_switches\$gene_name[i])
            })
        }
    }
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS":
        isoformswitchanalyzer: \$(Rscript -e 'cat(as.character(packageVersion("isoformswitchanalyzer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detailed_custom_analysis.csv versions.yml
    """
}

workflow BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ salmon_quant_dir, annotation.gtf, transcript_sequences.fasta, cpat_results.txt, cpc2_result.txt, pfam_results.txt, signalP_results.txt, iupred2a_result.txt.gz, netsurfp3_result.csv.gz, deeploc2.csv, DeepTMHMM.gff3 ] ]

    main:
    BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS.out.tables
    plots    = BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS.out.plots
    objects  = BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS.out.objects
    versions = BIOC_ISOFORMSWITCHANALYZER_DETAILED_CUSTOM_ANALYSIS.out.versions
}
