#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BRAIN — high_throughput_protein_processing
// Process a tabular file of protein sequences to calculate atomic compositions, monoisotopic masses, and most abundant peak masses in high-throughput.
// Input: uniprot.tab
// Container: quay.io/biocontainers/bioconductor-brain:1.56.0--r45hdfd78af_0
// R packages: BRAIN
// Bioconductor: 3.20 | R: 4.4
// Requires: BRAIN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and clean the protein sequence data
//  * 2. [Core Analysis] Filter sequences to ensure they only contain the 20 standard amino acids
//  * 3. [Core Analysis] Convert amino acid sequences to atomic compositions
//  * 4. [Core Analysis] Calculate isotopic distributions and extract monoisotopic and most abundant peak masses
//  * 5. [Visualization & Output] Export the processed data to a text file

nextflow.enable.dsl = 2

process BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("BRAIN")
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
    library(BRAIN)
    
    # 1. Read and clean the protein sequence data
    # The pipeline reads 'uniprot.tab' from the working directory
    tabUniprot <- read.table('uniprot.tab', sep="\t", header=TRUE, stringsAsFactors=FALSE) 
    tabUniprot\$Sequence <- gsub(" ", "", tabUniprot\$Sequence)
    howMany <- nrow(tabUniprot)
    
    # Define standard amino acids
    AMINOS <- c("A", "R", "N", "D", "C", "E", "Q", "G", "H", "I", "L", "K", "M", "F", "P", "S", "T", "W", "Y", "V")
    nrPeaks = 1000
    dfUniprot <- data.frame()
    
    # 2. Filter, convert, and calculate isotopic distributions in high-throughput
    for (idx in 1:howMany){
      seq <- as.character(tabUniprot[idx,"Sequence"])
      seqVector <- strsplit(seq, split="")[[1]]
      
      # Filter sequences to ensure they only contain the 20 standard amino acids
      if (!is.na(sum(match(seqVector, AMINOS)))){  
        # Convert amino acid sequences to atomic compositions
        aC <- getAtomsFromSeq(seq)
        
        # Calculate isotopic distributions and extract monoisotopic and most abundant peak masses
        res <- useBRAIN(aC = aC, nrPeaks = nrPeaks, stopOption = "abundantEstim", abundantEstim = 10)
        isoDistr <- res\$isoDistr
        masses <- res\$masses
        maxIdx <- which.max(isoDistr)
        mostAbundantPeakMass <- masses[maxIdx]
        monoMass <- res\$monoisotopicMass  
        
        dfAtomicComp <- data.frame(C=aC[1], H=aC[2], N=aC[3], O=aC[4], S=aC[5])
        singleDfUniprot <- data.frame(dfAtomicComp, monoMass=monoMass, maxIdx=maxIdx, mostAbundantPeakMass=mostAbundantPeakMass)
        
        if (!is.na(monoMass)){ # for huge atomic configuration numerical problems may occur
          dfUniprot <- rbind(dfUniprot, singleDfUniprot)
        }
      }
    }
    
    # 3. Export the processed data to output files
    # Export as tab-delimited text file as in the documented code
    write.table(unique(dfUniprot), "uniprotBRAIN.txt", sep="\t", row.names=FALSE, quote=FALSE)
    
    # Also export as a clean CSV and RDS for downstream robustness
    write.csv(unique(dfUniprot), "uniprotBRAIN.csv", row.names=FALSE)
    saveRDS(unique(dfUniprot), "uniprotBRAIN.rds")

    writeLines(c(
        '"BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING":',
        paste0('    BRAIN: ', as.character(packageVersion('BRAIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_high_throughput_protein_processing.csv versions.yml
    """
}

workflow BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ uniprot.tab ] ]

    main:
    BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING(ch_input)

    emit:
    tables   = BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING.out.tables
    plots    = BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING.out.plots
    objects  = BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING.out.objects
    versions = BIOC_BRAIN_HIGH_THROUGHPUT_PROTEIN_PROCESSING.out.versions
}
