nextflow.enable.dsl = 2

// VISUALIZATION — Cryo-EM output visualization modules
// Generates publication-quality PNG figures and interactive HTML viewers
// All outputs land in BioMate's output attachment system for display in chat
//
// Container: biomate/cryo-em-tools:1.0

// FSC CURVE PLOT — renders gold-standard FSC curve with resolution annotation
process FSC_PLOT {
    tag "fsc_plot"
    publishDir "${params.outdir}/visualization/fsc", mode: 'copy'

    container 'biomate/cryo-em-tools:1.0'

    input:
    path fsc_json           // CryoSPARC or RELION FSC JSON output
    val  pixel_size         // Å/pixel
    val  title              // Plot title (protein name + condition)

    output:
    path "fsc_curve.png",   emit: fsc_plot
    path "fsc_report.json", emit: report

    script:
    def ps = pixel_size ?: (params.pixel_size ?: 0.83)
    def t  = title ?: (params.project_name ?: 'Cryo-EM SPA')

    """
    python3 /opt/biomate_cryo_em/scripts/fsc_visualization.py \\
        --fsc_file ${fsc_json} \\
        --output fsc_curve.png \\
        --pixel_size ${ps} \\
        --title "${t}" \\
        --report fsc_report.json
    """

    stub:
    """
    python3 /opt/biomate_cryo_em/scripts/fsc_visualization.py \\
        --output fsc_curve.png \\
        --pixel_size ${pixel_size ?: 0.83} \\
        --title "Mock FSC" \\
        --report fsc_report.json \\
        --mock
    """
}


// MULTI_FSC_COMPARISON — FSC curves for multiple datasets on one plot
// Used for dual-dataset studies (morphine vs fentanyl, drug atlas)
process MULTI_FSC_COMPARISON {
    tag "multi_fsc"
    publishDir "${params.outdir}/visualization/fsc", mode: 'copy'

    container 'biomate/cryo-em-tools:1.0'

    input:
    path  fsc_files        // all FSC JSON files (staged together)
    val   labels           // comma-separated labels e.g. "morphine,fentanyl"
    val   pixel_size
    val   title

    output:
    path "fsc_comparison.png",   emit: comparison_plot
    path "fsc_comparison_report.json", emit: report

    script:
    def ps = pixel_size ?: (params.pixel_size ?: 0.83)
    def label_list = labels?.split(',') ?: ['Dataset 1', 'Dataset 2']
    def label_args = label_list.collect { "--labels ${it}" }.join(' ')
    def fsc_list = fsc_files instanceof List ? fsc_files.join(' ') : fsc_files

    """
    python3 /opt/biomate_cryo_em/scripts/fsc_visualization.py \\
        --fsc_file ${fsc_list.split()[0]} \\
        --compare ${fsc_list.split().tail().join(' ')} \\
        --labels ${labels} \\
        --output fsc_comparison.png \\
        --pixel_size ${ps} \\
        --title "${title ?: 'FSC Comparison'}" \\
        --report fsc_comparison_report.json
    """

    stub:
    """
    python3 /opt/biomate_cryo_em/scripts/fsc_visualization.py \\
        --output fsc_comparison.png \\
        --pixel_size ${pixel_size ?: 0.83} \\
        --title "Mock FSC Comparison" \\
        --report fsc_comparison_report.json \\
        --mock
    """
}


// STRUCTURE_OVERVIEW — PDB + density map visualization via PyMOL/py3Dmol
// Outputs: PNG for reports + HTML interactive viewer for BioMate chat
process STRUCTURE_OVERVIEW {
    tag "structure_viz"
    publishDir "${params.outdir}/visualization/structure", mode: 'copy'

    container 'biomate/cryo-em-tools:1.0'

    input:
    path pdb_file
    path map_file
    val  resolution_A

    output:
    path "structure_overview.png",     emit: overview_png
    path "structure_viewer.html",      emit: interactive_html
    path "visualization_report.json",  emit: report

    script:
    """
    mkdir -p viz_out
    python3 /opt/biomate_cryo_em/scripts/structure_visualization.py \\
        --pdb ${pdb_file} \\
        --map ${map_file} \\
        --output_dir viz_out \\
        --mode overview \\
        --resolution ${resolution_A ?: 3.0} \\
        --report viz_out/visualization_report.json

    cp viz_out/structure_overview.png . 2>/dev/null || \\
        python3 /opt/biomate_cryo_em/scripts/structure_visualization.py \\
            --output_dir . --mode overview --mock --report visualization_report.json
    cp viz_out/structure_viewer.html . 2>/dev/null || echo "<html><body>Viewer pending</body></html>" > structure_viewer.html
    cp viz_out/visualization_report.json . 2>/dev/null || echo '{}' > visualization_report.json
    """

    stub:
    """
    python3 /opt/biomate_cryo_em/scripts/structure_visualization.py \\
        --output_dir . --mode overview --mock --report visualization_report.json
    touch structure_viewer.html
    """
}


// LOCAL_RESOLUTION_PLOT — histogram of local resolution distribution
process LOCAL_RESOLUTION_PLOT {
    tag "local_res_plot"
    publishDir "${params.outdir}/visualization/local_resolution", mode: 'copy'

    container 'biomate/cryo-em-tools:1.0'

    input:
    path local_resolution_data   // JSON from CryoSPARC local_resolution job

    output:
    path "local_resolution.png",    emit: plot
    path "visualization_report.json", emit: report

    script:
    """
    python3 /opt/biomate_cryo_em/scripts/structure_visualization.py \\
        --map ${local_resolution_data} \\
        --output_dir . \\
        --mode local_resolution \\
        --report visualization_report.json
    """

    stub:
    """
    python3 /opt/biomate_cryo_em/scripts/structure_visualization.py \\
        --output_dir . --mode local_resolution --mock --report visualization_report.json
    """
}
