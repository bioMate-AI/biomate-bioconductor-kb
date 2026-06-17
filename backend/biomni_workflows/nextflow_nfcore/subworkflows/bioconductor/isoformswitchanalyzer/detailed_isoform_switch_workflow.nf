#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IsoformSwitchAnalyzeR — detailed_isoform_switch_workflow
// Perform a fully customized step-by-step isoform switch analysis using individual functions for filtering, testing, sequence extraction, external tool integratio
// Input: switchAnalyzeRlist, external_results
// Container: quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.10.0--r45h01b2380_0
// R packages: IsoformSwitchAnalyzeR
// Bioconductor: 3.20 | R: 4.4
// Requires: IsoformSwitchAnalyzeR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out lowly expressed features
//  * 2. [Core Analysis] Perform statistical testing for differential transcript usage
//  * 3. [Core Analysis] Extract nucleotide and amino acid sequences
//  * 4. [Input & Preparation] Import and integrate external sequence analysis results
//  * 5. [Core Analysis] Analyze alternative splicing events
//  * 6. [Core Analysis] Predict functional consequences of isoform switches

nextflow.enable.dsl = 2

process BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
            
            # Load required library
            library(IsoformSwitchAnalyzeR)
            
            # ==========================================
            # 0. Load User Input Files
            # ==========================================
            # The pipeline expects 'switchAnalyzeRlist.rds' and the external tool result files
            # to be present in the current working directory.
            
            rds_path <- "switchAnalyzeRlist.rds"
            if (!file.exists(rds_path)) {
                stop(paste("Error: Input file '", rds_path, "' not found in the working directory.", sep=""))
            }
            
            # Read the pre-existing switchAnalyzeRlist object
            switchAnalyzeRlist <- readRDS(rds_path)
            
            # Define paths to external results files
            cpat_file      <- "cpat_results.txt"
            cpc2_file      <- "cpc2_result.txt"
            pfam_file      <- "pfam_results.txt"
            signalp_file   <- "signalP_results.txt"
            iupred2a_file  <- "iupred2a_result.txt.gz"
            netsurfp3_file <- "netsurfp3_result.csv.gz"
            deeploc2_file  <- "deeploc2.csv"
            deeptmhmm_file <- "DeepTMHMM.gff3"
            
            # ==========================================
            # 1. Filter out lowly expressed features
            # ==========================================
            message("Step 1: Filtering lowly expressed features...")
            exampleSwitchListFiltered <- preFilter(
                switchAnalyzeRlist = switchAnalyzeRlist,
                IFcutoff = 0.1,
                removeSingleIsoformGenes = TRUE
            )
            
            # ==========================================
            # 2. Perform statistical testing for DTU
            # ==========================================
            message("Step 2: Testing for isoform switches via DEXSeq...")
            exampleSwitchListAnalyzed <- isoformSwitchTestDEXSeq(
                switchAnalyzeRlist = exampleSwitchListFiltered,
                reduceToSwitchingGenes = TRUE
            )
            
            # ==========================================
            # 3. Extract nucleotide and amino acid sequences
            # ==========================================
            message("Step 3: Extracting sequences...")
            
            exampleSwitchListAnalyzed <- analyzeORF(
                exampleSwitchListAnalyzed
            )
            
            # We set writeToFile=FALSE as documented, but specify a path for output if needed.
            exampleSwitchListAnalyzed <- extractSequence(
                exampleSwitchListAnalyzed, 
                pathToOutput = "extracted_sequences",
                writeToFile = FALSE,
                addToSwitchAnalyzeRlist = TRUE
            )
            
            # ==========================================
            # 4. Import and integrate external sequence analysis results
            # ==========================================
            message("Step 4: Integrating external sequence analysis results...")
            
            # CPAT
            if (file.exists(cpat_file)) {
                message("Integrating CPAT results...")
                exampleSwitchListAnalyzed <- analyzeCPAT(
                    switchAnalyzeRlist   = exampleSwitchListAnalyzed,
                    pathToCPATresultFile = cpat_file,
                    codingCutoff         = 0.725,
                    removeNoncodinORFs   = TRUE
                )
            } else {
                warning("CPAT result file not found. Skipping CPAT integration.")
            }
            
            # CPC2
            if (file.exists(cpc2_file)) {
                message("Integrating CPC2 results...")
                exampleSwitchListAnalyzed <- analyzeCPC2(
                    switchAnalyzeRlist   = exampleSwitchListAnalyzed,
                    pathToCPC2resultFile = cpc2_file,
                    removeNoncodinORFs   = TRUE
                )
            } else {
                warning("CPC2 result file not found. Skipping CPC2 integration.")
            }
            
            # PFAM
            if (file.exists(pfam_file)) {
                message("Integrating PFAM results...")
                exampleSwitchListAnalyzed <- analyzePFAM(
                    switchAnalyzeRlist   = exampleSwitchListAnalyzed,
                    pathToPFAMresultFile = pfam_file,
                    showProgress = FALSE
                )
            } else {
                warning("PFAM result file not found. Skipping PFAM integration.")
            }
            
            # SignalP
            if (file.exists(signalp_file)) {
                message("Integrating SignalP results...")
                exampleSwitchListAnalyzed <- analyzeSignalP(
                    switchAnalyzeRlist       = exampleSwitchListAnalyzed,
                    pathToSignalPresultFile  = signalp_file
                )
            } else {
                warning("SignalP result file not found. Skipping SignalP integration.")
            }
            
            # IUPred2A
            if (file.exists(iupred2a_file)) {
                message("Integrating IUPred2A results...")
                exampleSwitchListAnalyzed <- analyzeIUPred2A(
                    switchAnalyzeRlist        = exampleSwitchListAnalyzed,
                    pathToIUPred2AresultFile = iupred2a_file,
                    showProgress = FALSE
                )
            } else {
                warning("IUPred2A result file not found. Skipping IUPred2A integration.")
            }
            
            # NetSurfP3
            if (file.exists(netsurfp3_file)) {
                message("Integrating NetSurfP3 results...")
                exampleSwitchListAnalyzed <- analyzeNetSurfP3(
                    switchAnalyzeRlist = exampleSwitchListAnalyzed,
                    pathToNetSurfP3resultFile = netsurfp3_file,
                    showProgress = FALSE
                )
            } else {
                warning("NetSurfP3 result file not found. Skipping NetSurfP3 integration.")
            }
            
            # DeepLoc2
            if (file.exists(deeploc2_file)) {
                message("Integrating DeepLoc2 results...")
                exampleSwitchListAnalyzed <- analyzeDeepLoc2(
                    switchAnalyzeRlist = exampleSwitchListAnalyzed,
                    pathToDeepLoc2resultFile = deeploc2_file,
                    quiet = FALSE
                )
            } else {
                warning("DeepLoc2 result file not found. Skipping DeepLoc2 integration.")
            }
            
            # DeepTMHMM
            if (file.exists(deeptmhmm_file)) {
                message("Integrating DeepTMHMM results...")
                exampleSwitchListAnalyzed <- analyzeDeepTMHMM(
                    switchAnalyzeRlist   = exampleSwitchListAnalyzed,
                    pathToDeepTMHMMresultFile = deeptmhmm_file,
                    showProgress = FALSE
                )
            } else {
                warning("DeepTMHMM result file not found. Skipping DeepTMHMM integration.")
            }
            
            # ==========================================
            # 5. Analyze alternative splicing events
            # ==========================================
            message("Step 5: Analyzing alternative splicing...")
            exampleSwitchListAnalyzed <- analyzeAlternativeSplicing(
                switchAnalyzeRlist = exampleSwitchListAnalyzed,
                quiet = TRUE
            )
            
            # ==========================================
            # 6. Predict functional consequences of isoform switches
            # ==========================================
            message("Step 6: Predicting functional consequences...")
            consequencesOfInterest <- c(
                "intron_retention",
                "coding_potential",
                "domains_identified",
                "signal_peptide_identified",
                "disorder_identified",
                "subcellular_localization"
            )
            
            exampleSwitchListAnalyzed <- analyzeSwitchConsequences(
                exampleSwitchListAnalyzed,
                consequencesToAnalyze = consequencesOfInterest, 
                dIFcutoff = 0.4,
                showProgress = FALSE
            )
            
            # ==========================================
            # 7. Export Meaningful Results
            # ==========================================
            message("Step 7: Exporting results...")
            
            # Save the final analyzed switchAnalyzeRlist object
            saveRDS(exampleSwitchListAnalyzed, "isoform_switch_analyzed.rds")
            
            # Extract and save switch summary
            tryCatch({
                switch_summary <- extractSwitchSummary(exampleSwitchListAnalyzed)
                write.csv(switch_summary, "switch_summary.csv", row.names = FALSE)
            }, error = function(e) {
                warning("Could not extract switch summary: ", e\$message)
            })
            
            # Extract and save top switches
            tryCatch({
                top_switches <- extractTopSwitches(exampleSwitchListAnalyzed, n = 100)
                write.csv(top_switches, "top_switches.csv", row.names = FALSE)
            }, error = function(e) {
                warning("Could not extract top switches: ", e\$message)
            })
            
            # Extract and save consequence summary
            tryCatch({
                consequence_summary <- extractConsequenceSummary(exampleSwitchListAnalyzed, returnResult = TRUE)
                if (!is.null(consequence_summary)) {
                    write.csv(consequence_summary, "consequence_summary.csv", row.names = FALSE)
                }
            }, error = function(e) {
                warning("Could not extract consequence summary: ", e\$message)
            })
            
            # Extract and save splicing summary
            tryCatch({
                splicing_summary <- extractSplicingSummary(exampleSwitchListAnalyzed, returnResult = TRUE)
                if (!is.null(splicing_summary)) {
                    write.csv(splicing_summary, "splicing_summary.csv", row.names = FALSE)
                }
            }, error = function(e) {
                warning("Could not extract splicing summary: ", e\$message)
            })
            
            message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW":',
        paste0('    IsoformSwitchAnalyzeR: ', as.character(packageVersion('IsoformSwitchAnalyzeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detailed_isoform_switch_workflow.csv versions.yml
    """
}

workflow BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ switchAnalyzeRlist, external_results ] ]

    main:
    BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW.out.tables
    plots    = BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW.out.plots
    objects  = BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW.out.objects
    versions = BIOC_ISOFORMSWITCHANALYZER_DETAILED_ISOFORM_SWITCH_WORKFLOW.out.versions
}
