# BioMate Hospital On Premises Deployment Overview

BioMate’s front engineering team will lead installation, configuration, user onboarding and coordination with the hospital’s IT team. Hospital IT will provide the approved infrastructure, access and security arrangements; it does not need to undertake BioMate application development.

## What we need from hospital IT

- **A project contact and technical liaison.** Designate contacts for infrastructure, information security and the participating research teams, with an agreed route for approvals and coordination.
- **An approved hosting environment.** Identify available servers or private-cloud resources, storage and backup arrangements. BioMate will recommend a configuration based on the selected workloads and expected users. GPU resources will be considered where required for local models, molecular modeling or training—not assumed necessary for every deployment.
- **Network and resource access.** Confirm how researchers will access the platform and how our engineers may perform installation and support. Public databases, literature searches and other online resources require hospital-approved internet access or hospital-provided internal access interfaces. BioMate will assist with integration and access testing under the hospital’s security policies.
- **A model-service preference.** Confirm whether to use an existing hospital AI service, deploy models locally, or use an approved external service. BioMate will assess compatibility and the resources needed for the agreed option.
- **Approved pilot data and users.** Identify the initial research teams, representative tasks and datasets approved for testing. Installation can begin with public or synthetic data; identifiable patient data is not required for initial setup.

Existing hospital infrastructure can be used where suitable.

## What BioMate will do

BioMate will assess the available environment, agree the deployment scope and provide the application package and required software assets. Our front engineering team will install and configure the platform, connect the agreed storage, computing and model services, and verify the selected research workflows.

We will then support a pilot with the nominated users, provide training, resolve deployment issues and deliver operating guidance. Connections to hospital research systems or data sources will be agreed separately, with approved access and a defined integration scope. The initial installation does not require replacing or modifying existing clinical systems.

## How deployment will proceed

1. **Agree the pilot.** Confirm the research use cases, users, hosting environment and data-security requirements.
2. **Prepare and install.** Hospital IT makes the approved resources available; BioMate’s front engineering team completes installation and configuration.
3. **Validate together.** Test user access, data upload, representative analyses, results and downloads. Hospital IT reviews operational requirements, while research users review the scientific usefulness of the selected outputs.
4. **Launch and hand over.** Train the initial users, confirm acceptance, and agree ongoing support, maintenance and expansion arrangements.

The deployment schedule will be agreed after the infrastructure and approval requirements are confirmed.

## Data security and ongoing support

The hospital controls access to its research data and the approved deployment environment. External AI services, online resources and remote support connections will be used only within the agreed security policy. For restricted or disconnected networks, we will confirm which resources are available through hospital interfaces and which models, databases and workflows need to be provisioned locally. Without approved internet access or suitable internal interfaces, live external retrieval will be unavailable; local analysis can use the resources already deployed.

Hospital IT will manage the underlying infrastructure and institutional security controls. BioMate will provide update packages, release notes and technical support, with the front engineering team coordinating implementation. Updates can be obtained through hospital-approved network access or supplied as offline packages. The team will agree update arrangements with the hospital, complete the necessary backups and verify platform operation afterward. If problems occur, recovery will follow the agreed backup and rollback procedure.

Remote maintenance will use hospital-approved access, such as the hospital’s VPN, a bastion host or screen sharing attended by hospital staff, and will proceed only with hospital authorization. Where remote access is unavailable, front engineers will provide on-site assistance with support from BioMate’s development team. Update and technical support arrangements will be confirmed at handover.

## Next step

Arrange a joint meeting between hospital IT, the participating research team and BioMate’s front engineering team to confirm available infrastructure, network restrictions, the preferred model service and the first pilot use cases. BioMate will then provide a deployment configuration and implementation schedule for agreement.
