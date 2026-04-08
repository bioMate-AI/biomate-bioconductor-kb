#!/usr/bin/env nextflow
/*
 * pathology/analyze_aortic_diameter_and_geometry
 * Analyze aortic diameter and geometry from cardiovascular imaging data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = './output'

process ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_aortic_diameter_and_geometry_results.json"), emit: results
    tuple val(meta), path("analyze_aortic_diameter_and_geometry_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_aortic_diameter_and_geometry(image_path, output_dir="./output"):
    '''Analyze aortic diameter and geometry from cardiovascular imaging data.

    This function processes cardiovascular imaging data (ultrasound or CT/MRI) to
    measure aortic root diameter, ascending aorta diameter, and calculate
    geometric parameters such as tortuosity and dilation indices.

    Parameters
    ----------
    image_path : str
        Path to the cardiovascular imaging data (DICOM, JPG, PNG)
    output_dir : str, optional
        Directory to save output files (default: "./output")

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

    # Initialize research log
    log = []
    log.append(f"Aortic Diameter and Geometry Analysis - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append(f"Input image: {image_path}")

    # Step 1: Load the image
    log.append("\\n1. Loading and preprocessing image")
    try:
        # Check if file exists
        if not os.path.exists(image_path):
            return f"Error: File {image_path} not found"

        # Load image
        image = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
        if image is None:
            return f"Error: Could not read image {image_path}"

        log.append(f"  - Image loaded: {image.shape[1]}x{image.shape[0]} pixels")

        # Basic preprocessing
        image = cv2.GaussianBlur(image, (5, 5), 0)
        log.append("  - Applied Gaussian blur for noise reduction")

        # Enhance contrast
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        image = clahe.apply(image)
        log.append("  - Enhanced contrast using CLAHE")

    except Exception as e:
        return f"Error during image loading: {str(e)}"

    # Step 2: Segment the aorta
    log.append("\\n2. Aorta segmentation")
    try:
        # Otsu thresholding for initial segmentation
        thresh_val, binary = cv2.threshold(image, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        log.append(f"  - Applied Otsu thresholding (threshold value: {thresh_val})")

        # Morphological operations to clean up the binary image
        kernel = np.ones((3, 3), np.uint8)
        binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
        binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
        log.append("  - Applied morphological operations to refine segmentation")

        # Find contours
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        log.append(f"  - Detected {len(contours)} contours")

        # Assuming the aorta is one of the largest contours
        if len(contours) == 0:
            return "Error: No contours detected in the image"

        # Sort contours by area and take the largest
        contours = sorted(contours, key=cv2.contourArea, reverse=True)
        aorta_contour = contours[0]  # Assuming the largest contour is the aorta
        log.append(f"  - Selected largest contour as aorta (area: {cv2.contourArea(aorta_contour)} px²)")

    except Exception as e:
        return f"Error during aorta segmentation: {str(e)}"

    # Step 3: Measure aortic diameters
    log.append("\\n3. Measuring aortic diameters")
    try:
        # Create a mask of the aorta
        aorta_mask = np.zeros_like(image)
        cv2.drawContours(aorta_mask, [aorta_contour], 0, 255, -1)

        # Find the centerline of the aorta (simplified approach)
        # This is a simplified approach - in a real implementation, skeletonization would be better
        M = cv2.moments(aorta_contour)
        if M["m00"] != 0:
            cx = int(M["m10"] / M["m00"])
            cy = int(M["m01"] / M["m00"])
            log.append(f"  - Aorta centroid: ({cx}, {cy})")
        else:
            cx, cy = 0, 0
            log.append("  - Warning: Could not calculate aorta centroid")

        # Measure aortic root diameter (assuming it's at the bottom of the contour)
        aortic_root_points = sorted(aorta_contour.reshape(-1, 2), key=lambda p: p[1], reverse=True)[:20]
        aortic_root_diameter = np.max([p[0] for p in aortic_root_points]) - np.min([p[0] for p in aortic_root_points])
        log.append(f"  - Aortic root diameter: {aortic_root_diameter:.2f} pixels")

        # Measure ascending aorta diameter (assuming it's at the middle of the contour)
        y_mid = (
            np.min([p[1] for p in aorta_contour.reshape(-1, 2)]) + np.max([p[1] for p in aorta_contour.reshape(-1, 2)])
        ) // 2
        ascending_points = [p for p in aorta_contour.reshape(-1, 2) if abs(p[1] - y_mid) < 10]
        if ascending_points:
            ascending_diameter = np.max([p[0] for p in ascending_points]) - np.min([p[0] for p in ascending_points])
            log.append(f"  - Ascending aorta diameter: {ascending_diameter:.2f} pixels")
        else:
            ascending_diameter = 0
            log.append("  - Warning: Could not measure ascending aorta diameter")

    except Exception as e:
        return f"Error during diameter measurements: {str(e)}"

    # Step 4: Calculate geometric parameters
    log.append("\\n4. Calculating aortic geometry parameters")
    try:
        # Calculate tortuosity (simplified as the ratio of contour length to end-to-end distance)
        contour_length = cv2.arcLength(aorta_contour, closed=True)

        # Find the two most distant points (approximation for end-to-end distance)
        hull = cv2.convexHull(aorta_contour)
        hull_points = hull.reshape(-1, 2)
        max_dist = 0
        for i in range(len(hull_points)):
            for j in range(i + 1, len(hull_points)):
                dist = np.sqrt(
                    (hull_points[i][0] - hull_points[j][0]) ** 2 + (hull_points[i][1] - hull_points[j][1]) ** 2
                )
                max_dist = max(max_dist, dist)

        if max_dist > 0:
            tortuosity = contour_length / max_dist
            log.append(f"  - Aortic tortuosity index: {tortuosity:.2f}")
        else:
            tortuosity = 0
            log.append("  - Warning: Could not calculate tortuosity")

        # Calculate dilation index (ratio of max diameter to min diameter)
        min_diameter = min(aortic_root_diameter, ascending_diameter)
        max_diameter = max(aortic_root_diameter, ascending_diameter)

        if min_diameter > 0:
            dilation_index = max_diameter / min_diameter
            log.append(f"  - Aortic dilation index: {dilation_index:.2f}")
        else:
            dilation_index = 0
            log.append("  - Warning: Could not calculate dilation index")

    except Exception as e:
        return f"Error during geometry calculations: {str(e)}"

    # Step 5: Save results
    log.append("\\n5. Saving results")
    try:
        # Create a visual output
        output_image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
        cv2.drawContours(output_image, [aorta_contour], 0, (0, 255, 0), 2)

        # Mark diameters
        cv2.circle(output_image, (cx, cy), 5, (0, 0, 255), -1)

        # Save the output image
        output_filename = os.path.join(output_dir, f"aorta_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png")
        cv2.imwrite(output_filename, output_image)
        log.append(f"  - Saved annotated image to: {output_filename}")

        # Save measurements to a text file
        measurements_filename = os.path.join(
            output_dir,
            f"aorta_measurements_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt",
        )
        with open(measurements_filename, "w") as f:
            f.write(f"Aortic Root Diameter: {aortic_root_diameter:.2f} pixels\\n")
            f.write(f"Ascending Aorta Diameter: {ascending_diameter:.2f} pixels\\n")
            f.write(f"Tortuosity Index: {tortuosity:.2f}\\n")
            f.write(f"Dilation Index: {dilation_index:.2f}\\n")
        log.append(f"  - Saved measurements to: {measurements_filename}")

    except Exception as e:
        return f"Error during saving results: {str(e)}"

    # Step 6: Summarize findings
    log.append("\\n6. Summary of findings")
    log.append(f"  - Aortic root diameter: {aortic_root_diameter:.2f} pixels")
    log.append(f"  - Ascending aorta diameter: {ascending_diameter:.2f} pixels")
    log.append(f"  - Tortuosity index: {tortuosity:.2f}")
    log.append(f"  - Dilation index: {dilation_index:.2f}")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_aortic_diameter_and_geometry(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./output")),
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
    "function": "analyze_aortic_diameter_and_geometry",
    "domain": "pathology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_aortic_diameter_and_geometry_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_aortic_diameter_and_geometry_output.txt", "w") as f:
    f.write("Biomni: Analyze Aortic Diameter And Geometry" + NL)
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
        biomni_function: "analyze_aortic_diameter_and_geometry"
    END_VERSIONS
    """
}

workflow ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY(ch_input)

    emit:
    results = ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY.out.results
    output = ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY.out.output
    versions = ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY_WORKFLOW(ch_input)

    ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY_WORKFLOW.out.output.view { "Output: $it" }
}
