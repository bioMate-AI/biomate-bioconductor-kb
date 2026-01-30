#!/usr/bin/env nextflow
/*
 * cell_biology/quantify_and_cluster_cell_motility
 * Quantify cell motility features from time-lapse microscopy images and cluster cells based on motility patterns.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo mode: use 'demo' to generate synthetic time-lapse images
params.image_sequence_path = 'demo'
params.output_dir = './results'
params.num_clusters = '3'

process QUANTIFY_AND_CLUSTER_CELL_MOTILITY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("quantify_and_cluster_cell_motility_results.json"), emit: results
    tuple val(meta), path("quantify_and_cluster_cell_motility_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_SEQUENCE_PATH="${params.image_sequence_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_CLUSTERS="${params.num_clusters?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def quantify_and_cluster_cell_motility(image_sequence_path, output_dir="./results", num_clusters=3):
    '''Quantify cell motility features from time-lapse microscopy images and cluster cells based on motility patterns.

    Parameters
    ----------
    image_sequence_path : str
        Path to directory containing time-lapse microscopy images in sequential order.
        Use 'demo' for synthetic test data.
    output_dir : str
        Directory to save output files (default: "./results")
    num_clusters : int
        Number of motility pattern clusters to identify (default: 3)

    Returns
    -------
    str
        Research log summarizing the analysis process and results

    '''
    import os
    import tempfile

    import cv2
    import numpy as np
    import pandas as pd
    from sklearn.cluster import KMeans

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Generate synthetic time-lapse images if demo mode
    if image_sequence_path == 'demo' or image_sequence_path is None:
        # Create temporary directory with synthetic images
        temp_dir = tempfile.mkdtemp(prefix='cell_motility_demo_')
        np.random.seed(42)

        # Generate 10 frames with moving cells
        n_frames = 10
        n_cells = 20
        img_size = 256

        # Initialize cell positions with different motility types
        cell_positions = []
        cell_speeds = []
        for i in range(n_cells):
            x = np.random.randint(30, img_size - 30)
            y = np.random.randint(30, img_size - 30)
            # Different cell types: slow, medium, fast
            if i < n_cells // 3:
                speed = np.random.uniform(1, 3)  # slow
            elif i < 2 * n_cells // 3:
                speed = np.random.uniform(3, 6)  # medium
            else:
                speed = np.random.uniform(6, 10)  # fast
            cell_positions.append([x, y])
            cell_speeds.append(speed)

        for frame_idx in range(n_frames):
            img = np.zeros((img_size, img_size), dtype=np.uint8)

            # Draw cells and update positions
            for cell_idx in range(n_cells):
                x, y = cell_positions[cell_idx]
                # Draw cell as a circle
                cv2.circle(img, (int(x), int(y)), 8, 255, -1)

                # Update position for next frame
                angle = np.random.uniform(0, 2 * np.pi)
                dx = cell_speeds[cell_idx] * np.cos(angle)
                dy = cell_speeds[cell_idx] * np.sin(angle)
                new_x = np.clip(x + dx, 10, img_size - 10)
                new_y = np.clip(y + dy, 10, img_size - 10)
                cell_positions[cell_idx] = [new_x, new_y]

            # Save frame
            frame_path = os.path.join(temp_dir, f"frame_{frame_idx:03d}.png")
            cv2.imwrite(frame_path, img)

        image_sequence_path = temp_dir

    # Step 1: Load image sequence
    image_files = sorted(
        [f for f in os.listdir(image_sequence_path) if f.endswith((".tif", ".tiff", ".png", ".jpg", ".jpeg"))]
    )

    if len(image_files) < 2:
        return "Error: Insufficient images found. At least 2 time points are required."

    # Step 2: Initialize cell tracking
    first_image = cv2.imread(os.path.join(image_sequence_path, image_files[0]), cv2.IMREAD_GRAYSCALE)

    # Simple cell detection using thresholding and contour detection
    _, binary = cv2.threshold(first_image, 127, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    # Extract cell centroids from first frame
    cells = []
    for i, contour in enumerate(contours):
        if cv2.contourArea(contour) > 50:  # Filter small noise
            M = cv2.moments(contour)
            if M["m00"] != 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
                cells.append({"id": i, "positions": [(cx, cy)], "frame_indices": [0]})

    # Step 3: Track cells across frames
    for frame_idx, img_file in enumerate(image_files[1:], 1):
        img = cv2.imread(os.path.join(image_sequence_path, img_file), cv2.IMREAD_GRAYSCALE)
        _, binary = cv2.threshold(img, 127, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        # Get current frame centroids
        current_centroids = []
        for contour in contours:
            if cv2.contourArea(contour) > 50:
                M = cv2.moments(contour)
                if M["m00"] != 0:
                    cx = int(M["m10"] / M["m00"])
                    cy = int(M["m01"] / M["m00"])
                    current_centroids.append((cx, cy))

        # Match cells with nearest centroids in current frame
        for cell in cells:
            if len(cell["positions"]) == frame_idx:  # Only track cells found in previous frame
                prev_pos = cell["positions"][-1]

                if current_centroids:
                    # Calculate distances to all current centroids
                    distances = [
                        np.sqrt((prev_pos[0] - c[0]) ** 2 + (prev_pos[1] - c[1]) ** 2) for c in current_centroids
                    ]
                    min_idx = np.argmin(distances)

                    # Only match if distance is below threshold (prevents incorrect matching)
                    if distances[min_idx] < 50:  # Threshold distance in pixels
                        cell["positions"].append(current_centroids[min_idx])
                        cell["frame_indices"].append(frame_idx)
                        current_centroids.pop(min_idx)  # Remove matched centroid

    # Step 4: Calculate motility features for each cell
    cell_features = []

    for cell in cells:
        # Only analyze cells tracked for at least 3 frames
        if len(cell["positions"]) < 3:
            continue

        # Calculate displacements between consecutive positions
        displacements = []
        for i in range(1, len(cell["positions"])):
            prev_pos = cell["positions"][i - 1]
            curr_pos = cell["positions"][i]
            displacement = np.sqrt((curr_pos[0] - prev_pos[0]) ** 2 + (curr_pos[1] - prev_pos[1]) ** 2)
            displacements.append(displacement)

        # Calculate speed (pixels per frame)
        avg_speed = np.mean(displacements)

        # Calculate directionality (displacement from start to end / total path length)
        start_pos = cell["positions"][0]
        end_pos = cell["positions"][-1]
        net_displacement = np.sqrt((end_pos[0] - start_pos[0]) ** 2 + (end_pos[1] - start_pos[1]) ** 2)
        total_path_length = np.sum(displacements)
        directionality = net_displacement / total_path_length if total_path_length > 0 else 0

        # Calculate mean squared displacement
        msd = np.mean(
            [
                np.sqrt((cell["positions"][i][0] - start_pos[0]) ** 2 + (cell["positions"][i][1] - start_pos[1]) ** 2)
                for i in range(1, len(cell["positions"]))
            ]
        )

        # Calculate track duration
        duration = cell["frame_indices"][-1] - cell["frame_indices"][0]

        cell_features.append(
            {
                "cell_id": cell["id"],
                "avg_speed": avg_speed,
                "directionality": directionality,
                "msd": msd,
                "track_duration": duration,
                "track_length": len(cell["positions"]),
            }
        )

    # Step 5: Cluster cells based on motility features
    if len(cell_features) < num_clusters:
        return f"Error: Not enough cells ({len(cell_features)}) to form {num_clusters} clusters. Try reducing num_clusters."

    # Create feature matrix for clustering
    feature_df = pd.DataFrame(cell_features)
    feature_matrix = feature_df[["avg_speed", "directionality", "msd"]].values

    # Normalize features
    feature_matrix = (feature_matrix - np.mean(feature_matrix, axis=0)) / np.std(feature_matrix, axis=0)

    # Perform k-means clustering
    kmeans = KMeans(n_clusters=num_clusters, random_state=42)
    clusters = kmeans.fit_predict(feature_matrix)

    # Add cluster assignments to dataframe
    feature_df["cluster"] = clusters

    # Save results to CSV
    results_file = os.path.join(output_dir, "cell_motility_features.csv")
    feature_df.to_csv(results_file, index=False)

    # Calculate cluster statistics
    cluster_stats = feature_df.groupby("cluster").agg(
        {
            "avg_speed": ["mean", "std"],
            "directionality": ["mean", "std"],
            "msd": ["mean", "std"],
            "cell_id": "count",
        }
    )

    # Save cluster statistics
    stats_file = os.path.join(output_dir, "cluster_statistics.csv")
    cluster_stats.to_csv(stats_file)

    # Create research log
    log = f'''
Cell Motility Quantification and Clustering Analysis
===================================================

Analysis Steps:
1. Loaded {len(image_files)} time-lapse microscopy images
2. Detected and tracked {len(cells)} initial cells across time frames
3. Calculated motility features for {len(cell_features)} cells with sufficient tracking data
4. Performed k-means clustering to identify {num_clusters} distinct motility patterns

Results Summary:
- Detected {len(cells)} cells in the first frame
- Successfully tracked {len(cell_features)} cells across multiple frames
- Clustered cells into {num_clusters} motility pattern groups

Cluster Statistics:
{cluster_stats.to_string()}

Output Files:
- Cell motility features saved to: {results_file}
- Cluster statistics saved to: {stats_file}

Analysis Notes:
- Features used for clustering: average speed, directionality, and mean squared displacement
- Cells were required to be tracked for at least 3 frames to be included in the analysis
'''

    # Save research log
    log_file = os.path.join(output_dir, "research_log.txt")
    with open(log_file, "w") as f:
        f.write(log)

    return log

# Execute the function
try:
    result = quantify_and_cluster_cell_motility(
        image_sequence_path=auto_convert(os.environ.get("PARAM_IMAGE_SEQUENCE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
        num_clusters=auto_convert(os.environ.get("PARAM_NUM_CLUSTERS", "3")),
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
    "function": "quantify_and_cluster_cell_motility",
    "domain": "cell_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("quantify_and_cluster_cell_motility_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("quantify_and_cluster_cell_motility_output.txt", "w") as f:
    f.write("Biomni: Quantify And Cluster Cell Motility" + NL)
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
        biomni_function: "quantify_and_cluster_cell_motility"
    END_VERSIONS
    """
}

workflow QUANTIFY_AND_CLUSTER_CELL_MOTILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    QUANTIFY_AND_CLUSTER_CELL_MOTILITY(ch_input)

    emit:
    results = QUANTIFY_AND_CLUSTER_CELL_MOTILITY.out.results
    output = QUANTIFY_AND_CLUSTER_CELL_MOTILITY.out.output
    versions = QUANTIFY_AND_CLUSTER_CELL_MOTILITY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    QUANTIFY_AND_CLUSTER_CELL_MOTILITY_WORKFLOW(ch_input)

    QUANTIFY_AND_CLUSTER_CELL_MOTILITY_WORKFLOW.out.output.view { "Output: $it" }
}
