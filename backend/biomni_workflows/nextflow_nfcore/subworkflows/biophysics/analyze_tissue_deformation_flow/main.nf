#!/usr/bin/env nextflow
/*
 * biophysics/analyze_tissue_deformation_flow
 * Quantify tissue deformation and flow dynamics from microscopy image sequence.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Test with synthetic image sequence dimensions [frames, height, width]
params.image_sequence = '[[100, 100], [100, 100], [100, 100], [100, 100], [100, 100]]'
params.output_dir = 'results'
params.pixel_scale = '1.0'

process ANALYZE_TISSUE_DEFORMATION_FLOW {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_tissue_deformation_flow_results.json"), emit: results
    tuple val(meta), path("analyze_tissue_deformation_flow_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_SEQUENCE="${params.image_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PIXEL_SCALE="${params.pixel_scale?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_tissue_deformation_flow(image_sequence, output_dir="results", pixel_scale=1.0):
    '''Quantify tissue deformation and flow dynamics from microscopy image sequence.

    Parameters
    ----------
    image_sequence : list or numpy.ndarray
        Sequence of microscopy images (either a list of file paths or a 3D numpy array [time, height, width])
    output_dir : str, optional
        Directory to save results (default: "results")
    pixel_scale : float, optional
        Physical scale of pixels (e.g., μm/pixel) for proper scaling of metrics (default: 1.0)

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    from datetime import datetime

    import cv2
    import numpy as np

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Load images if paths are provided
    if isinstance(image_sequence[0], str):
        loaded_images = []
        for img_path in image_sequence:
            img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)
            if img is None:
                return f"Error: Could not load image {img_path}"
            loaded_images.append(img)
        frames = np.array(loaded_images)
    else:
        frames = image_sequence
        # Convert to grayscale if needed
        if len(frames.shape) > 3:  # Has color channels
            frames = np.array(
                [cv2.cvtColor(frame, cv2.COLOR_RGB2GRAY) if frame.shape[-1] == 3 else frame for frame in frames]
            )

    # Parameters for optical flow
    lk_params = {
        "winSize": (15, 15),
        "maxLevel": 2,
        "criteria": (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 10, 0.03),
    }

    # Metrics storage
    num_frames = len(frames)
    flow_fields = []
    divergence_maps = []
    curl_maps = []
    strain_maps = []

    # Log initialization
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log = f"Tissue Deformation and Flow Analysis - {timestamp}\\n"
    log += f"Number of frames analyzed: {num_frames}\\n"
    log += f"Image dimensions: {frames[0].shape[0]}x{frames[0].shape[1]} pixels\\n"
    log += f"Pixel scale: {pixel_scale} units/pixel\\n\\n"
    log += "Analysis Steps:\\n"

    # Create feature points grid (evenly spaced points)
    y, x = np.mgrid[0 : frames[0].shape[0] : 20, 0 : frames[0].shape[1] : 20]
    feature_points = np.stack((x.flatten(), y.flatten()), axis=1).astype(np.float32)

    for i in range(num_frames - 1):
        log += f"Processing frame pair {i} and {i + 1}...\\n"

        # Calculate optical flow using Lucas-Kanade
        prev_frame = frames[i]
        next_frame = frames[i + 1]

        # Compute flow for the grid points
        next_points, status, _ = cv2.calcOpticalFlowPyrLK(prev_frame, next_frame, feature_points, None, **lk_params)

        # Filter valid points
        valid_idx = status.flatten() == 1
        valid_prev_points = feature_points[valid_idx]
        valid_next_points = next_points[valid_idx]

        # Calculate displacement vectors
        displacement = valid_next_points - valid_prev_points
        points = valid_prev_points

        # Interpolate flow field to full image resolution
        flow_field = np.zeros((frames[0].shape[0], frames[0].shape[1], 2), dtype=np.float32)

        # Simple nearest-neighbor interpolation for demonstration
        # In a production system, you might use more sophisticated interpolation
        for j, (x, y) in enumerate(points.astype(int)):
            if 0 <= y < flow_field.shape[0] and 0 <= x < flow_field.shape[1]:
                flow_field[y, x] = displacement[j]

        # Calculate derivatives for deformation analysis
        u = flow_field[:, :, 0]  # x-component of flow
        v = flow_field[:, :, 1]  # y-component of flow

        # Calculate divergence (expansion/contraction)
        # Using central differences for derivatives
        u_x = cv2.Sobel(u, cv2.CV_64F, 1, 0, ksize=3) / (8.0 * pixel_scale)
        v_y = cv2.Sobel(v, cv2.CV_64F, 0, 1, ksize=3) / (8.0 * pixel_scale)
        divergence = u_x + v_y

        # Calculate curl (rotation)
        u_y = cv2.Sobel(u, cv2.CV_64F, 0, 1, ksize=3) / (8.0 * pixel_scale)
        v_x = cv2.Sobel(v, cv2.CV_64F, 1, 0, ksize=3) / (8.0 * pixel_scale)
        curl = v_x - u_y

        # Calculate strain tensor components
        strain_xx = u_x
        strain_yy = v_y
        strain_xy = 0.5 * (u_y + v_x)

        # Magnitude of strain tensor (Frobenius norm)
        strain_magnitude = np.sqrt(strain_xx**2 + strain_yy**2 + 2 * strain_xy**2)

        # Store results
        flow_fields.append(flow_field)
        divergence_maps.append(divergence)
        curl_maps.append(curl)
        strain_maps.append(strain_magnitude)

        # Visualize flow field
        flow_viz = np.zeros((frames[0].shape[0], frames[0].shape[1], 3), dtype=np.uint8)
        flow_viz[..., 0] = next_frame  # Use next frame as background
        flow_viz[..., 1] = next_frame
        flow_viz[..., 2] = next_frame

        # Draw flow vectors for visualization
        step = 20
        for y in range(0, flow_field.shape[0], step):
            for x in range(0, flow_field.shape[1], step):
                dx, dy = flow_field[y, x]
                if abs(dx) > 0.5 or abs(dy) > 0.5:  # Only draw significant flow
                    cv2.arrowedLine(
                        flow_viz,
                        (x, y),
                        (int(x + dx), int(y + dy)),
                        (0, 255, 0),  # Green
                        1,
                        tipLength=0.3,
                    )

        # Save visualizations
        flow_viz_path = os.path.join(output_dir, f"flow_viz_{i:03d}.png")
        divergence_path = os.path.join(output_dir, f"divergence_{i:03d}.npy")
        curl_path = os.path.join(output_dir, f"curl_{i:03d}.npy")
        strain_path = os.path.join(output_dir, f"strain_{i:03d}.npy")

        cv2.imwrite(flow_viz_path, flow_viz)
        np.save(divergence_path, divergence)
        np.save(curl_path, curl)
        np.save(strain_path, strain_magnitude)

    # Calculate summary statistics
    mean_divergence = np.mean([np.mean(div) for div in divergence_maps])
    max_divergence = np.max([np.max(div) for div in divergence_maps])
    mean_curl = np.mean([np.mean(np.abs(c)) for c in curl_maps])
    mean_strain = np.mean([np.mean(s) for s in strain_maps])

    # Add summary to log
    log += "\\nAnalysis Results:\\n"
    log += f"Mean tissue divergence: {mean_divergence:.6f} (expansion/contraction rate)\\n"
    log += f"Maximum divergence: {max_divergence:.6f}\\n"
    log += f"Mean absolute curl: {mean_curl:.6f} (rotation rate)\\n"
    log += f"Mean strain magnitude: {mean_strain:.6f} (deformation intensity)\\n\\n"

    # Save summary data
    summary_data = {
        "mean_divergence": mean_divergence,
        "max_divergence": max_divergence,
        "mean_curl": mean_curl,
        "mean_strain": mean_strain,
    }
    summary_path = os.path.join(output_dir, "deformation_summary.npy")
    np.save(summary_path, summary_data)

    log += "Files Generated:\\n"
    log += f"- Flow visualization images: {output_dir}/flow_viz_*.png\\n"
    log += f"- Divergence maps: {output_dir}/divergence_*.npy\\n"
    log += f"- Curl maps: {output_dir}/curl_*.npy\\n"
    log += f"- Strain maps: {output_dir}/strain_*.npy\\n"
    log += f"- Summary statistics: {output_dir}/deformation_summary.npy\\n"

    return log

# Execute the function
try:
    result = analyze_tissue_deformation_flow(
        image_sequence=auto_convert(os.environ.get("PARAM_IMAGE_SEQUENCE", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "results")),
        pixel_scale=auto_convert(os.environ.get("PARAM_PIXEL_SCALE", "1.0")),
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
    "function": "analyze_tissue_deformation_flow",
    "domain": "biophysics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_tissue_deformation_flow_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_tissue_deformation_flow_output.txt", "w") as f:
    f.write("Biomni: Analyze Tissue Deformation Flow" + NL)
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
        biomni_function: "analyze_tissue_deformation_flow"
    END_VERSIONS
    """
}

workflow ANALYZE_TISSUE_DEFORMATION_FLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_TISSUE_DEFORMATION_FLOW(ch_input)

    emit:
    results = ANALYZE_TISSUE_DEFORMATION_FLOW.out.results
    output = ANALYZE_TISSUE_DEFORMATION_FLOW.out.output
    versions = ANALYZE_TISSUE_DEFORMATION_FLOW.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_TISSUE_DEFORMATION_FLOW_WORKFLOW(ch_input)

    ANALYZE_TISSUE_DEFORMATION_FLOW_WORKFLOW.out.output.view { "Output: $it" }
}
