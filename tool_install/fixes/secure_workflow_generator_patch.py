"""
Secure Workflow Generator Patch

Adds user approval requirement to EnhancedWorkflowGenerator.
This is a drop-in replacement for the auto_install_workflow_tools method.
"""

from typing import Dict, List, Tuple
import logging

log = logging.getLogger(__name__)


def request_tool_installation_approval(tool_ids: List[str], tool_source: str = "local") -> bool:
    """
    Request user approval for tool installation.

    Args:
        tool_ids: List of tool IDs to install
        tool_source: Source of tools (local, toolshed, etc.)

    Returns:
        True if user approves, False otherwise
    """
    if not tool_ids:
        return True

    print("\n" + "=" * 70)
    print("🔐 TOOL INSTALLATION APPROVAL REQUEST")
    print("=" * 70)
    print(f"\nThe workflow requires installation of {len(tool_ids)} tool(s):")
    print(f"Source: {tool_source}\n")

    for i, tool_id in enumerate(tool_ids, 1):
        # Classify tool risk level
        risk = classify_tool_risk(tool_id, tool_source)
        risk_emoji = {"low": "🟢", "medium": "🟡", "high": "🟠", "critical": "🔴"}[risk]

        print(f"{i}. {risk_emoji} {tool_id} (risk: {risk})")

    print("\n" + "=" * 70)
    print("\nWhat these tools can do:")
    print("  • Execute commands on your system")
    print("  • Access your data files")
    print("  • Make network requests (if not sandboxed)")
    print("  • Consume system resources")

    if tool_source == "local":
        print("\n⚠️  WARNING: Local tools have NOT been verified by Galaxy ToolShed")
        print("   Please review tool source code before approving")

    print("\n" + "=" * 70)

    while True:
        response = input("\nApprove installation of these tools? (yes/no/details): ").strip().lower()

        if response == "yes":
            log.info(f"User approved installation of {len(tool_ids)} tools")
            return True

        elif response == "no":
            log.info(f"User rejected installation of {len(tool_ids)} tools")
            return False

        elif response == "details":
            print_tool_details(tool_ids, tool_source)

        else:
            print("Please enter 'yes', 'no', or 'details'")


def classify_tool_risk(tool_id: str, tool_source: str) -> str:
    """
    Classify tool installation risk level.

    Args:
        tool_id: Tool identifier
        tool_source: Tool source (local, toolshed)

    Returns:
        Risk level: low, medium, high, critical
    """
    # ToolShed tools are generally lower risk (verified)
    if tool_source == "toolshed":
        return "low"

    # Local tools are higher risk
    if tool_source == "local":
        # Check for known dangerous patterns in ID
        dangerous_keywords = ['eval', 'exec', 'system', 'shell', 'remote', 'download']

        for keyword in dangerous_keywords:
            if keyword in tool_id.lower():
                return "critical"

        # nfcore tools are medium risk (community maintained)
        if "nfcore" in tool_id:
            return "medium"

        # Other local tools are high risk
        return "high"

    return "medium"


def print_tool_details(tool_ids: List[str], tool_source: str):
    """Print detailed information about tools to be installed."""
    print("\n" + "=" * 70)
    print("TOOL INSTALLATION DETAILS")
    print("=" * 70)

    for tool_id in tool_ids:
        print(f"\nTool: {tool_id}")
        print(f"Source: {tool_source}")
        print(f"Risk Level: {classify_tool_risk(tool_id, tool_source)}")

        # Try to provide more context
        if "nfcore" in tool_id:
            print("Info: Part of nf-core bioinformatics pipeline tools")
        elif "toolshed" in tool_source:
            print("Info: From Galaxy ToolShed (community verified)")
        else:
            print("Info: Local BioMate tool (not externally verified)")

    print("\n" + "=" * 70)


def secure_auto_install_workflow_tools(self, workflow_dict: Dict) -> Tuple[bool, str, List[str]]:
    """
    Secure version of auto_install_workflow_tools with user approval.

    This is a drop-in replacement for the EnhancedWorkflowGenerator method.
    Add this to enhanced_workflow_generator.py or monkey-patch it.

    Args:
        workflow_dict: Galaxy workflow dictionary

    Returns:
        Tuple of (all_success, message, failed_tools)
    """
    # Use the original validation logic
    available, missing_custom, missing_toolshed = self.tool_installer.validate_workflow_tools(workflow_dict)

    if not missing_custom and not missing_toolshed:
        return True, "All tools already available", []

    log.info(f"Workflow requires: {len(missing_custom)} custom tools, {len(missing_toolshed)} ToolShed tools")

    failed = []

    # Request approval for custom tools
    if missing_custom:
        print(f"\n📦 Custom BioMate Tools Installation Required")

        approved = request_tool_installation_approval(missing_custom, tool_source="local")

        if not approved:
            return False, "User rejected installation of custom tools", missing_custom

        # User approved - proceed with installation
        log.info(f"Installing {len(missing_custom)} custom BioMate tools...")
        custom_results = self.tool_installer.install_missing_tools(missing_custom)
        failed.extend([tool_id for tool_id, (success, _) in custom_results.items() if not success])

    # Request approval for ToolShed tools
    if missing_toolshed:
        print(f"\n📦 Galaxy ToolShed Tools Installation Required")

        approved = request_tool_installation_approval(missing_toolshed, tool_source="toolshed")

        if not approved:
            return False, "User rejected installation of ToolShed tools", missing_toolshed

        # User approved - proceed with installation
        log.info(f"Installing {len(missing_toolshed)} ToolShed tools...")
        toolshed_results = self.tool_installer._install_toolshed_tools(missing_toolshed)

        failed.extend([
            tool_id for tool_id, (success, msg) in toolshed_results.items()
            if not success and "Galaxy will auto-install" not in msg
        ])

    if failed:
        msg = f"Failed to install {len(failed)} tools: {', '.join(failed[:5])}"
        if len(failed) > 5:
            msg += f" and {len(failed) - 5} more"
        return False, msg, failed

    total_installed = len(missing_custom) + len(missing_toolshed)
    msg = f"✅ Successfully installed {total_installed} tools ({len(missing_custom)} custom, {len(missing_toolshed)} ToolShed)"

    return True, msg, []


# Monkey-patch instructions
"""
To apply this patch to your existing EnhancedWorkflowGenerator:

1. Import this module:
   from tool_install.fixes.secure_workflow_generator_patch import secure_auto_install_workflow_tools

2. Replace the method:
   EnhancedWorkflowGenerator.auto_install_workflow_tools = secure_auto_install_workflow_tools

3. Or better yet, directly edit enhanced_workflow_generator.py:
   - Replace the auto_install_workflow_tools method with this secure version
   - Add the helper functions at module level

Example:
    from galaxy.ai.enhanced_workflow_generator import EnhancedWorkflowGenerator
    from tool_install.fixes.secure_workflow_generator_patch import secure_auto_install_workflow_tools

    # Monkey-patch the class
    EnhancedWorkflowGenerator.auto_install_workflow_tools = secure_auto_install_workflow_tools

    # Now all instances will use the secure version
    generator = EnhancedWorkflowGenerator(config)
    result = generator.generate_workflow(request, auto_install_tools=True)
    # User will be prompted for approval before any tools are installed
"""


if __name__ == "__main__":
    # Test the approval flow
    test_tools = [
        "nfcore_fastqc",
        "nfcore_multiqc",
        "custom_data_processor"
    ]

    approved = request_tool_installation_approval(test_tools, tool_source="local")

    print(f"\n{'✅ Approved' if approved else '❌ Rejected'}")
