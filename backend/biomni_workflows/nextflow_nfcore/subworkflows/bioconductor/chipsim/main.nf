#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipsim — nucleosome_positioning_simulation
// Simulate nucleosome positioning ChIP-seq data using default parameters and a reference genome.
// Input: genome.fasta
// Container: quay.io/biocontainers/bioconductor-chipsim:1.64.0--r45hdfd78af_0
// R packages: Biostrings, ChIPsim
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipsim:1.64.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "ChIPsim")
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
    
    # --- Initialize random seed and load reference genome ---
    library(ChIPsim)
    library(Biostrings)
    
    set.seed(1)
    
    # Read the reference genome from the user-provided FASTA file
    if (!file.exists("genome.fasta")) {
      stop("Error: 'genome.fasta' not found in the working directory.")
    }
    genome <- readDNAStringSet("genome.fasta")
    
    # --- Define custom read sequence and quality generation ---
    randomQuality <- function(read, ...){
    	paste(sample(unlist(strsplit(rawToChar(as.raw(64:104)),"")), 
    					nchar(read), replace = TRUE), collapse="")
    }
    
    dfReads <- function(readPos, readNames, sequence, readLen, ...){
    	readSeq <- character(sum(sapply(readPos, sapply, length)))
    	readQual <- character(sum(sapply(readPos, sapply, length)))
    	idx <- 1
    	for(k in length(readPos)){
    		for(i in 1:2){
    			for(j in 1:length(readPos[[k]][[i]])){
    				readSeq[idx] <- as.character(readSequence(readPos[[k]][[i]][j], sequence[[k]], 
    						strand=ifelse(i==1, 1, -1), readLen=readLen))
    				readQual[idx] <- randomQuality(readSeq[idx])
    				readSeq[idx] <- readError(readSeq[idx], decodeQuality(readQual[idx]))
    				idx <- idx + 1
    			}
    		}
    	}
    	data.frame(name=unlist(readNames), sequence=readSeq, quality=readQual, 
    			stringsAsFactors = FALSE)
    }
    
    # --- Retrieve default simulation functions and customize the ---
    myFunctions <- defaultFunctions()
    myFunctions\$readSequence <- dfReads 
    
    # --- Run the simulation using simChIP with customized control ---
    nReads <- 1000
    simulated <- simChIP(nReads, genome, file = "", functions = myFunctions,
    		control = defaultControl(readDensity=list(meanLength = 150)))
    
    # --- Write named output files for the meaningful results ---
    # Save the complete simulated object
    saveRDS(simulated, file = "simulated_nucleosomes.rds")
    
    # Save the simulated reads as a CSV table
    write.csv(simulated\$readSequence, file = "simulated_reads.csv", row.names = FALSE)
    
    # Generate and save the density plot
    pdf("nucleosome_density_plot.pdf", width = 8, height = 6)
    tryCatch({
      feat <- simulated\$features[[1]]
      stableIdx <- which(sapply(feat, inherits, "StableFeature"))
      if (length(stableIdx) > 0) {
        start <- feat[[stableIdx[1]]]\$start
        plot_range <- (start - 2000):(start + 500)
        # Ensure indices are within bounds of the density vector
        plot_range <- plot_range[plot_range > 0 & plot_range <= length(simulated\$bindDensity[[1]])]
        
        plot(plot_range, simulated\$bindDensity[[1]][plot_range], xlab = "Chromosome 1",
             ylab = "Density", type = 'l', main = "Nucleosome and Read Densities")
        lines(plot_range, simulated\$readDensity[[1]][plot_range, 1], col = 4)
        lines(plot_range, simulated\$readDensity[[1]][plot_range, 2], col = 2)
        legend("topright", legend = c("Nucleosome density", "Read density (+)", "Read density (-)"), 
               col = c(1, 4, 2), lwd = 1)
      } else {
        # Fallback plot if no StableFeature is found
        plot(simulated\$bindDensity[[1]][1:min(5000, length(simulated\$bindDensity[[1]]))], 
             type = 'l', xlab = "Position", ylab = "Density", main = "Nucleosome Density (First 5kb)")
      }
    }, error = function(e) {
      warning("Could not generate density plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION":',
        paste0('        chipsim: ', as.character(packageVersion("chipsim")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucleosome_positioning_simulation.csv versions.yml
    """
}

workflow BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fasta ] ]

    main:
    BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION(ch_input)

    emit:
    tables   = BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION.out.tables
    plots    = BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION.out.plots
    objects  = BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION.out.objects
    versions = BIOC_CHIPSIM_NUCLEOSOME_POSITIONING_SIMULATION.out.versions
}
