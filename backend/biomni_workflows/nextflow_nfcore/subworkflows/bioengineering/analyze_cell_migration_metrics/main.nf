#!/usr/bin/env nextflow
/*
 * bioengineering/analyze_cell_migration_metrics
 * Analyze cell migration metrics from time-lapse microscopy images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Use null to trigger synthetic cell track generation for testing
params.image_sequence_path = null
params.pixel_size_um = '1.0'
params.time_interval_min = '1.0'
params.min_track_length = '10'
params.output_dir = './'

process ANALYZE_CELL_MIGRATION_METRICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_cell_migration_metrics_results.json"), emit: results
    tuple val(meta), path("analyze_cell_migration_metrics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_SEQUENCE_PATH="${params.image_sequence_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PIXEL_SIZE_UM="${params.pixel_size_um?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_INTERVAL_MIN="${params.time_interval_min?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_TRACK_LENGTH="${params.min_track_length?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def analyze_cell_migration_metrics(
    image_sequence_path,
    pixel_size_um=1.0,
    time_interval_min=1.0,
    min_track_length=10,
    output_dir="./",
):
    '''Analyze cell migration metrics from time-lapse microscopy images.

    Parameters
    ----------
    image_sequence_path : str
        Path to the directory containing time-lapse images or path to a multi-frame TIFF file
    pixel_size_um : float
        Conversion factor from pixels to micrometers (default: 1.0)
    time_interval_min : float
        Time interval between consecutive frames in minutes (default: 1.0)
    min_track_length : int
        Minimum number of frames a cell must be tracked to be included in analysis (default: 10)
    output_dir : str
        Directory to save output files (default: "./")

    Returns
    -------
    str
        Research log summarizing the cell migration analysis process and results

    '''
    import os

    import matplotlib.pyplot as plt
    import numpy as np
    import pandas as pd
    import trackpy as tp
    from skimage import io

    # Validate inputs - use defaults if None
    if pixel_size_um is None:
        pixel_size_um = 1.0
    if time_interval_min is None:
        time_interval_min = 1.0
    if min_track_length is None:
        min_track_length = 10
    if output_dir is None:
        output_dir = "./"
    pixel_size_um = float(pixel_size_um)
    time_interval_min = float(time_interval_min)
    min_track_length = int(min_track_length)

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Generate synthetic data if no image path provided
    if image_sequence_path is None:
        # Generate synthetic cell migration data
        np.random.seed(42)
        n_frames = 20
        n_cells = 5

        # Simulate cell trajectories
        trajectories_data = []
        for cell_id in range(n_cells):
            x = 50 + np.cumsum(np.random.randn(n_frames) * 2)
            y = 50 + np.cumsum(np.random.randn(n_frames) * 2)
            for frame, (xi, yi) in enumerate(zip(x, y)):
                trajectories_data.append({
                    'x': xi, 'y': yi, 'frame': frame, 'particle': cell_id,
                    'mass': 1000, 'size': 3, 'ecc': 0.1, 'signal': 100, 'raw_mass': 1000, 'ep': 0.1
                })

        trajectories = pd.DataFrame(trajectories_data)

        # Calculate metrics directly from synthetic trajectories
        cell_ids = trajectories["particle"].unique()
        metrics = []

        for cell_id in cell_ids:
            cell_track = trajectories[trajectories["particle"] == cell_id].sort_values("frame")
            cell_track = cell_track.copy()
            cell_track["x_um"] = cell_track["x"] * pixel_size_um
            cell_track["y_um"] = cell_track["y"] * pixel_size_um

            dx = np.diff(cell_track["x_um"])
            dy = np.diff(cell_track["y_um"])
            step_distances = np.sqrt(dx**2 + dy**2)
            path_length = np.sum(step_distances)

            start_x, start_y = cell_track.iloc[0][["x_um", "y_um"]]
            end_x, end_y = cell_track.iloc[-1][["x_um", "y_um"]]
            net_displacement = np.sqrt((end_x - start_x) ** 2 + (end_y - start_y) ** 2)
            directionality = net_displacement / path_length if path_length > 0 else 0

            time_tracked = (cell_track["frame"].max() - cell_track["frame"].min()) * time_interval_min
            speed = path_length / time_tracked if time_tracked > 0 else 0

            metrics.append({
                "cell_id": cell_id,
                "frames_tracked": len(cell_track),
                "speed_um_per_min": speed,
                "directionality": directionality,
                "displacement_um": net_displacement,
                "path_length_um": path_length,
            })

        metrics_df = pd.DataFrame(metrics)
        metrics_df.to_csv(os.path.join(output_dir, "cell_migration_metrics.csv"), index=False)

        summary = {
            "num_cells_tracked": len(metrics_df),
            "avg_speed": metrics_df["speed_um_per_min"].mean(),
            "avg_directionality": metrics_df["directionality"].mean(),
            "avg_displacement": metrics_df["displacement_um"].mean(),
        }

        log = "# Cell Migration Analysis (Synthetic Data)\\n\\n"
        log += f"Generated {n_cells} synthetic cell tracks over {n_frames} frames.\\n\\n"
        log += "## Summary Statistics\\n"
        log += f"- Cells tracked: {summary['num_cells_tracked']}\\n"
        log += f"- Average speed: {summary['avg_speed']:.2f} μm/min\\n"
        log += f"- Average directionality: {summary['avg_directionality']:.2f}\\n"
        log += f"- Average displacement: {summary['avg_displacement']:.2f} μm\\n"
        return log

    # Load image sequence
    if os.path.isdir(image_sequence_path):
        # Load from directory of images
        image_files = sorted(
            [f for f in os.listdir(image_sequence_path) if f.endswith((".tif", ".tiff", ".png", ".jpg", ".jpeg"))]
        )
        frames = [io.imread(os.path.join(image_sequence_path, f)) for f in image_files]
    else:
        # Load multi-frame TIFF
        frames = io.imread(image_sequence_path)
        if frames.ndim == 3:  # Check if it's a time series
            pass
        else:
            return "Error: Input is not a valid time-lapse image sequence"

    # Step 1: Detect cells in each frame
    features_list = []
    for i, frame in enumerate(frames):
        # Detect cells (particles) in the frame
        features = tp.locate(frame, diameter=15, minmass=100)
        if features is not None and not features.empty:
            features["frame"] = i
            features_list.append(features)

    if not features_list:
        return "Error: No cells detected in the image sequence"

    # Combine all features
    all_features = pd.concat(features_list)

    # Save raw detections to output directory
    raw_detections_file = os.path.join(output_dir, "raw_cell_detections.csv")
    all_features.to_csv(raw_detections_file, index=False)

    # Step 2: Link features into cell trajectories
    trajectories = tp.link_df(all_features, search_range=10, memory=3)

    # Save linked trajectories before filtering
    # Reset index to ensure frame is a column, not an index level
    trajectories_reset = trajectories.reset_index(drop=True)
    all_trajectories_file = os.path.join(output_dir, "all_trajectories.csv")
    trajectories_reset.to_csv(all_trajectories_file, index=False)

    # Step 3: Filter trajectories to get only the ones that appear in enough frames
    trajectories = tp.filter_stubs(trajectories, threshold=min_track_length)

    if trajectories.empty:
        return "No complete cell tracks found. Try adjusting parameters."

    # Save filtered trajectories
    filtered_trajectories_file = os.path.join(output_dir, "filtered_trajectories.csv")
    # Reset index again to be safe
    trajectories = trajectories.reset_index(drop=True)
    trajectories.to_csv(filtered_trajectories_file, index=False)

    # Step 4: Calculate migration metrics for each cell
    cell_ids = trajectories["particle"].unique()
    metrics = []

    for cell_id in cell_ids:
        cell_track = trajectories[trajectories["particle"] == cell_id].sort_values("frame")

        # Convert pixel positions to micrometers
        cell_track["x_um"] = cell_track["x"] * pixel_size_um
        cell_track["y_um"] = cell_track["y"] * pixel_size_um

        # Calculate displacements between consecutive frames
        dx = np.diff(cell_track["x_um"])
        dy = np.diff(cell_track["y_um"])

        # Calculate step distances
        step_distances = np.sqrt(dx**2 + dy**2)

        # Calculate total path length
        path_length = np.sum(step_distances)

        # Calculate net displacement (straight-line distance from start to end)
        start_x, start_y = cell_track.iloc[0][["x_um", "y_um"]]
        end_x, end_y = cell_track.iloc[-1][["x_um", "y_um"]]
        net_displacement = np.sqrt((end_x - start_x) ** 2 + (end_y - start_y) ** 2)

        # Calculate directionality ratio (net displacement / path length)
        directionality = net_displacement / path_length if path_length > 0 else 0

        # Calculate speed (μm/min)
        time_tracked = (cell_track["frame"].max() - cell_track["frame"].min()) * time_interval_min
        speed = path_length / time_tracked if time_tracked > 0 else 0

        metrics.append(
            {
                "cell_id": cell_id,
                "frames_tracked": len(cell_track),
                "speed_um_per_min": speed,
                "directionality": directionality,
                "displacement_um": net_displacement,
                "path_length_um": path_length,
            }
        )

    # Convert metrics to DataFrame
    metrics_df = pd.DataFrame(metrics)

    # Save metrics to CSV
    metrics_file = os.path.join(output_dir, "cell_migration_metrics.csv")
    metrics_df.to_csv(metrics_file, index=False)

    # Calculate summary statistics
    summary = {
        "num_cells_tracked": len(metrics_df),
        "avg_speed": metrics_df["speed_um_per_min"].mean(),
        "std_speed": metrics_df["speed_um_per_min"].std(),
        "avg_directionality": metrics_df["directionality"].mean(),
        "std_directionality": metrics_df["directionality"].std(),
        "avg_displacement": metrics_df["displacement_um"].mean(),
        "std_displacement": metrics_df["displacement_um"].std(),
    }

    # Save summary statistics
    summary_file = os.path.join(output_dir, "migration_summary.csv")
    pd.DataFrame([summary]).to_csv(summary_file, index=False)

    # Save trajectories visualization
    fig, ax = plt.figure(figsize=(8, 8)), plt.gca()
    tp.plot_traj(trajectories, ax=ax)
    plt.title("Cell Migration Trajectories")
    plt.xlabel("x position (pixels)")
    plt.ylabel("y position (pixels)")

    trajectories_file = os.path.join(output_dir, "cell_trajectories.png")
    plt.savefig(trajectories_file)
    plt.close()

    # Create a rose plot to show migration directionality
    fig, ax = plt.subplots(subplot_kw={"projection": "polar"}, figsize=(8, 8))

    # Calculate angles for each cell (end position relative to start)
    angles = []
    for cell_id in cell_ids:
        cell_track = trajectories[trajectories["particle"] == cell_id].sort_values("frame")
        start_x, start_y = cell_track.iloc[0][["x", "y"]]
        end_x, end_y = cell_track.iloc[-1][["x", "y"]]
        dx, dy = end_x - start_x, end_y - start_y
        angle = np.arctan2(dy, dx)
        angles.append(angle)

    # Plot the histogram
    bins = np.linspace(-np.pi, np.pi, 16)
    ax.hist(angles, bins=bins)
    ax.set_title("Cell Migration Directionality")

    # Save the rose plot
    rose_plot_file = os.path.join(output_dir, "rose_plot.png")
    plt.savefig(rose_plot_file)
    plt.close()

    # Create a displacement plot
    plt.figure(figsize=(10, 6))
    plt.bar(range(len(metrics_df)), metrics_df["displacement_um"])
    plt.xlabel("Cell ID")
    plt.ylabel("Displacement (μm)")
    plt.title("Cell Displacements")

    # Save the displacement plot
    displacement_plot_file = os.path.join(output_dir, "track_displacement_plot.png")
    plt.savefig(displacement_plot_file)
    plt.close()

    # Generate research log
    log = f'''
Cell Migration Analysis Research Log:

1. Analyzed time-lapse sequence with {len(frames)} frames
2. Detected and tracked {len(cell_ids)} cells that persisted for at least {min_track_length} frames
3. Calculated key migration metrics:
   - Average speed: {summary["avg_speed"]:.2f} ± {summary["std_speed"]:.2f} μm/min
   - Average directionality ratio: {summary["avg_directionality"]:.2f} ± {summary["std_directionality"]:.2f}
   - Average displacement: {summary["avg_displacement"]:.2f} ± {summary["std_displacement"]:.2f} μm

4. Files saved:
   - Raw cell detections: {raw_detections_file}
   - All cell trajectories: {all_trajectories_file}
   - Filtered trajectories: {filtered_trajectories_file}
   - Detailed cell metrics: {metrics_file}
   - Summary statistics: {summary_file}
   - Cell trajectories visualization: {trajectories_file}
   - Direction rose plot: {rose_plot_file}
   - Cell displacement plot: {displacement_plot_file}

Note: Analysis used pixel size of {pixel_size_um} μm and time interval of {time_interval_min} min between frames.
    '''

    return log.strip()

# Execute the function
try:
    result = analyze_cell_migration_metrics(
        image_sequence_path=auto_convert(os.environ.get("PARAM_IMAGE_SEQUENCE_PATH", "")),
        pixel_size_um=auto_convert(os.environ.get("PARAM_PIXEL_SIZE_UM", "1.0")),
        time_interval_min=auto_convert(os.environ.get("PARAM_TIME_INTERVAL_MIN", "1.0")),
        min_track_length=auto_convert(os.environ.get("PARAM_MIN_TRACK_LENGTH", "10")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "analyze_cell_migration_metrics",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_cell_migration_metrics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_cell_migration_metrics_output.txt", "w") as f:
    f.write("Biomni: Analyze Cell Migration Metrics" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "analyze_cell_migration_metrics"
    END_VERSIONS
    """
}

workflow ANALYZE_CELL_MIGRATION_METRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CELL_MIGRATION_METRICS(ch_input)

    emit:
    results = ANALYZE_CELL_MIGRATION_METRICS.out.results
    output = ANALYZE_CELL_MIGRATION_METRICS.out.output
    versions = ANALYZE_CELL_MIGRATION_METRICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CELL_MIGRATION_METRICS_WORKFLOW(ch_input)

    ANALYZE_CELL_MIGRATION_METRICS_WORKFLOW.out.output.view { "Output: $it" }
}
