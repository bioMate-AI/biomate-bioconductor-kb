#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sbmlr — sbml_simulation_and_export
// Import an SBML model, modify initial conditions, run time-course simulations with or without reaction modulators, and export the modified model.
// Input: model.xml
// Container: quay.io/biocontainers/bioconductor-sbmlr:2.6.0--r45hdfd78af_0
// R packages: SBMLR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sbmlr:2.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("SBMLR")
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
    
    # ==========================================
    # Pipeline: sbml_simulation_and_export
    # Package: SBMLR
    # ==========================================
    
    library(SBMLR)
    
    # --- Import the SBML model from the declared user input file ---
    # (Replacing system.file demo-data setup with the required user input file)
    curto <- readSBML("model.xml")
    
    # --- Inspect the model structure and reaction laws using ---
    model_summary <- summary(curto)
    reactions_head <- head(model_summary\$reactions)
    
    # Save the summary head to a CSV file
    write.csv(reactions_head, "reactions_summary_head.csv", row.names = TRUE)
    
    # --- Run a baseline simulation to establish steady state using ---
    out1 <- sim(curto, seq(-20, 0, 1))
    
    # --- Modify initial concentrations of specific species ---
    curto\$species\$PRPP\$ic <- 50
    
    # --- Run a perturbation simulation using sim ---
    out2 <- sim(curto, 0:70)
    
    # Combine baseline and perturbation simulations
    outs <- data.frame(rbind(out1, out2))
    
    # Save the simulation results to a CSV file
    write.csv(outs, "simulation_results_prpp_perturbed.csv", row.names = FALSE)
    
    # Generate a PDF plot of the simulation results
    pdf("simulation_plots.pdf", width = 8, height = 10)
    par(mfrow = c(2, 1))
    plot(outs\$time, outs\$IMP, type = "l", xlab = "minutes", ylab = "IMP (uM)", main = "IMP Concentration Over Time")
    plot(outs\$time, outs\$HX, type = "l", xlab = "minutes", ylab = "HX (uM)", main = "HX Concentration Over Time")
    par(mfrow = c(1, 1))
    dev.off()
    
    # --- Apply reaction rate modulators to simulate enzyme level ---
    # Return PRPP IC to its original value
    curto\$species\$PRPP\$ic <- 5
    
    # Run simulation with uniform modulator (bumpless transfer)
    out_mod_uniform <- sim(curto, (-10):10, modulator = rep(2, 37))
    write.csv(out_mod_uniform, "simulation_uniform_modulator.csv", row.names = FALSE)
    
    # Run simulation with non-uniform modulator (unstable/not bumpless)
    out_mod_nonuniform <- sim(curto, (-10):10, modulator = c(rep(1.1, 20), rep(0.9, 17)))
    write.csv(out_mod_nonuniform, "simulation_nonuniform_modulator.csv", row.names = FALSE)
    
    # --- Export the model to XML format using saveSBML or to an ---
    saveSBML(curto, "curto_modified.xml")
    saveSBMLR(curto, "curto_modified.r")
    
    # Verify export by reading them back and comparing
    curtoX <- readSBML("curto_modified.xml")
    curtoR <- readSBMLR("curto_modified.r")
    
    comparison_species <- head((curtoX == curtoR)\$species)
    comparison_reactions <- head((curtoX == curtoR)\$reactions)
    
    write.csv(comparison_species, "comparison_species.csv", row.names = TRUE)
    write.csv(comparison_reactions, "comparison_reactions.csv", row.names = TRUE)
    
    # Print final summary and model object representation to console/log
    final_summary <- summary(curto)
    print(final_summary)
    print(curto)
    
    # Save the final model object as an RDS file for downstream R tasks
    saveRDS(curto, "curto_final_model.rds")

    writeLines(c(
        '"BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT":',
        paste0('        sbmlr: ', as.character(packageVersion("sbmlr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sbml_simulation_and_export.csv versions.yml
    """
}

workflow BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ model.xml ] ]

    main:
    BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT(ch_input)

    emit:
    tables   = BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT.out.tables
    plots    = BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT.out.plots
    objects  = BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT.out.objects
    versions = BIOC_SBMLR_SBML_SIMULATION_AND_EXPORT.out.versions
}
