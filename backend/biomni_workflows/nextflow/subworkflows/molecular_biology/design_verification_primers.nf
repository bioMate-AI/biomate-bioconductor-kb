#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_verification_primers
 * Design Sanger sequencing primers to verify a construct. Uses align_sequences to map existing primers and design_primer to create new primers for uncovered regions.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.plasmid_sequence = null
params.region_start = null
params.region_end = null
params.existing_primers = null

// Processes
process IDENTIFY_COVERAGE_GAPS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(region_start)
    path(region_end)
    path(primer_alignments)

    output:
    path("identify_coverage_gaps_gaps.txt"), emit: gaps

    script:
    """
    # Tool: biomni_molecular_biology_identify_coverage_gaps
    # Runs in unified Docker container
    echo 'Running IDENTIFY_COVERAGE_GAPS'
        touch identify_coverage_gaps_gaps.txt
    """
}

process COMPILE_FINAL_PRIMER_SET {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(plasmid_sequence)
    path(region_start)
    path(region_end)
    path(existing_primers)
    path(aligned_primers)
    path(new_primers)

    output:
    path("compile_final_primer_set_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_design_verification_primers
    # Runs in unified Docker container
    echo 'Running COMPILE_FINAL_PRIMER_SET'
        touch compile_final_primer_set_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_VERIFICATION_PRIMERS {
    main:
    ch_plasmid_sequence = Channel.fromPath(params.plasmid_sequence)
    ch_region_start = Channel.fromPath(params.region_start)
    ch_region_end = Channel.fromPath(params.region_end)
    ch_existing_primers = Channel.fromPath(params.existing_primers)

    IDENTIFY_COVERAGE_GAPS(ch_region_start, ch_region_end, ALIGN_EXISTING_PRIMERS.out.alignments)
    COMPILE_FINAL_PRIMER_SET(ch_plasmid_sequence, ch_region_start, ch_region_end, ch_existing_primers, ALIGN_EXISTING_PRIMERS.out.alignments, DESIGN_NEW_PRIMERS.out.primers)

    emit:
    output = COMPILE_FINAL_PRIMER_SET.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_VERIFICATION_PRIMERS()
}