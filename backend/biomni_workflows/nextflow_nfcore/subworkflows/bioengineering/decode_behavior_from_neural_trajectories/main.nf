#!/usr/bin/env nextflow
/*
 * bioengineering/decode_behavior_from_neural_trajectories
 * Model neural activity trajectories and decode behavioral variables.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Use null to trigger synthetic data generation for testing
params.neural_data = null
params.behavioral_data = null
params.n_components = '10'
params.output_dir = './'

process DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("decode_behavior_from_neural_trajectories_results.json"), emit: results
    tuple val(meta), path("decode_behavior_from_neural_trajectories_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_NEURAL_DATA="${params.neural_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BEHAVIORAL_DATA="${params.behavioral_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N_COMPONENTS="${params.n_components?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def decode_behavior_from_neural_trajectories(neural_data, behavioral_data, n_components=10, output_dir="./"):
    '''Model neural activity trajectories and decode behavioral variables.

    Parameters
    ----------
    neural_data : numpy.ndarray
        Neural spiking activity data, shape (n_timepoints, n_neurons)
    behavioral_data : numpy.ndarray
        Behavioral data, shape (n_timepoints, n_behavioral_variables)
    n_components : int, optional
        Number of principal components to use for dimensionality reduction, default is 10
    output_dir : str, optional
        Directory to save output files, default is "./"

    Returns
    -------
    str
        Research log summarizing the steps taken and results

    '''
    import os
    import pickle

    import matplotlib.pyplot as plt
    import numpy as np
    from sklearn.decomposition import PCA
    from sklearn.metrics import mean_squared_error
    from sklearn.model_selection import train_test_split

    # Validate inputs - use defaults if None
    if n_components is None:
        n_components = 10
    if output_dir is None:
        output_dir = "./"
    n_components = int(n_components)

    # Generate synthetic data if no input provided
    if neural_data is None or behavioral_data is None:
        np.random.seed(42)
        n_timepoints = 1000
        n_neurons = 50
        n_behavioral = 3

        # Generate synthetic neural data (simulated firing rates)
        neural_data = np.random.poisson(5, (n_timepoints, n_neurons)).astype(float)
        # Generate correlated behavioral data
        behavioral_data = np.random.randn(n_timepoints, n_behavioral)

    neural_data = np.array(neural_data)
    behavioral_data = np.array(behavioral_data)

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Initialize research log
    log = "# Neural Trajectory Modeling and Decoding Research Log\\n\\n"

    # Step 1: Preprocess the data
    log += "## Step 1: Data Preprocessing\\n"
    log += f"- Neural data shape: {neural_data.shape}\\n"
    log += f"- Behavioral data shape: {behavioral_data.shape}\\n"

    # Check for NaN values and replace with zeros
    neural_data = np.nan_to_num(neural_data)
    behavioral_data = np.nan_to_num(behavioral_data)

    # Split data into training and testing sets
    X_train, X_test, y_train, y_test = train_test_split(neural_data, behavioral_data, test_size=0.2, random_state=42)
    log += f"- Training set size: {X_train.shape[0]} samples\\n"
    log += f"- Testing set size: {X_test.shape[0]} samples\\n\\n"

    # Step 2: Dimensionality reduction with PCA
    log += "## Step 2: Dimensionality Reduction\\n"
    log += f"- Reducing neural data from {neural_data.shape[1]} dimensions to {n_components} components\\n"

    pca = PCA(n_components=n_components)
    X_train_pca = pca.fit_transform(X_train)
    X_test_pca = pca.transform(X_test)

    explained_variance = np.sum(pca.explained_variance_ratio_) * 100
    log += f"- Total variance explained: {explained_variance:.2f}%\\n\\n"

    # Save PCA components visualization
    try:
        plt.figure(figsize=(10, 6))
        plt.bar(range(1, n_components + 1), pca.explained_variance_ratio_)
        plt.xlabel("Principal Component")
        plt.ylabel("Explained Variance Ratio")
        plt.title("PCA Components Explained Variance")
        plt.xticks(range(1, n_components + 1))
        plt.tight_layout()

        pca_plot_path = os.path.join(output_dir, "pca_explained_variance.png")
        plt.savefig(pca_plot_path, dpi=300)
        plt.close()

        log += f"- PCA components visualization saved to: {pca_plot_path}\\n\\n"
    except Exception as e:
        log += f"- Error creating PCA visualization: {str(e)}\\n\\n"

    # Step 3: Train a linear model for decoding
    log += "## Step 3: Trajectory Modeling and Decoding\\n"
    log += "- Training linear regression to decode behavioral variables from neural trajectories\\n"

    # Use LinearRegression instead of KalmanFilter (more widely available)
    from sklearn.linear_model import LinearRegression
    model = LinearRegression()
    model.fit(X_train_pca, y_train)

    # Step 4: Decode behavioral variables
    log += "## Step 4: Decoding Behavioral Variables\\n"

    # Use the linear model to predict behavioral variables
    y_pred = model.predict(X_test_pca)

    # Evaluate performance
    mse = mean_squared_error(y_test, y_pred)
    log += f"- Mean squared error on test set: {mse:.4f}\\n\\n"

    # Save the decoded trajectories visualization
    try:
        if y_test.shape[1] >= 2:
            # Create visualization of true vs. predicted trajectories (first 2 dimensions)
            plt.figure(figsize=(12, 6))

            # First behavioral variable
            plt.subplot(1, 2, 1)
            plt.plot(y_test[:, 0], label="True")
            plt.plot(y_pred[:, 0], label="Predicted")
            plt.xlabel("Time steps")
            plt.ylabel("Behavioral Variable 1")
            plt.title("Decoding Performance - Variable 1")
            plt.legend()

            # Second behavioral variable
            plt.subplot(1, 2, 2)
            plt.plot(y_test[:, 1], label="True")
            plt.plot(y_pred[:, 1], label="Predicted")
            plt.xlabel("Time steps")
            plt.ylabel("Behavioral Variable 2")
            plt.title("Decoding Performance - Variable 2")
            plt.legend()

            plt.tight_layout()

            trajectory_plot_path = os.path.join(output_dir, "decoded_trajectories.png")
            plt.savefig(trajectory_plot_path, dpi=300)
            plt.close()

            log += f"- Decoded trajectories visualization saved to: {trajectory_plot_path}\\n"
    except Exception as e:
        log += f"- Error creating trajectory visualization: {str(e)}\\n"

    # Save the results as a pickle file
    results = {
        "true_behavior": y_test,
        "predicted_behavior": y_pred,
        "pca_model": pca,
        "linear_model": model,
        "mse": mse,
    }

    results_file = os.path.join(output_dir, "neural_decoding_results.pkl")
    with open(results_file, "wb") as f:
        pickle.dump(results, f)

    # Also save a CSV with the first few predicted vs. actual values for easier inspection
    try:
        import pandas as pd

        n_samples = min(100, y_test.shape[0])
        n_vars = y_test.shape[1]

        results_data = {}
        for i in range(n_vars):
            results_data[f"true_var{i + 1}"] = y_test[:n_samples, i]
            results_data[f"pred_var{i + 1}"] = y_pred[:n_samples, i]

        results_df = pd.DataFrame(results_data)
        csv_path = os.path.join(output_dir, "decoding_results_sample.csv")
        results_df.to_csv(csv_path, index=False)

        log += f"- Sample of decoding results saved to: {csv_path}\\n"
    except Exception as e:
        log += f"- Error creating CSV results: {str(e)}\\n"

    log += "\\n## Results\\n"
    log += f"- Full decoded behavioral trajectories saved to: {results_file}\\n"
    log += f"- Decoder performance (MSE): {mse:.4f}\\n"

    # Save the log to a file
    log_file = os.path.join(output_dir, "neural_decoding_log.txt")
    with open(log_file, "w") as f:
        f.write(log)

    log += f"- Analysis log saved to: {log_file}\\n"

    return log

# Execute the function
try:
    result = decode_behavior_from_neural_trajectories(
        neural_data=auto_convert(os.environ.get("PARAM_NEURAL_DATA", "")),
        behavioral_data=auto_convert(os.environ.get("PARAM_BEHAVIORAL_DATA", "")),
        n_components=auto_convert(os.environ.get("PARAM_N_COMPONENTS", "10")),
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
    "function": "decode_behavior_from_neural_trajectories",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("decode_behavior_from_neural_trajectories_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("decode_behavior_from_neural_trajectories_output.txt", "w") as f:
    f.write("Biomni: Decode Behavior From Neural Trajectories" + NL)
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
        biomni_function: "decode_behavior_from_neural_trajectories"
    END_VERSIONS
    """
}

workflow DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES(ch_input)

    emit:
    results = DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES.out.results
    output = DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES.out.output
    versions = DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES_WORKFLOW(ch_input)

    DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES_WORKFLOW.out.output.view { "Output: $it" }
}
