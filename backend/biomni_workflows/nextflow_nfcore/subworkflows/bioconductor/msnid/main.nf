#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msnid — msms_filtering_and_fdr_optimization
// Load MS/MS search results, assess cleavage properties, correct mass errors, optimize filtering criteria to maximize identifications within a target FDR, and exp
// Input: human_brain.txt, c_elegans.mzid.gz
// Container: quay.io/biocontainers/bioconductor-msnid:1.44.0--r45ha27e39d_0
// R packages: Biostrings, dplyr, ggplot2, MSnbase, MSnID, xtable
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msnid:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biostrings", "dplyr", "ggplot2", "MSnbase", "MSnID", "xtable")
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
    library("MSnID")
    library("ggplot2")
    library("MSnbase")
    
    # 1. Initialize MSnID object and load PSM data
    msnid <- MSnID(".")
    
    # Read user input files from the working directory
    PSMresults <- read.delim("human_brain.txt", stringsAsFactors=FALSE)
    psms(msnid) <- PSMresults
    show(msnid)
    
    mzids <- "c_elegans.mzid.gz"
    msnid <- read_mzIDs(msnid, mzids)
    show(msnid)
    
    # Start PDF for diagnostic plots
    pdf("msnid_diagnostic_plots.pdf", width=8, height=6)
    
    # 2. Assess cleavage termini and missed cleavages
    msnid <- assess_termini(msnid, validCleavagePattern="[KR]\\\\.[^P]")
    msnid <- assess_missed_cleavages(msnid, missedCleavagePattern="[KR](?=[^P\$])")
    
    # Plot missed cleavages
    pepCleav <- unique(psms(msnid)[,c("numMissCleavages", "isDecoy", "peptide")])
    pepCleav <- as.data.frame(table(pepCleav[,c("numMissCleavages", "isDecoy")]))
    p1 <- ggplot(pepCleav, aes(x=numMissCleavages, y=Freq, fill=isDecoy)) +
        geom_bar(stat='identity', position='dodge') +
        ggtitle("Number of Missed Cleavages")
    print(p1)
    
    # 3. Calculate peptide length and other sequence properties
    msnid\$numCys <- sapply(lapply(strsplit(msnid\$peptide,''),'==','C'),sum)
    msnid\$PepLength <- nchar(msnid\$peptide) - 4
    
    # Plot peptide lengths
    pepLen <- unique(psms(msnid)[,c("PepLength", "isDecoy", "peptide")])
    p2 <- ggplot(pepLen, aes(x=PepLength, fill=isDecoy)) +
        geom_histogram(position='dodge', binwidth=3) +
        ggtitle("Distribution of Peptide Lengths")
    print(p2)
    
    show(msnid)
    
    # Apply initial tryptic filters
    msnid <- apply_filter(msnid, "numIrregCleavages == 0")
    show(msnid)
    
    msnid <- apply_filter(msnid, "numMissCleavages <= 2")
    show(msnid)
    
    # Plot original mass measurement error
    ppm <- mass_measurement_error(msnid)
    p3 <- ggplot(as.data.frame(ppm), aes(x=ppm)) +
        geom_histogram(binwidth=100) +
        ggtitle("Original Mass Measurement Error")
    print(p3)
    
    # Plot delta mass
    dM <- with(psms(msnid),
        (experimentalMassToCharge-calculatedMassToCharge)*chargeState)
    x <- data.frame(dM, isDecoy=msnid\$isDecoy)
    p4 <- ggplot(x, aes(x=dM, fill=isDecoy)) +
        geom_histogram(position='stack', binwidth=0.1) +
        ggtitle("Delta Mass Distribution")
    print(p4)
    
    # 4. Correct parent ion mass measurement errors and recalibrate
    msnid.fixed <- correct_peak_selection(msnid)
    ppm <- mass_measurement_error(msnid.fixed)
    p5 <- ggplot(as.data.frame(ppm), aes(x=ppm)) +
        geom_histogram(binwidth=0.25) +
        ggtitle("Corrected Peak Selection Mass Error")
    print(p5)
    
    msnid.chopped <- apply_filter(msnid, "abs(mass_measurement_error(msnid)) < 20")
    ppm <- mass_measurement_error(msnid.chopped)
    p6 <- ggplot(as.data.frame(ppm), aes(x=ppm)) +
        geom_histogram(binwidth=0.25) +
        ggtitle("Chopped Mass Error (< 20 ppm)")
    print(p6)
    
    msnid <- recalibrate(msnid.chopped)
    ppm <- mass_measurement_error(msnid)
    p7 <- ggplot(as.data.frame(ppm), aes(x=ppm)) +
        geom_histogram(binwidth=0.25) +
        ggtitle("Recalibrated Mass Error")
    print(p7)
    
    # Calculate scores
    msnid\$msmsScore <- -log10(msnid\$`MS-GF:SpecEValue`)
    params <- psms(msnid)[,c("msmsScore","isDecoy")]
    p8 <- ggplot(params) +
        geom_density(aes(x = msmsScore, color = isDecoy, y = ..count..)) +
        ggtitle("MS-GF SpecEValue Score Distribution")
    print(p8)
    
    msnid\$absParentMassErrorPPM <- abs(mass_measurement_error(msnid))
    params2 <- psms(msnid)[,c("absParentMassErrorPPM","isDecoy")]
    p9 <- ggplot(params2) +
        geom_density(aes(x = absParentMassErrorPPM, color = isDecoy, y = ..count..)) +
        ggtitle("Absolute Parent Mass Error Distribution")
    print(p9)
    
    # 5. Define filtering criteria and optimize thresholds using Grid and Nelder-Mead methods
    filtObj <- MSnIDFilter(msnid)
    filtObj\$absParentMassErrorPPM <- list(comparison="<", threshold=10.0)
    filtObj\$msmsScore <- list(comparison=">", threshold=10.0)
    show(filtObj)
    
    evaluate_filter(msnid, filtObj, level="PSM")
    evaluate_filter(msnid, filtObj, level="peptide")
    evaluate_filter(msnid, filtObj, level="accession")
    
    # Grid search optimization
    filtObj.grid <- optimize_filter(filtObj, msnid, fdr.max=0.01,
                                    method="Grid", level="peptide",
                                    n.iter=500)
    show(filtObj.grid)
    
    # Nelder-Mead optimization
    filtObj.nm <- optimize_filter(filtObj.grid, msnid, fdr.max=0.01,
                                    method="Nelder-Mead", level="peptide",
                                    n.iter=500)
    show(filtObj.nm)
    
    evaluate_filter(msnid, filtObj, level="peptide")
    evaluate_filter(msnid, filtObj.nm, level="peptide")
    
    # Close PDF device
    dev.off()
    
    # 6. Apply optimized filters and remove decoy/contaminant matches
    msnid <- apply_filter(msnid, filtObj.nm)
    show(msnid)
    
    msnid <- apply_filter(msnid, "isDecoy == FALSE")
    show(msnid)
    
    msnid <- apply_filter(msnid, "!grepl('Contaminant',accession)")
    show(msnid)
    
    # Extract tables
    psm.df <- psms(msnid)
    psm.dt <- as(msnid, "data.table")
    
    peps <- peptides(msnid)
    head(peps)
    
    prots <- accessions(msnid)
    head(prots)
    
    prots <- proteins(msnid)
    head(prots)
    
    # Write tabular outputs
    write.csv(psm.df, "psm_filtered.csv", row.names=FALSE)
    writeLines(peps, "peptides_filtered.txt")
    writeLines(prots, "proteins_filtered.txt")
    
    # 7. Export to MSnSet for downstream spectral counting
    msnset <- as(msnid, "MSnSet")
    head(fData(msnset))
    head(exprs(msnset))
    
    # Combine features to protein level
    msnset <- combineFeatures(msnset,
                                fData(msnset)\$accession,
                                redundancy.handler="unique",
                                fun="sum",
                                cv=FALSE)
    head(fData(msnset))
    head(exprs(msnset))
    
    # Save final MSnSet object
    saveRDS(msnset, "msnset_combined.rds")
    
    # Clean up cache
    unlink(".Rcache", recursive=TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION":
        msnid: \$(Rscript -e 'cat(as.character(packageVersion("msnid")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msms_filtering_and_fdr_optimization.csv versions.yml
    """
}

workflow BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ human_brain.txt, c_elegans.mzid.gz ] ]

    main:
    BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION.out.tables
    plots    = BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION.out.plots
    objects  = BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION.out.objects
    versions = BIOC_MSNID_MSMS_FILTERING_AND_FDR_OPTIMIZATION.out.versions
}
