#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: psmatch — ms2_fragment_ion_analysis
// Calculate theoretical fragment ions for a peptide sequence and visualize them against experimental MS2 spectra.
// Input: spf.mzML.gz, idf.mzid
// Container: quay.io/biocontainers/bioconductor-psmatch:1.14.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-psmatch:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("PSMatch", "PTMods", "Spectra")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(Spectra)
    library(PSMatch)
    library(PTMods)
    
    # 1. Load raw MS data from the working directory
    spf <- "spf.mzML.gz"
    sp <- Spectra(spf)
    
    # 2. Load and filter identification data from the working directory
    idf <- "idf.mzid"
    id <- PSM(idf) |> filterPSMs()
    
    # 3. Merge raw and identification data
    sp <- joinSpectraData(sp, id, by.x = "spectrumId", by.y = "spectrumID")
    
    # 4. Filter precursor scans
    sp1158 <- filterPrecursorScan(sp, 1158)
    
    # Save precursor scan plot to PDF
    pdf("precursor_scan_1158.pdf", width = 7, height = 5)
    plotSpectra(sp1158[1], xlim = c(400, 600))
    abline(v = precursorMz(sp1158)[2], col = "red", lty = "dotted")
    dev.off()
    
    # 5. Calculate theoretical fragment ions
    # Print sequence to console
    sp1158\$sequence
    
    # Calculate fragments without carbamidomethylation and save to CSV
    frags_no_carbamido <- calculateFragments(sp1158\$sequence[2], addCarbamidomethyl = FALSE)
    write.csv(frags_no_carbamido, "fragments_no_carbamidomethyl.csv", row.names = FALSE)
    
    # Add variable modifications and calculate fragments
    var_seq <- PTMods::addVariableModifications(sp1158\$sequence[2],
        variableModifications = c(C = 57.02146, T = 79.966)
    )
    frags_var_mod <- calculateFragments(var_seq)
    write.csv(frags_var_mod, "fragments_variable_modifications.csv", row.names = FALSE)
    
    # 6. Plot experimental spectra and annotate with PTMs
    pdf("experimental_spectra_ptm.pdf", width = 10, height = 8)
    
    # Plot experimental spectrum as is
    plotSpectra(sp1158[2])
    
    # Plot with fixed modifications
    dataOrigin(sp1158)[2] <- "TMT_Erwinia" ## Reduces the mzspec text
    plotSpectraPTM(sp1158[2],
        fixedModifications = c(C = "Carbamidomethyl")
    )
    
    # Plot comparison with and without carbamidomethylation
    plotSpectraPTM(sp1158[2],
        variableModifications = c(C = "Carbamidomethyl"),
        addCarbamidomethyl = FALSE, ## Remove carbamidomethyl by default
        asp = 1/2,
        deltaMz = FALSE,
        main = c("Scan 1158 without carbamidomethyl", "Scan 1158 with carbamidomethyl")
    )
    
    dev.off()
    
    # Save processed objects for downstream analysis
    saveRDS(sp1158, "sp1158_filtered.rds")
    saveRDS(id, "id_filtered.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS":
        psmatch: \$(Rscript -e 'cat(as.character(packageVersion("psmatch")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ms2_fragment_ion_analysis.csv versions.yml
    """
}

workflow BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spf.mzML.gz, idf.mzid ] ]

    main:
    BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS.out.tables
    plots    = BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS.out.plots
    objects  = BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS.out.objects
    versions = BIOC_PSMATCH_MS2_FRAGMENT_ION_ANALYSIS.out.versions
}
