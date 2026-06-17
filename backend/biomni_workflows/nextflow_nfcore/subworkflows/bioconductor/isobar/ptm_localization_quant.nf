#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isobar — ptm_localization_quant
// Filter and quantify post-translational modifications (PTMs) using PhosphoRS localization probabilities and estimate modified peptide ratios.
// Input: identifications.id.csv, peaklist.mgf
// Container: quay.io/biocontainers/bioconductor-isobar:1.56.0--r45hdfd78af_0
// R packages: distr, ggplot2, isobar
// Bioconductor: 3.20 | R: 4.4
// Requires: distr, ggplot2, isobar
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate PhosphoRS XML input using writePhosphoRSInput
//  * 2. [Visualization & Output] Read PhosphoRS XML output using readPhosphoRSOutput or run PhosphoRS directly using getPhosphoRSProbabilities
//  * 3. [Input & Preparation] Read and filter spectra during import using readIBSpectra with filterSpectraDeltaScore or filterSpectraPhosphoRS
//  * 4. [Core Analysis] Estimate ratios for specific modified peptides using estimateRatio
//  * 5. [Core Analysis] Retrieve PTM annotation information using getPtmInfoFromPhosphoSitePlus or getPtmInfoFromNextprot

nextflow.enable.dsl = 2

process BIOC_ISOBAR_PTM_LOCALIZATION_QUANT {
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
    .bm_deps <- c("distr", "ggplot2", "isobar")
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
            library(isobar)
            library(ggplot2)
            library(distr)
            
            # Verify that the required user input files exist in the working directory
            if (!file.exists("identifications.id.csv") || !file.exists("peaklist.mgf")) {
              stop("Required input files 'identifications.id.csv' and/or 'peaklist.mgf' are missing from the working directory.")
            }
            
            # Allow user to specify spectra type via command line, default to iTRAQ4plexSpectra
            args <- commandArgs(trailingOnly = TRUE)
            spectra_type <- if (length(args) > 0) args[1] else "iTRAQ4plexSpectra"
            
            # ==========================================
            # STAGE 1: Generate PhosphoRS XML input
            # ==========================================
            message("Stage 1: Generating PhosphoRS XML input...")
            writePhosphoRSInput("phosphors.in.xml",
                                "identifications.id.csv","peaklist.mgf",
                                 massTolerance=0.5,activationType="CID")
            
            # ==========================================
            # STAGE 2: Read PhosphoRS XML output or run PhosphoRS directly
            # ==========================================
            message("Stage 2: Reading PhosphoRS XML output / running PhosphoRS...")
            if (file.exists("phosphors.out.xml")) {
              phosphors_out <- readPhosphoRSOutput("phosphors.out.xml",simplify=TRUE,besthit.only=TRUE)
              write.csv(phosphors_out, file="phosphors_out.csv", row.names=FALSE)
            }
            
            if (file.exists("phosphoRS.jar")) {
              phosphors_prob <- getPhosphoRSProbabilities("identifications.id.csv","peaklist.mgf",
                                          massTolerance=0.5,activationType="CID",
                                          phosphors.cmd="java -jar phosphoRS.jar")
              write.csv(phosphors_prob, file="phosphors_prob.csv", row.names=FALSE)
            }
            
            # ==========================================
            # STAGE 3: Read and filter spectra during import
            # ==========================================
            message("Stage 3: Reading and filtering spectra during import...")
            ib <- readIBSpectra(type=spectra_type, "identifications.id.csv","peaklist.mgf",
                                  annotate.spectra.f=function(...) 
                                    filterSpectraDeltaScore(...,min.delta.score=10))
            
            if (file.exists("PhosphoRS.jar")) {
              ib <- readIBSpectra(type=spectra_type, "identifications.id.csv","peaklist.mgf",
                                    annotate.spectra.f=
                                      function(...) filterSpectraPhosphoRS(...,min.prob=0.9,
                                         phosphors.cmd="java -jar PhosphoRS.jar"))
            }
            
            # Construct the main ib_phospho and noise.model.hcd objects from user input
            message("Constructing ib_phospho and noise.model.hcd from user input...")
            ib_phospho <- ib
            noise.model.hcd <- NoiseModel(ib_phospho)
            
            # ==========================================
            # STAGE 4: Estimate ratios for specific modified peptides
            # ==========================================
            message("Stage 4: Estimating ratios for specific modified peptides...")
            
            # Extract channel names dynamically to avoid hardcoding
            channels <- colnames(assayData(ib_phospho)[["mass"]])
            if (is.null(channels) || length(channels) < 2) {
              channels <- names(reporterTagMasses(ib_phospho))
            }
            ch1 <- channels[1]
            ch2 <- channels[2]
            
            # Run the exact documented call for a specific peptide
            if ("peptide" %in% colnames(fData(ib_phospho)) && nrow(fData(ib_phospho)) > 0) {
              peptide_to_test <- as.character(fData(ib_phospho)\$peptide[1])
              ratio1 <- 10^estimateRatio(ib_phospho,noise.model.hcd,peptide=peptide_to_test)
            } else {
              ratio1 <- NULL
            }
            
            # Extract pep.n.modif from the constructed ib_phospho object
            if (all(c("peptide", "modif") %in% colnames(fData(ib_phospho))) && nrow(fData(ib_phospho)) > 0) {
              pep.n.modif <- as.matrix(unique(fData(ib_phospho)[,c("peptide","modif")]))
            } else {
              pep.n.modif <- NULL
            }
            
            # Fallback if pep.n.modif is empty or modif column is missing
            if (is.null(pep.n.modif) || length(pep.n.modif) == 0) {
              if ("peptide" %in% colnames(fData(ib_phospho)) && nrow(fData(ib_phospho)) > 0) {
                all_peptides <- unique(as.character(fData(ib_phospho)\$peptide))
                pep.n.modif <- data.frame(
                  peptide = head(all_peptides, 5),
                  modif = rep("PHOS", min(5, length(all_peptides)))
                )
                pep.n.modif <- as.matrix(pep.n.modif)
              } else {
                pep.n.modif <- NULL
              }
            }
            
            # Run the exact documented call for multiple peptides
            if (!is.null(pep.n.modif) && length(pep.n.modif) > 0) {
              ratio2 <- estimateRatio(ib_phospho,noise.model.hcd,channel1=ch1,channel2=ch2,
                                peptide=head(pep.n.modif),combine=FALSE)[,c("lratio","variance",
                                                                            "n.spectra","p.value.rat")]
            } else {
              ratio2 <- NULL
            }
            
            # ==========================================
            # STAGE 5: Retrieve PTM annotation information
            # ==========================================
            message("Stage 5: Retrieving PTM annotation information...")
            ptm.info.psp <- getPtmInfoFromPhosphoSitePlus(proteinGroup(ib_phospho),modif="PHOS")
            
            ptm.info.np <- getPtmInfoFromNextprot(proteinGroup(ib_phospho))
            
            # ==========================================
            # WRITE OUTPUTS
            # ==========================================
            message("Writing output files...")
            
            # Save RDS objects
            saveRDS(ib_phospho, file = "ib_phospho.rds")
            saveRDS(noise.model.hcd, file = "noise_model_hcd.rds")
            
            # Save CSV tables
            if (!is.null(ratio2)) {
              write.csv(as.data.frame(ratio2), file = "estimated_ratios.csv", row.names = TRUE)
            }
            if (!is.null(ptm.info.psp)) {
              write.csv(as.data.frame(ptm.info.psp), file = "ptm_info_phosphositeplus.csv", row.names = FALSE)
            }
            if (!is.null(ptm.info.np)) {
              write.csv(as.data.frame(ptm.info.np), file = "ptm_info_nextprot.csv", row.names = FALSE)
            }
            
            # Generate and save PDF plot
            pdf("isobar_ptm_plots.pdf", width = 7, height = 7)
            maplot(ib_phospho, noise.model = noise.model.hcd, channel1 = ch1, channel2 = ch2,
                   main = "95% CI Noise Model Maplot")
            dev.off()
            
            message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ISOBAR_PTM_LOCALIZATION_QUANT":',
        paste0('    isobar: ', as.character(packageVersion('isobar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ptm_localization_quant.csv versions.yml
    """
}

workflow BIOC_ISOBAR_PTM_LOCALIZATION_QUANT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ identifications.id.csv, peaklist.mgf ] ]

    main:
    BIOC_ISOBAR_PTM_LOCALIZATION_QUANT(ch_input)

    emit:
    tables   = BIOC_ISOBAR_PTM_LOCALIZATION_QUANT.out.tables
    plots    = BIOC_ISOBAR_PTM_LOCALIZATION_QUANT.out.plots
    objects  = BIOC_ISOBAR_PTM_LOCALIZATION_QUANT.out.objects
    versions = BIOC_ISOBAR_PTM_LOCALIZATION_QUANT.out.versions
}
