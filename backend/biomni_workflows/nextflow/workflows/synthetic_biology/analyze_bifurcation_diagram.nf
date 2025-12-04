#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_analyze_bifurcation_diagram
 * Performs bifurcation analysis on a dynamical system and generates a bifurcation diagram.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.time_series_data = null
params.parameter_values = null

// Processes
process STEP_1__PLT_FIGURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__plt_figure_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_figure
    # Runs in unified Docker container
    echo 'Running STEP_1__PLT_FIGURE'
        touch step_1__plt_figure_output.txt
    """
}

process STEP_2__PLT_LEGEND {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__plt_legend_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_legend
    # Runs in unified Docker container
    echo 'Running STEP_2__PLT_LEGEND'
        touch step_2__plt_legend_output.txt
    """
}

process STEP_3__PLT_PLOT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__plt_plot_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_plot
    # Runs in unified Docker container
    echo 'Running STEP_3__PLT_PLOT'
        touch step_3__plt_plot_output.txt
    """
}

process STEP_4__PLT_XLABEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__plt_xlabel_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_xlabel
    # Runs in unified Docker container
    echo 'Running STEP_4__PLT_XLABEL'
        touch step_4__plt_xlabel_output.txt
    """
}

process STEP_5__PLT_YLABEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__plt_ylabel_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_ylabel
    # Runs in unified Docker container
    echo 'Running STEP_5__PLT_YLABEL'
        touch step_5__plt_ylabel_output.txt
    """
}

workflow BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BIFURCATION_DIAGRAM {
    main:
    ch_time_series_data = Channel.value(params.time_series_data)
    ch_parameter_values = Channel.value(params.parameter_values)

    STEP_1__PLT_FIGURE(ch_parameter_values)
    STEP_2__PLT_LEGEND(STEP_1__PLT_FIGURE.out.output)
    STEP_3__PLT_PLOT(STEP_2__PLT_LEGEND.out.output)
    STEP_4__PLT_XLABEL(STEP_3__PLT_PLOT.out.output)
    STEP_5__PLT_YLABEL(STEP_4__PLT_XLABEL.out.output)

    emit:
    output = STEP_5__PLT_YLABEL.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BIFURCATION_DIAGRAM()
}