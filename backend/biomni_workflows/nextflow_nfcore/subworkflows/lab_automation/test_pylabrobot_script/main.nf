#!/usr/bin/env nextflow
/*
 * lab_automation/test_pylabrobot_script
 * Test a PyLabRobot script using simulation and validation.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Simple PyLabRobot script that sets up a liquid handler and performs a basic transfer
params.script_input = '''
from pylabrobot.liquid_handling import LiquidHandler
from pylabrobot.liquid_handling.backends import LiquidHandlerChatterboxBackend
from pylabrobot.resources.hamilton import STARLetDeck
from pylabrobot.resources import Cor_96_wellplate_360ul_Fb, HTF_L

async def main():
    # Initialize liquid handler with simulation backend
    backend = LiquidHandlerChatterboxBackend()
    deck = STARLetDeck()
    lh = LiquidHandler(backend=backend, deck=deck)

    await lh.setup()

    # Add resources to deck
    tip_rack = HTF_L(name="tip_rack")
    plate = Cor_96_wellplate_360ul_Fb(name="plate")

    deck.assign_child_resource(tip_rack, rails=1)
    deck.assign_child_resource(plate, rails=7)

    # Pick up tips and aspirate/dispense
    await lh.pick_up_tips(tip_rack["A1:H1"])
    await lh.aspirate(plate["A1:H1"], vols=[100]*8)
    await lh.dispense(plate["A2:H2"], vols=[100]*8)
    await lh.drop_tips(tip_rack["A1:H1"])

    await lh.stop()

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
'''
params.enable_tracking = 'true'
params.timeout_seconds = 60
params.save_test_report = 'false'
params.test_report_dir = './test_reports'

process TEST_PYLABROBOT_SCRIPT {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("test_pylabrobot_script_results.json"), emit: results
    tuple val(meta), path("test_pylabrobot_script_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SCRIPT_INPUT="${params.script_input?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENABLE_TRACKING="${params.enable_tracking?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIMEOUT_SECONDS="${params.timeout_seconds?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAVE_TEST_REPORT="${params.save_test_report?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TEST_REPORT_DIR="${params.test_report_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import json
import asyncio
import os
import tempfile
import ast
from typing import Any
import time
import traceback
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

def _validate_pylabrobot_imports(script_content: str) -> dict[str, Any]:
    '''Validate that all PyLabRobot imports in the script are available.'''
    import_errors = []
    import_warnings = []

    try:
        # Parse the script to find import statements
        tree = ast.parse(script_content)
        pylabrobot_imports = []

        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if "pylabrobot" in alias.name:
                        pylabrobot_imports.append(alias.name)
            elif isinstance(node, ast.ImportFrom):
                if node.module and "pylabrobot" in node.module:
                    for alias in node.names:
                        full_import = f"{node.module}.{alias.name}"
                        pylabrobot_imports.append(full_import)

        # Try to import each PyLabRobot module/class
        for import_name in pylabrobot_imports:
            try:
                # Handle different import patterns
                if "." in import_name:
                    parts = import_name.split(".")
                    module_parts = parts[:-1]
                    class_name = parts[-1]

                    # Import the module
                    module_name = ".".join(module_parts)
                    module = __import__(module_name, fromlist=[class_name])

                    # Check if the class/function exists
                    if not hasattr(module, class_name):
                        import_errors.append(f"Cannot find '{class_name}' in module '{module_name}'")
                else:
                    # Direct module import
                    __import__(import_name)

            except ImportError as e:
                import_errors.append(f"Failed to import '{import_name}': {str(e)}")
            except Exception as e:
                import_warnings.append(f"Warning validating import '{import_name}': {str(e)}")

    except Exception as e:
        import_errors.append(f"Error parsing imports: {str(e)}")

    return {"success": len(import_errors) == 0, "errors": import_errors, "warnings": import_warnings}

def _modify_script_for_testing(script_content: str, enable_tracking: bool) -> str:
    '''Modify script to use simulation backends and enable tracking.'''
    modified_script = script_content

    # Replace STARBackend with LiquidHandlerChatterboxBackend for simulation
    replacements = [("STARBackend()", "LiquidHandlerChatterboxBackend()")]

    for old, new in replacements:
        modified_script = modified_script.replace(old, new)

    lines = modified_script.split("\\n")
    insert_at = 0
    for i, line in enumerate(lines):
        if line.strip().startswith(("from ", "import ", "#")):
            insert_at = i + 1
            continue
        if line.strip().startswith(("async def", "def", "class", "if __name__")):
            break
        insert_at = i + 1
    lines.insert(insert_at, "from pylabrobot.liquid_handling.backends import LiquidHandlerChatterboxBackend")
    modified_script = "\\n".join(lines)

    # Add tracking imports and setup at the beginning
    if enable_tracking:
        tracking_setup = '''
# Enable PyLabRobot tracking for validation
try:
    from pylabrobot.resources import set_tip_tracking, set_volume_tracking
    set_tip_tracking(True)
    set_volume_tracking(True)
except ImportError:
    pass  # Tracking not available in this PyLabRobot version

'''
    else:
        tracking_setup = '''
# Disable PyLabRobot tracking for testing
try:
    from pylabrobot.resources import set_tip_tracking, set_volume_tracking
    set_tip_tracking(False)
    set_volume_tracking(False)
except ImportError:
    pass  # Tracking not available in this PyLabRobot version

'''

    # Insert after imports but before main function
    lines = modified_script.split("\\n")
    insert_index = 0
    for i, line in enumerate(lines):
        if (
            line.strip().startswith("async def")
            or line.strip().startswith("def")
            or line.strip().startswith("if __name__")
        ):
            insert_index = i
            break

    lines.insert(insert_index, tracking_setup)
    modified_script = "\\n".join(lines)

    return modified_script

def _execute_script_safely(script_content: str, timeout_seconds: int) -> dict[str, Any]:
    '''Execute the modified script in a safe environment.'''
    errors = []
    warnings = []
    summary = {"operations_performed": 0, "tips_used": 0, "liquid_transferred": 0.0}

    try:
        # Create a temporary file for the script
        with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False) as f:
            f.write(script_content)
            temp_script_path = f.name

        # Execute the script with timeout
        try:
            # Use threading for timeout control
            import threading

            result = None
            exception = None

            def target():
                nonlocal result, exception
                try:
                    result = _run_script_with_monitoring(temp_script_path)
                except Exception as e:
                    exception = e

            thread = threading.Thread(target=target)
            thread.start()
            thread.join(timeout=timeout_seconds)

            if thread.is_alive():
                errors.append(f"Script execution timed out after {timeout_seconds} seconds")
            elif exception:
                raise exception
            elif result:
                summary.update(result.get("summary", {}))
                warnings.extend(result.get("warnings", []))

                return {"success": True, "summary": summary, "errors": errors, "warnings": warnings}
            else:
                errors.append("Script execution completed but returned no result")
        except Exception as e:
            errors.append(f"Script execution failed: {str(e)}")

    except Exception as e:
        errors.append(f"Failed to prepare script execution: {str(e)}")
    finally:
        # Clean up temporary file
        try:
            os.unlink(temp_script_path)
        except OSError:
            pass

    return {"success": False, "summary": summary, "errors": errors, "warnings": warnings}

def _run_script_with_monitoring(script_path: str) -> dict[str, Any]:
    '''Run the script and monitor its execution.'''
    # Note: This is a simplified version. In practice, you might want to
    # use subprocess or other isolation methods for safety

    warnings = []
    summary = {"operations_performed": 0, "tips_used": 0, "liquid_transferred": 0.0}

    try:
        # Read and execute the script
        with open(script_path) as f:
            script_content = f.read()

        # Create a namespace for execution
        namespace = {
            "__name__": "__main__",
            "__file__": script_path,
        }

        # Execute the script
        exec(script_content, namespace)

        # If the script has a main function, run it
        if "main" in namespace and callable(namespace["main"]):
            if asyncio.iscoroutinefunction(namespace["main"]):
                # Run async main function using asyncio.run if not in event loop
                try:
                    asyncio.get_running_loop()
                    # We're in an event loop, create a new thread to run asyncio.run
                    import threading

                    result = None
                    exception = None

                    def run_async():
                        nonlocal result, exception
                        try:
                            asyncio.run(namespace["main"]())
                        except Exception as e:
                            exception = e

                    thread = threading.Thread(target=run_async)
                    thread.start()
                    thread.join()

                    if exception:
                        raise exception
                except RuntimeError:
                    # No event loop running, safe to use asyncio.run
                    asyncio.run(namespace["main"]())
            else:
                namespace["main"]()

        # Execution summary collection can be added here in the future once
        # PyLabRobot exposes reliable runtime statistics.
    except Exception as e:
        raise Exception(f"Script execution error: {str(e)}") from e

    return {"summary": summary, "warnings": warnings}

def _create_test_result(
    success: bool,
    test_results: dict,
    execution_summary: dict,
    errors: list,
    warnings: list,
    start_time: float,
    save_test_report: bool,
    test_report_dir: str,
) -> dict[str, Any]:
    '''Create the final test result dictionary.'''
    # Calculate total execution time
    total_execution_time = time.time() - start_time
    execution_summary["total_execution_time"] = total_execution_time

    result = {
        "success": success,
        "test_results": test_results,
        "execution_summary": execution_summary,
        "errors": errors,
        "warnings": warnings,
    }

    # Save test report if requested
    if save_test_report:
        try:
            if test_report_dir:
                os.makedirs(test_report_dir, exist_ok=True)
            else:
                test_report_dir = tempfile.gettempdir()

            timestamp = time.strftime("%Y%m%d_%H%M%S")
            report_filename = f"pylabrobot_test_report_{timestamp}.json"
            report_path = os.path.join(test_report_dir, report_filename)

            with open(report_path, "w") as f:
                json.dump(result, f, indent=2)

            result["test_report_path"] = report_path

        except Exception as e:
            warnings.append(f"Failed to save test report: {str(e)}")

    return result

def test_pylabrobot_script(
    script_input: str,
    enable_tracking: bool = False,
    timeout_seconds: int = 60,
    save_test_report: bool = False,
    test_report_dir: str = None,
) -> dict[str, Any]:
    '''Test a PyLabRobot script using simulation and validation.

    Uses PyLabRobot's ChatterboxBackend and tracking systems to
    validate generated scripts without requiring physical hardware.

    Args:
        script_input (str): Either the PyLabRobot script code as a string, or a file path to a .py file
        enable_tracking (bool): Enable tip and volume tracking for error detection
        timeout_seconds (int): Maximum execution time before timeout
        save_test_report (bool): Whether to save detailed test results to file
        test_report_dir (str, optional): Directory to save test reports

    Returns:
        dict: Dictionary containing:
            - success (bool): Whether the script passed all tests
            - test_results (dict): Detailed test results for each validation step
            - execution_summary (dict): Summary of operations performed
            - errors (list): List of errors encountered
            - warnings (list): List of warnings
            - test_report_path (str): Path to saved report if requested

    Example:
        >>> # Test with script content string
        >>> script = "async def main(): ..."
        >>> result = test_pylabrobot_script(script)

        >>> # Test with file path
        >>> result = test_pylabrobot_script("/path/to/script.py")

        >>> if result["success"]:
        ...     print("Test passed!")
        ... else:
        ...     print(f"Test failed: {result['errors']}")
    '''
    start_time = time.time()
    test_results = {
        "syntax_valid": False,
        "imports_valid": False,
        "simulation_successful": False,
        "tracking_enabled": enable_tracking,
    }
    execution_summary = {"operations_performed": 0, "tips_used": 0, "liquid_transferred": 0.0, "execution_time": 0.0}
    errors = []
    warnings = []

    # Determine if input is a file path or script content
    script_content = ""
    try:
        # Check if input looks like a file path and exists
        if (
            script_input.endswith(".py") and os.path.isfile(script_input) and "\\n" not in script_input[:100]
        ):  # Basic heuristic: file paths shouldn't have newlines
            try:
                with open(script_input, encoding="utf-8") as f:
                    script_content = f.read()
                test_results["input_type"] = "file"
                test_results["file_path"] = script_input
            except Exception as e:
                errors.append(f"Failed to read script file '{script_input}': {str(e)}")
                return _create_test_result(
                    False,
                    test_results,
                    execution_summary,
                    errors,
                    warnings,
                    start_time,
                    save_test_report,
                    test_report_dir,
                )
        else:
            # Treat as script content string
            script_content = script_input
            test_results["input_type"] = "string"

    except Exception as e:
        errors.append(f"Failed to process script input: {str(e)}")
        return _create_test_result(
            False, test_results, execution_summary, errors, warnings, start_time, save_test_report, test_report_dir
        )

    if not script_content.strip():
        errors.append("Script content is empty")
        return _create_test_result(
            False, test_results, execution_summary, errors, warnings, start_time, save_test_report, test_report_dir
        )

    try:
        # Step 1: Syntax Validation
        try:
            ast.parse(script_content)
            test_results["syntax_valid"] = True
        except SyntaxError as e:
            errors.append(f"Syntax Error: {str(e)} at line {e.lineno}")
            return _create_test_result(
                False, test_results, execution_summary, errors, warnings, start_time, save_test_report, test_report_dir
            )

        # Step 2: Import Validation
        import_results = _validate_pylabrobot_imports(script_content)
        test_results["imports_valid"] = import_results["success"]
        if not import_results["success"]:
            errors.extend(import_results["errors"])
            warnings.extend(import_results["warnings"])

        # Step 3: Replace backends with ChatterboxBackend for simulation
        modified_script = _modify_script_for_testing(script_content, enable_tracking)

        # Step 4: Execute script in controlled environment
        execution_result = _execute_script_safely(modified_script, timeout_seconds)

        test_results["simulation_successful"] = execution_result["success"]
        execution_summary.update(execution_result["summary"])

        if not execution_result["success"]:
            errors.extend(execution_result["errors"])

        warnings.extend(execution_result.get("warnings", []))

    except Exception as e:
        errors.append(f"Unexpected error during testing: {str(e)}")
        traceback.print_exc()

    overall_success = (
        test_results["syntax_valid"] and test_results["imports_valid"] and test_results["simulation_successful"]
    )

    return _create_test_result(
        overall_success,
        test_results,
        execution_summary,
        errors,
        warnings,
        start_time,
        save_test_report,
        test_report_dir,
    )

# Execute the function
try:
    result = test_pylabrobot_script(
        script_input=auto_convert(os.environ.get("PARAM_SCRIPT_INPUT", "")),
        enable_tracking=auto_convert(os.environ.get("PARAM_ENABLE_TRACKING", "")),
        timeout_seconds=auto_convert(os.environ.get("PARAM_TIMEOUT_SECONDS", "60")),
        save_test_report=auto_convert(os.environ.get("PARAM_SAVE_TEST_REPORT", "")),
        test_report_dir=auto_convert(os.environ.get("PARAM_TEST_REPORT_DIR", "")),
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
    "function": "test_pylabrobot_script",
    "domain": "lab_automation",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("test_pylabrobot_script_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("test_pylabrobot_script_output.txt", "w") as f:
    f.write("Biomni: Test Pylabrobot Script" + NL)
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
        biomni_function: "test_pylabrobot_script"
    END_VERSIONS
    """
}

workflow TEST_PYLABROBOT_SCRIPT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    TEST_PYLABROBOT_SCRIPT(ch_input)

    emit:
    results = TEST_PYLABROBOT_SCRIPT.out.results
    output = TEST_PYLABROBOT_SCRIPT.out.output
    versions = TEST_PYLABROBOT_SCRIPT.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    TEST_PYLABROBOT_SCRIPT_WORKFLOW(ch_input)

    TEST_PYLABROBOT_SCRIPT_WORKFLOW.out.output.view { "Output: $it" }
}
