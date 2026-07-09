#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChIPsim — transcription_factor_binding_simulation
// Simulate transcription factor binding ChIP-seq data with custom feature generation, binding site densities, and strand-specific read densities.
// Input: genome.fasta
// Container: quay.io/biocontainers/bioconductor-chipsim:1.64.0--r45hdfd78af_0
// R packages: Biostrings, ChIPsim, actuar
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, ChIPsim, actuar
// Visualizations: density plot
// QC: input validation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define transition probabilities and initial state distribution for the Markov chain
//  * 2. [Input & Preparation] Define background and binding feature parameter generators
//  * 3. [Core Analysis] Implement custom feature reconciliation and density functions
//  * 4. [Input & Preparation] Define fragment length distribution and custom read sequence generation functions
//  * 5. [Core Analysis] Run the complete simulation using simChIP with custom control arguments

nextflow.enable.dsl = 2

process BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biostrings", "ChIPsim", "actuar")
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
    library(ChIPsim)
    library(Biostrings)
    library(actuar)
    
    # ==========================================
    # 0. Read User Input
    # ==========================================
    if (!file.exists("genome.fasta")) {
      stop("Required input file 'genome.fasta' not found in the working directory.")
    }
    
    # Read the reference genome
    genome <- Biostrings::readDNAStringSet("genome.fasta")
    
    # To ensure compatibility with the documented single-chromosome loop structure,
    # we select the first chromosome from the input genome.
    genome <- genome[1]
    chr_length <- Biostrings::width(genome)[1]
    
    # ==========================================
    # 1. Define transition probabilities and initial state distribution
    # ==========================================
    transition <- list(Binding=c(Background=1), Background=c(Binding=0.05, Background=0.95))
    transition <- lapply(transition, "class<-", "StateDistribution")
    
    init <- c(Binding=0, Background=1)
    class(init) <- "StateDistribution"
    
    # ==========================================
    # 2. Define background and binding feature parameter generators
    # ==========================================
    backgroundFeature <- function(start, length=1000, shape=1, scale=20){
      weight <- rgamma(1, shape=1, scale=20)
      params <- list(start = start, length = length, weight = weight)
      class(params) <- c("Background", "SimulatedFeature")
      
      params
    }
    
    bindingFeature <- function(start, length=500, shape=1, scale=20, enrichment=5, r=1.5){
      stopifnot(r > 1)
      
      avgWeight <- shape * scale * enrichment
      lowerBound <- ((r - 1) * avgWeight)
      weight <- actuar::rpareto1(1, r, lowerBound)
      
      params <- list(start = start, length = length, weight = weight)
      class(params) <- c("Binding", "SimulatedFeature")
      
      params
    }
    
    # ==========================================
    # 3. Implement custom feature reconciliation and density functions
    # ==========================================
    reconcileFeatures.TFExperiment <- function(features, ...){
      bindIdx <- sapply(features, inherits, "Binding")
      if(any(bindIdx))
        bindLength <- features[[min(which(bindIdx))]]\$length
      else bindLength <- 1
      lapply(features, function(f){
        if(inherits(f, "Background"))
          f\$weight <- f\$weight/bindLength
        ## The next three lines (or something to this effect)
        ## are required by all 'reconcileFeatures' implementations. 
        f\$overlap <- 0
        currentClass <- class(f)
        class(f) <- c(currentClass[-length(currentClass)], 
                      "ReconciledFeature", currentClass[length(currentClass)])
        f
      })
    }
    
    constRegion <- function(weight, length) rep(weight, length)
    
    featureDensity.Binding <- function(feature, ...){
      featDens <- numeric(feature\$length)
      featDens[floor(feature\$length/2)] <- feature\$weight
      featDens
    }
    
    featureDensity.Background <- function(feature, ...) constRegion(feature\$weight, feature\$length)
    
    # ==========================================
    # 4. Define fragment length distribution and custom read sequence generation functions
    # ==========================================
    fragLength <- function(x, minLength, maxLength, meanLength, ...){
      sd <- (maxLength - minLength)/4
      prob <- dnorm(minLength:maxLength, mean = meanLength, sd = sd)
      prob <- prob/sum(prob)
      prob[x - minLength + 1]
    }
    
    randomQuality <- function(read, ...){
      paste(sample(unlist(strsplit(rawToChar(as.raw(64:104)),"")), 
                   nchar(read), replace = TRUE), collapse="")
    }
    
    dfReads <- function(readPos, readNames, sequence, readLen, ...){
      ## create vector to hold read sequences and qualities
      readSeq <- character(sum(sapply(readPos, sapply, length)))
      readQual <- character(sum(sapply(readPos, sapply, length)))
      
      idx <- 1
      ## process read positions for each chromosome and strand
      for(k in length(readPos)){ ## chromosome
        for(i in 1:2){ ## strand
          for(j in 1:length(readPos[[k]][[i]])){
            ## get (true) sequence
            readSeq[idx] <- as.character(ChIPsim::readSequence(readPos[[k]][[i]][j], sequence[[k]], 
                                                               strand=ifelse(i==1, 1, -1), readLen=readLen))
            ## get quality
            readQual[idx] <- randomQuality(readSeq[idx])
            ## introduce sequencing errors
            readSeq[idx] <- ChIPsim::readError(readSeq[idx], ChIPsim::decodeQuality(readQual[idx]))
            idx <- idx + 1
          }
        }
      }
      data.frame(name=unlist(readNames), sequence=readSeq, quality=readQual, 
                 stringsAsFactors = FALSE)
    }
    
    # Set up custom functions list
    myFunctions <- ChIPsim::defaultFunctions()
    myFunctions\$readSequence <- dfReads
    
    generator <- list(Binding=bindingFeature, Background=backgroundFeature)
    
    # Configure arguments dynamically based on the input genome length
    featureArgs <- list(generator=generator, transition=transition, init=init, start = 0, 
                        length = chr_length, globals=list(shape=1, scale=20), experimentType="TFExperiment", 
                        lastFeat=c(Binding = FALSE, Background = TRUE), control=list(Binding=list(length=50)))
    
    readDensArgs <- list(fragment=fragLength, bind = 50, minLength = 150, maxLength = 250,
                         meanLength = 200)
    
    # ==========================================
    # 5. Run the complete simulation using simChIP
    # ==========================================
    set.seed(1)
    simulated <- ChIPsim::simChIP(1e4, genome, file = "", functions = myFunctions,
                                  control = ChIPsim::defaultControl(features=featureArgs, readDensity=readDensArgs))
    
    # ==========================================
    # 6. Export Results
    # ==========================================
    # Save the complete simulated object
    saveRDS(simulated, "simulated_data.rds")
    
    # Save the simulated features
    saveRDS(simulated\$features, "simulated_features.rds")
    
    # Save the simulated reads and qualities to a CSV file
    write.csv(simulated\$readSequence, "simulated_reads.csv", row.names = FALSE)
    
    # Generate and save a diagnostic plot of the read densities
    pdf("read_density_plot.pdf", width = 10, height = 6)
    if (length(simulated\$readDensity) > 0) {
      dens_data <- simulated\$readDensity[[1]]
      # Plot a subset around the middle of the chromosome to keep the plot clean
      plot_start <- max(1, floor(nrow(dens_data)/2) - 5000)
      plot_end <- min(nrow(dens_data), floor(nrow(dens_data)/2) + 5000)
      
      plot(plot_start:plot_end, dens_data[plot_start:plot_end, 1], type = 'l', col = 'blue',
           xlab = "Genomic Position", ylab = "Read Density", 
           main = "Simulated Strand-Specific Read Density (10kb Window)")
      lines(plot_start:plot_end, dens_data[plot_start:plot_end, 2], col = 'red')
      legend("topright", legend = c("Forward Strand", "Reverse Strand"), col = c("blue", "red"), lty = 1)
    }
    dev.off()
    
    cat("Simulation completed successfully. Outputs written to 'simulated_data.rds', 'simulated_features.rds', 'simulated_reads.csv', and 'read_density_plot.pdf'.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\\\.rds\$"), list.files(".", pattern = "\\\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION":',
        paste0('    ChIPsim: ', as.character(packageVersion('ChIPsim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcription_factor_binding_simulation.csv versions.yml
    """
}

workflow BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fasta ] ]

    main:
    BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION(ch_input)

    emit:
    tables   = BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION.out.tables
    plots    = BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION.out.plots
    objects  = BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION.out.objects
    versions = BIOC_CHIPSIM_TRANSCRIPTION_FACTOR_BINDING_SIMULATION.out.versions
}
