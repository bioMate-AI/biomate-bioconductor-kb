# Galaxy Frontend - Comprehensive Feature Analysis

## Overview
Galaxy is a sophisticated bioinformatics workflow management platform with a rich, feature-heavy Vue.js frontend. The frontend implements a complex, modular architecture based on Pinia state management, featuring virtual scrolling, advanced form builders, workflow editors, and extensive data visualization capabilities.

---

## 1. HISTORY MANAGEMENT

### Location
`/home/yzhang/biomate/backend/client/src/components/History/`

### Key Features

#### 1.1 History Architecture
Galaxy implements a hierarchical history system with the following capabilities:

**Component Tree:**
- **Index.vue**: Root component that switches between `CurrentHistory` and `CurrentCollection` views
- **HistoryView.vue**: Public history viewing interface with import/export capabilities
- **HistoryPanel.vue**: Main history display with:
  - Virtual scroller for efficient rendering of thousands of items
  - Real-time filtering and search with advanced operators
  - Drag-and-drop support for history operations
  - Multi-selection and batch operations
  - Synchronized state with server via polling/websockets

#### 1.2 History Content Management
- **ContentItem.vue**: Efficiently renders individual history items (datasets/collections)
- **GenericItem.vue** / **GenericElement.vue**: Polymorphic rendering for different item types
- **ExpandedItems.js**: Tracks which items are expanded for detail viewing
- **SelectedItems.js**: Manages multi-select state for batch operations

#### 1.3 Dataset Operations
- **DatasetActions.vue**: Button group for dataset operations:
  - Download datasets
  - Visualize data
  - Rerun tools that generated dataset
  - Copy download links
  - Report errors
  - View detailed information
- **DatasetDetails.vue**: Expanded view with metadata, file info, and metrics
- **DatasetDownload.vue**: Format-aware download options

#### 1.4 Advanced Features
- **History Archiving**: Complete workflow to archive histories with export options
  - HistoryArchive.vue, HistoryArchiveWizard.vue
  - Selective content archiving
  - Export formats support
- **History Export/Import**:
  - HistoryExport.vue with wizard interface
  - CopyModal.vue for importing other users' histories
- **History Filtering System** (HistoryFilters.js):
  - Advanced query language with operators (eq, contains, gt, lt, etc.)
  - Server-side filtering for performance
  - Field-specific searches (name, created, size, etc.)

#### 1.5 Storage Management
- **SelectPreferredStore.vue**: User can select preferred object storage location
- **StorageLocationIndicator.vue**: Displays where data is stored
- **PreferredStorePopover.vue**: Interactive storage selection

#### 1.6 History Navigation
- **HistoryNavigation.vue**: Breadcrumbs and navigation controls
- **HistoryCounter.vue**: Displays item counts and status metrics
- **HistoryMessages.vue**: Informational/error messages from server

### State Management
- **historyStore.ts**: Pinia store managing:
  - Current history state and switching
  - History list with pagination (10 items per page)
  - Pinned histories (persisted to localStorage)
  - Filter text per history
  - History details caching with smart loading
- **historyItemsStore.ts**: Manages individual history items with:
  - Virtual scroller state
  - Watched history monitoring
  - Total matches count for filtered views
  - Lazy loading of item details

---

## 2. DATA VISUALIZATION

### Location
`/home/yzhang/biomate/backend/client/src/components/Visualizations/`

### Key Features

#### 2.1 Visualization System
- **VisualizationPanel.vue**: Main visualization discovery interface
  - Plugin-based architecture using fetchPlugins API
  - Real-time search across visualization names, descriptions, tags
  - Sortable by embeddability (embeddable plugins first)
  - Context-aware (can visualize specific dataset or create new)

#### 2.2 Visualization Types
- **DisplayApplications.vue**: Renders available visualization plugins
- **VisualizationWrapper.vue**: Container for visualization rendering
- **VisualizationFrame.vue**: IFrame-based visualization isolation
- **VisualizationCreate.vue**: Create new visualization from scratch
- **TabularChunkedView.vue**: Specialized for tabular data with chunked loading

#### 2.3 Advanced Visualization Features
- **VisualizationHeader.vue**: Navigation and controls
- **VisualizationExamples.vue**: Saved visualization examples
- **VisualizationPublished.vue**: Public/published visualization management

#### 2.4 API Integration
- Plugins fetched from `/api/plugins` endpoint
- Support for multiple plugin types with different embedding capabilities
- Dynamic plugin loading and registration

---

## 3. TOOL EXECUTION

### Location
`/home/yzhang/biomate/backend/client/src/components/Tool/`

### Key Features

#### 3.1 Tool Interface
- **ToolForm.vue**: Main tool execution interface with:
  - Loading states and error handling
  - Dynamic form generation from tool schema
  - Tool recommendations
  - Tool version switching
  - Email notification options
  - Job remapping (re-use previous job outputs)
  - Cached job attempts
  - Data manager mode selection

#### 3.2 Tool Metadata and Help
- **ToolCard.vue**: Tool information card with schema validation
- **ToolHelp.vue**: Unified help interface aggregating:
  - **ToolHelpMarkdown.vue**: Markdown-formatted help
  - **ToolHelpRst.vue**: reStructuredText help with syntax highlighting
  - **ToolHelpForum.vue**: Help forum links and community resources
- **ToolTutorialRecommendations.vue**: Recommended tutorials for tool

#### 3.3 Tool Source Information
- **ToolSource.vue**: Tool XML source viewer
- **ToolSourceDisplay.vue**: Syntax-highlighted display
- **ToolSourceMenuItem.vue**: Menu item for source access

#### 3.4 Tool Features and Options
- **ToolOptionsButton.vue**: Access to tool options menu
- **ToolFavoriteButton.vue**: Mark tools as favorites
- **ToolVersionsButton.vue**: Switch between tool versions
- **ToolReport.vue**: Generate execution reports
- **ToolLink.vue** / **ToolLinkPopover.vue**: Shareable tool links

#### 3.5 Object Store Selection
- **ToolSelectPreferredObjectStore.vue**: Choose output storage location
- **ToolTargetPreferredObjectStorePopover.vue**: Storage selection UI

#### 3.6 Execution Flow
- **ToolSuccessMessage.vue**: Success feedback with output dataset links
- **ToolSuccess.vue**: Complete success view with job details
- **ToolFooter.vue**: Action buttons and status display

#### 3.7 Tool Entry Points
- **ToolEntryPoints.vue**: Interactive tool job entry points
- Integration with interactive tools in workflows

### Tool Form Building
- **ToolForm.vue** + **FormDisplay.vue**: Dynamic form generation from schema
- Validates tool parameters before execution
- Shows inline errors for invalid inputs
- Supports conditional parameters based on other field values
- Scroll-to-error functionality for validation failures

---

## 4. FORM BUILDER

### Location
`/home/yzhang/biomate/backend/client/src/components/Form/`

### Key Features

#### 4.1 Core Form Components
Galaxy implements a sophisticated form system with:

- **FormDisplay.vue**: Root form component managing:
  - Input validation with server-side error handling
  - Repeat sections (1-to-N inputs)
  - Conditional sections (show/hide based on values)
  - Loading states
  - Scroll-to-validation functionality
  - Form message display

#### 4.2 Form Elements (40+ specialized input types)
- **FormInput.vue**: Text input with validation
- **FormText.vue**: Multiline text area
- **FormNumber.vue**: Numeric input with min/max/step
- **FormBoolean.vue**: Toggle/checkbox
- **FormCheck.vue**: Checkbox with label
- **FormRadio.vue**: Radio button group
- **FormSelect.vue**: Dropdown with single/multiple options
- **FormSelectMany.vue**: Multi-select with search (using worker for performance)
- **FormDrilldown.vue**: Hierarchical nested selection
- **FormColor.vue**: Color picker
- **FormUpload.vue**: File upload with progress
- **FormDirectory.vue**: Directory path selector
- **FormTags.vue**: Tag input
- **FormOptionalText.vue**: Optional string with enable/disable
- **FormHidden.vue**: Hidden fields
- **FormRulesEdit.vue**: Rule editor for complex logic
- **FormSelection.vue**: Generic selection widget

#### 4.3 Advanced Data Input
- **FormData.vue**: Dataset/collection selector with:
  - History dataset browsing
  - Collection element browsing
  - Datatype filtering
  - Extension filtering
  - URI-based input support
- **FormDataUri.vue**: URI input for remote datasets
- **FormDataExtensions.vue**: Extension information display
- **FormDataContextButtons.vue**: Context-aware actions
- **FormDataWorkflowRunTabs.vue**: Workflow invocation output selection

#### 4.4 Form Utilities
- **FormElement.vue**: Single form element wrapper with:
  - Label rendering
  - Help text (Markdown)
  - Error display
  - Validation indicators
- **FormElementLabel.vue**: Label with contextual help
- **FormElementHelpMarkdown.vue**: Markdown rendering for help text
- **FormElementHeader.vue**: Section headers
- **FormRepeat.vue**: Dynamic repeat sections
- **FormListElementOperations.vue**: Add/remove repeat elements
- **FormInputs.vue**: Wrapper for multiple inputs
- **FormGeneric.vue**: Generic element renderer
- **FormCard.vue** / **FormCardSticky.vue**: Layout containers
- **FormMessage.vue**: Message/notification display

#### 4.5 Form Validation
- Input-level validation with regex patterns
- Server-side validation for complex rules
- Datatype mismatch detection (FormInputMismatchBadge.vue)
- Required field indicators
- Conditional validation based on other fields

#### 4.6 Styling and Layout
- SCSS variables and mixins (_form-elements.scss)
- Responsive design
- Bootstrap integration
- Accessibility features (labels, ARIA)

---

## 5. COLLECTIONS (Dataset Collections)

### Location
`/home/yzhang/biomate/backend/client/src/components/Collections/`

### Key Features

#### 5.1 Collection Types Supported
- **List Collections**: Ordered lists of datasets
- **Paired Collections**: Paired datasets (e.g., forward/reverse reads)
- **Paired/Unpaired Lists**: Mixed collections for flexible data organization
- **List-of-Pairs**: Nested collections
- **Record Collections**: Named field collections
- **File Sets**: Structured file collections
- **Workbooks**: Sample sheet-based collections

#### 5.2 Collection Creation Wizards
- **ListWizard.vue**: Create list collections
- **PairCollectionCreator.vue**: Pair individual datasets
- **PairedOrUnpairedListCollectionCreator.vue**: Mixed pairing
- **ListCollectionCreator.vue**: List from dataset selection
- **BuildFileSetWizard.vue**: File set creation
- **SampleSheetWizard.vue**: Sample sheet-based collections
- **SampleSheetCollectionCreator.vue**: Sheet validation and creation
- **RuleBasedCollectionCreatorModal.js**: Rule-based collection generation

#### 5.3 Collection Management
- **CollectionCreator.vue**: Main collection creation interface
- **CollectionCreatorIndex.vue**: Wizard selection interface
- **CollectionEditView.vue**: Edit existing collections
- **FixedIdentifierDatasetCollectionElementView.vue**: View collection elements

#### 5.4 Pairing and Rules
- **PairingFilterInputGroup.vue**: Filter datasets for pairing
- **PairedElementView.vue**: Display paired datasets
- **UnpairedDatasetElementView.vue**: Display unpaired items
- **AutoPairing.vue**: Automatic pairing with regex patterns
- **usePairing.ts**: Composable for pairing logic
- **pairing.ts**: Pairing utilities and algorithms
- **RulesStandalone.vue**: Standalone rule builder
- **rule_target_column_specification.yml**: Rule schema

#### 5.5 Collection Wizards Components
- **SourceFromCollection.vue**: Create from existing collection
- **SourceFromDatasetAsTable.vue**: Use dataset as table source
- **SourceFromRemoteFiles.vue**: Remote file input
- **SourceFromPastedData.vue**: Paste data directly
- **SourceFromCollectionApplyRules.vue**: Apply transformation rules
- **SelectCollection.vue**: Collection selector
- **SelectDataset.vue**: Dataset selector
- **SelectFolder.vue**: Folder browser
- **PasteData.vue**: Text input area
- **CreatingWhat.vue**: Collection type selection

#### 5.6 Workbook Support
- **SampleSheetGrid.vue**: Spreadsheet-like interface
- **DownloadWorkbookButton.vue**: Export workbook
- **CardUploadWorkbook.vue**: Upload Excel/CSV
- **CardEditWorkbook.vue**: In-place editing
- **CardDownloadWorkbook.vue**: Download template
- **UploadSampleSheet.vue**: Sheet upload interface
- **UploadFetchWorkbook.vue**: Fetch from remote
- **ConfigureFetchWorkbook.vue**: Configure remote fetch
- **workbooks.ts**: Workbook utilities

#### 5.7 Data Organization
- **CollectionCreatorSourceOptions.vue**: Source selection
- **CollectionNameInput.vue**: Name input with validation
- **CollectionCreatorHelpHeader.vue**: Contextual help
- **CollectionCreatorNoItemsMessage.vue**: Empty state messaging
- **CollectionCreatorShowExtensions.vue**: File extension display
- **CollectionCreatorFooterButtons.vue**: Action buttons
- **ClickToEdit.vue**: Inline editing widget
- **CellStatusComponent.vue**: Cell state indicators
- **CellDiscardComponent.vue**: Discard cell values
- **DatabaseEditTab.vue**: Database integration
- **SuitableConvertersTab.vue**: Data type conversion options

### State Management
- **collectionElementsStore.ts**: Collection element caching
- **collectionBuilderItemsStore.ts**: Builder-specific state
- **collectionAttributesStore.ts**: Collection metadata

---

## 6. LIBRARIES (Data Libraries)

### Location
`/home/yzhang/biomate/backend/client/src/components/Libraries/`

### Key Features

#### 6.1 Data Libraries System
Galaxy Data Libraries provide centralized data management:
- Hierarchical folder structure (like file systems)
- Per-library and per-item permissions
- Sharing across users/groups
- Metadata management
- Dataset versioning support

#### 6.2 Library Interface
- **LibrariesList.vue**: List of available libraries
- **LibraryFolder.vue**: Folder browsing interface with:
  - Sortable table with multiple columns
  - Pagination support
  - Search functionality
  - Bulk selection with multi-action support
  - Create new folders inline

#### 6.3 Library Operations
- **FolderTopBar.vue**: Toolbar with:
  - Search/filter
  - Add dataset button
  - Refresh controls
  - Import to history
  - Download options
  - Delete operations
- **DirectoryDatasetPicker.vue**: File browser for adding datasets
- **TopToolbar/delete-selected.js**: Bulk delete logic
- **TopToolbar/download.js**: Bulk download
- **TopToolbar/import-to-history/import-dataset.js**: Import datasets to history
- **TopToolbar/import-to-history/import-collection.js**: Import collections
- **TopToolbar/ui-select.js**: Selection UI

#### 6.4 Library Dataset Management
- **LibraryDataset.vue**: Individual dataset entry
  - Edit name and description
  - Manage permissions
  - Download options
  - Deletion (soft delete support)
- **LibraryEditField.vue**: Inline field editing
- **LibraryBreadcrumb.vue**: Navigation breadcrumbs

#### 6.5 Library Permissions
- **LibraryPermissions.vue**: Manage library-wide permissions
- **LibraryFolderPermissions.vue**: Folder-level permissions
- **LibraryFolderDatasetPermissions.vue**: Item-level permissions
- **PermissionsInputField.vue**: Permission input widget
- **PermissionsHeader.vue**: Permission column headers
- **LibraryPermissionsWarning.vue**: Permission warnings

#### 6.6 Library Metadata
- **FolderDetails.vue**: Display folder information
- **LibraryFolder/services.js**: API interactions
- **table-fields.js**: Table column definitions
- **icons.js**: Icon mappings

### State Management
- **LibraryFolder/services.js**: Library API calls
- **Libraries/services.js**: Library management API
- **library-utils.js**: Utility functions
- **library-folder-table.css**: Styling

---

## 7. ADMIN FEATURES

### Location
`/home/yzhang/biomate/backend/client/src/components/admin/`

### Key Features

#### 7.1 Admin Panel Structure
- **AdminPanel.vue**: Main admin navigation
- **AdminHome.vue**: Admin dashboard
- **AdminServices.js**: Admin API wrapper

#### 7.2 Data Management
- **DataManager.vue**: Data cleanup and management
  - **DataManagerView.vue**: Main view
  - **DataManagerTable.vue**: Table of managed items
  - **DataManagerJobs.vue**: Job listing
  - **DataManagerJob.vue**: Individual job details

#### 7.3 Data Types and Converters
- **DataTypes.vue**: Datatype registry management
- **DataTables.vue**: Data table mapping
- **DataTablesGrid.vue**: Grid-based data table editing
- **DataManagerGrid.vue**: Data manager grid view
- **DisplayApplications.vue**: Application configuration

#### 7.4 Dependency Resolution
- **Dependencies/** folder:
  - **DependencyResolver.vue**: Tool dependency resolution
  - **ContainerResolver.vue**: Container/conda environment management
  - **DependencyIndexWrapper.vue**: Index wrapper
  - **ResolutionIndex.vue**: Resolution tracking
  - **ResolutionDetails.vue**: Detailed resolution info
  - **Requirements.vue**: Requirement listing
  - **Statuses.vue**: Status tracking
  - **ToolDisplay.vue**: Tool information

#### 7.5 Job Management
- **JobsList.vue**: List of jobs for monitoring
- **JobsTable.vue**: Job details in table format
- **JobLock.vue**: Job locking/unlock controls
- **JobFields.js**: Job column definitions

#### 7.6 Form and Configuration
- **RoleForm.vue**: Role creation/editing
- **ResetMetadata.vue**: Metadata reset tool
- **SanitizeAllow.vue**: HTML sanitization settings
- **ErrorStack.vue**: Error message display

#### 7.7 Notifications
- **Notifications/** folder:
  - **NotificationsManagement.vue**: Main notifications UI
  - **NotificationForm.vue**: Create/edit notifications
  - **BroadcastsList.vue**: List of broadcasts
  - **BroadcastForm.vue**: Create/edit broadcasts
  - **BroadcastCard.vue**: Broadcast display
  - Support for admin-wide notifications

#### 7.8 Grid and List Views
- **BaseList.vue**: Base list component
- **BaseGrid.vue**: Base grid component
- Reusable patterns for admin interfaces

---

## 8. STATE MANAGEMENT (Pinia Stores)

### Location
`/home/yzhang/biomate/backend/client/src/stores/`

### Key Stores

#### 8.1 Core Stores
- **historyStore.ts**: History state (currently selected, list, filters)
- **historyItemsStore.ts**: History contents (items, virtual scroll state)
- **userStore.ts**: User authentication and profile
- **userFlagsStore.ts**: User feature flags/preferences
- **configurationStore.ts**: Server configuration

#### 8.2 Tool and Workflow Stores
- **toolStore.ts**: Available tools, panels, and searching
- **unprivilegedToolStore.ts**: Unprivileged tool access
- **workflowStore.ts**: Workflow definitions and metadata
- **workflowEditorStateStore.ts**: Workflow editor UI state
- **workflowStepStore.ts**: Individual workflow step details
- **workflowNodeInspectorStore.ts**: Node inspection sidebar
- **workflowSearchStore.ts**: Workflow search functionality
- **workflowConnectionStore.ts**: Workflow connection state
- **workflowEditorToolbarStore.ts**: Editor toolbar buttons
- **workflowEditorCommentStore.ts**: Workflow comments/annotations
- **workflowLandingStore.ts**: Workflow page state

#### 8.3 Data and Job Stores
- **datasetStore.ts**: Individual dataset caching
- **datasetTextContentStore.ts**: Dataset text preview cache
- **datasetExtraFilesStore.ts**: Extra files for datasets
- **jobStore.ts**: Job details caching
- **invocationStore.ts**: Workflow invocation state
- **jobMetricsStore.ts**: Job performance metrics
- **jobDestinationParametersStore.ts**: Job destination info

#### 8.4 Collection and File Stores
- **collectionElementsStore.ts**: Collection element caching
- **collectionBuilderItemsStore.ts**: Builder UI state
- **collectionAttributesStore.ts**: Collection metadata
- **fileSourcesStore.ts**: File source configuration
- **fileSourceTemplatesStore.ts**: File source templates
- **fileSourceInstancesStore.ts**: File source instances

#### 8.5 Object Store and Datatype Stores
- **objectStoreStore.ts**: Object storage management
- **objectStoreTemplatesStore.ts**: Object store templates
- **objectStoreInstancesStore.ts**: Configured object stores
- **datatypeStore.js**: Datatype registry
- **datatypesMapperStore.ts**: Datatype conversions
- **datatypeVisualizationsStore.ts**: Visualization availability per datatype

#### 8.6 UI and Activity Stores
- **activityStore.ts**: Activity bar state (which panels open, visibility)
- **activityStoreTypes.ts**: Type definitions
- **notificationsStore.ts**: User notifications/toasts
- **broadcastsStore.ts**: Server broadcasts
- **entryPointStore.ts**: Entry point management
- **interactiveToolsStore.ts**: Interactive tool state

#### 8.7 Advanced Features
- **undoRedoStore/**: Comprehensive undo/redo system
  - **undoRedoAction.ts**: Action base class
  - Supports lazy actions for debouncing
  - Bi-directional state management
  - Scoped instances for multiple contexts
- **userTagsStore.ts**: Tag management
- **helpTermsStore.ts**: Help text caching

#### 8.8 Utility Stores
- **scopedStore.ts**: Create scoped store instances
- **scopePointerStore.ts**: Scope pointer management
- **refreshFromStore.ts**: Store refresh utilities
- **dbKeyStore.js**: Database key management
- **testUtils.ts**: Testing utilities
- **utilities/history.utilities.js**: History utilities
- **services/history.services.ts**: History API services

### Store Patterns Used
1. **Pinia defineStore**: Standard store definition
2. **Computed getters**: Derived state
3. **Direct mutations**: ref() and set() from Vue
4. **Services pattern**: Async API calls separated
5. **Caching patterns**: useKeyedCache composable for smart caching
6. **Scoped stores**: Create isolated store instances
7. **User local storage**: Persist user preferences

---

## 9. WORKFLOW EDITOR

### Location
`/home/yzhang/biomate/backend/client/src/components/Workflow/Editor/`

### Key Features

#### 9.1 Core Workflow Editor
- **Index.vue**: Main editor component with:
  - Toolbar with file operations (save, revert, export, import)
  - Multiple modal dialogs (save-as, state upgrade, messages)
  - Activity bar integration
  - Side panels for tools, attributes, workflow inspector
  - Main editor canvas with workflow graph

#### 9.2 Visual Editing
- **WorkflowGraph.vue**: Renders the workflow DAG (directed acyclic graph)
- **Node.vue**: Individual workflow step nodes with:
  - Tool/workflow information
  - Input/output terminals
  - Status indicators
  - Label editing
- **NodeInput.vue**: Input node visualization
- **NodeOutput.vue**: Output node visualization
- **NodeInvocationText.vue**: Invocation-specific text
- **WorkflowEdges.vue**: Connection lines between nodes
- **SVGConnection.vue**: Individual connection rendering
- **ConnectionMenu.vue**: Connection modification menu

#### 9.3 Canvas Interaction
- **Draggable.vue**: Base draggable component
- **DraggablePan.vue**: Canvas panning
- **AdaptiveGrid.vue**: Grid lines with adaptive granularity
- **AreaHighlight.vue**: Selection area visualization
- **WorkflowMinimap.vue**: Mini overview of workflow
- **ZoomControl.vue**: Zoom in/out/fit controls

#### 9.4 Node Inspector/Properties
- **NodeInspector.vue**: Right-side panel showing selected node details
- **WorkflowAttributes.vue**: Edit workflow-level properties:
  - Name, annotation, version
  - Tags, license, creator
  - DOI, logo, readme, help text
  - Input parameters

#### 9.5 Step Configuration
- **Forms/** folder: Step parameter configuration
  - **FormTool.vue**: Tool step configuration
  - **FormOutput.vue**: Output parameter definition
  - **FormInputCollection.vue**: Collection input definition
  - **FormColumnDefinitions.vue**: Table column specifications
  - **FormRecordFieldDefinitions.vue**: Record structure definition
  - **FormDatatype.vue**: Datatype specification
  - **FormCollectionType.vue**: Collection type specification
  - **FormConditional.vue**: Conditional step configuration
  - **FormDefault.vue**: Default value specification
  - **FormFieldType.vue**: Custom field type definition

#### 9.6 Comments and Annotations
- **Comments/** folder: Workflow annotation system
  - **WorkflowComment.vue**: Base comment component
  - **TextComment.vue**: Text annotations
  - **MarkdownComment.vue**: Markdown-formatted comments
  - **FreehandComment.vue**: Freehand drawing
  - **FrameComment.vue**: Rectangular frame grouping
  - **ColorSelector.vue**: Comment color picker
  - **useResizable.ts**: Resizable comment support
  - **colors.ts**: Color palette definitions

#### 9.7 Workflow Actions
- **Actions/** folder: Operation implementations
  - **workflowActions.ts**: Workflow-level actions (add step, delete, etc.)
  - **stepActions.ts**: Step modifications
  - **commentActions.ts**: Comment CRUD operations
  - **cloneStep.ts**: Step duplication
  - **actions.test.ts**: Comprehensive action tests

#### 9.8 Linting and Validation
- **Lint.vue**: Lint issues display
- **LintSection.vue**: Lint detail section
- **WorkflowAttributes.vue**: Link to linting best practices
- Checks for:
  - Untyped parameters
  - Missing documentation
  - Missing license
  - Missing creator info
  - Orphaned steps
  - Tool version updates

#### 9.9 Additional Features
- **SaveChangesModal.vue**: Unsaved changes warning
- **StateUpgradeModal.vue**: Tool upgrade compatibility checking
- **RefactorConfirmationModal.vue**: Refactoring confirmation
- **MessagesModal.vue**: Error/info messages
- **ReadmeEditor.vue**: Workflow documentation editor
- **ReportHelp.vue**: Report generation help
- **Recommendations.vue**: Tool/workflow recommendations

#### 9.10 Utilities and Helpers
- **modules/** folder: Shared utilities
  - **labels.ts**: Label management
  - **itemIcons.ts**: Icon mapping
  - **inputs.ts**: Input handling
  - **geometry.ts**: Position/size calculations
  - **collectionTypeDescription.ts**: Collection type info
  - **canvasDraw.ts**: Canvas drawing utilities
  - **activities.ts**: Activity definitions

#### 9.11 Composables for UI Logic
- **composables/** folder: Reusable composition functions
  - **workflowBoundingBox.ts**: Workflow bounds calculation
  - **viewportBoundingBox.ts**: Viewport bounds
  - **useUniqueLabelError.ts**: Label uniqueness validation
  - **useToolState.ts**: Tool state management
  - **useTerminal.ts**: Connection terminal logic
  - **useStepProps.ts**: Step property handling
  - **useNodePosition.ts**: Node positioning
  - **useDraggable.js**: Drag functionality
  - **useDefaultStepPosition.ts**: Initial step placement
  - **relativePosition.ts**: Position calculations
  - **multiSelect.ts**: Multi-selection support
  - **d3Zoom.ts**: D3.js zoom integration

#### 9.12 Toolbar
- **Tools/** folder: Editor tools
  - **ToolBar.vue**: Main toolbar
  - **InputCatcher.vue**: Input element handling
  - **BoxSelectPreview.vue**: Box selection visualization
  - **useToolLogic.ts**: Tool operation logic
  - **useSelectionOperations.ts**: Selection handling

---

## 10. ADDITIONAL POWERFUL FEATURES

### 10.1 Activity Bar System
**Location**: `/home/yzhang/biomate/backend/client/src/components/ActivityBar/`

The Activity Bar is Galaxy's plugin-like sidebar system:
- **ActivityBar.vue**: Main bar with icons
- **ActivityItem.vue**: Individual activity icon
- **ActivitySettings.vue**: Activity customization
- **Items/** folder:
  - **UploadItem.vue**: Upload progress indicator
  - **NotificationItem.vue**: Notification badge
  - **InteractiveItem.vue**: Interactive tool status
- **activityStore.ts**: State management with localStorage persistence
- Extensible activity definition system (Activity interface)

### 10.2 Upload System
**Location**: `/home/yzhang/biomate/backend/client/src/components/Upload/`

Advanced file upload capabilities:
- **uploadStore.ts**: Upload queue and progress tracking
- **useUploadConfigurations.ts**: File type configuration
- Drag-and-drop support
- Multiple file handling
- Progress indicators per file
- Server polling for upload status
- File type/extension validation

### 10.3 Advanced Search
**Location**: `/home/yzhang/biomate/backend/client/src/components/Panels/`

- **SearchPanel.vue**: Cross-system search
- **ToolSearch.vue**: Tool searching with:
  - Web worker for fast local searching
  - Whoosh-like query syntax (e.g., #favorites, name:foo)
  - EDAM ontology support
  - Tool metadata searching
- **toolSearch.worker.js**: Web worker for parallel search

### 10.4 Undo/Redo System
**Location**: `/home/yzhang/biomate/backend/client/src/stores/undoRedoStore/`

A comprehensive undo/redo implementation:
- **UndoRedoAction class**: Base class with:
  - run/onRun: Execute action
  - undo/onUndo: Reverse action
  - redo/onRedo: Re-apply action
  - destroy/onDestroy: Cleanup
  - name property: Display name
- **LazyUndoRedoAction**: For debounced actions (e.g., dragging)
- **useUndoRedoStore**: Scoped store for isolated undo stacks
- Stack-based history with size limits
- Bi-directional state management
- Comprehensive testing patterns

### 10.5 Panels System
**Location**: `/home/yzhang/biomate/backend/client/src/components/Panels/`

Flexible side panel system:
- **FlexPanel.vue**: Flexible layout
- **ActivityPanel.vue**: Activity-based panel
- **MultiviewPanel.vue**: Multiple view support
- **InvocationsPanel.vue**: Workflow execution history
- **InteractiveToolsPanel.vue**: Running interactive tools
- **SettingsPanel.vue**: Configuration options
- **NotificationsPanel.vue**: Notification center

### 10.6 User Preferences and Storage
- **useUserLocalStorage.ts**: Composable for user-scoped localStorage
- **userStore.ts**: User info and flags
- **userFlagsStore.ts**: Feature flags per user
- Persisted preferences (Activity bar state, panel widths, etc.)

### 10.7 Dialog and Modal System
- **FilesDialog.vue**: File/folder browser
- **DataDialog.vue**: Dataset/collection selector
- **FilesDialog.vue**: File selection
- Integration with Bootstrap Vue modals

### 10.8 Type Safety
- **parameterTypes.d.ts**: TypeScript definitions for tool parameters
- **FormDisplay.test.js**: Comprehensive form testing
- Type-safe form element rendering

---

## 11. KEY ARCHITECTURAL PATTERNS

### 11.1 State Management Pattern
```
Component (Vue 3 Composition API)
  ↓
Store (Pinia defineStore)
  ↓
Services (API calls)
  ↓
API (GalaxyApi wrapper)
```

### 11.2 Virtual Scrolling Pattern
- Used in History, Collections, and large lists
- Efficient rendering of 1000+ items
- Virtual scroller plugin integration
- Throttled scroll event handling

### 11.3 Plugin/Extension Pattern
- Activity Bar activities
- Visualization plugins
- Tool panels
- Dynamic feature loading

### 11.4 Modal/Dialog Pattern
- Bootstrap Vue modal integration
- Confirmation dialogs
- Form wizards
- Modal chains with data passing

### 11.5 Composable Pattern
- ReusableVue 3 Composition API functions
- useHistoryDragDrop
- useUploadConfigurations
- useToolState
- Custom hooks for business logic

### 11.6 Form Pattern
- Dynamic form generation from JSON schema
- Recursive form element composition
- Error collection and display
- Validation at multiple levels

---

## 12. KEY TECHNOLOGIES

### Frontend Framework
- **Vue 3**: Composition API and script-setup
- **TypeScript**: Optional but used extensively
- **Pinia**: State management (modern Vuex)
- **Vue Router**: Navigation

### UI Framework
- **Bootstrap Vue**: Component library
- **Font Awesome**: Icon library
- **Bootstrap CSS**: Styling foundation

### Advanced Libraries
- **Axios**: HTTP client
- **D3.js**: Workflow graph visualization
- **Web Workers**: Parallel search and form processing
- **VueUse**: Composable utilities
- **Virtual Scroll**: List virtualization

### Developer Tools
- **Jest**: Unit testing
- **Vitest**: Faster testing
- **TypeScript**: Type checking
- **ESLint**: Code linting
- **Webpack/Vite**: Module bundling

---

## 13. POWERFUL FEATURES FOR BIOMATE ADAPTATION

### Most Valuable Galaxy Features
1. **Virtual scrolling for large datasets** - Handle massive histories
2. **Plugin architecture** - Extensible visualization system
3. **Workflow editor with visual DAG** - Drag-drop workflow creation
4. **Advanced form builder** - Dynamic parameter forms from schema
5. **Undo/redo system** - Professional UX
6. **Collection management** - Organize complex data structures
7. **Activity bar panels** - Flexible sidebar management
8. **Multi-select batch operations** - Handle many items efficiently
9. **Real-time filtering** - Advanced query language support
10. **Job and invocation tracking** - Monitor long-running operations

### UI Patterns Worth Adapting
1. **Tabbed interfaces** - For different views/sections
2. **Breadcrumb navigation** - For hierarchical data
3. **Dropdown menus with icons** - For bulk operations
4. **Progress indicators** - For async operations
5. **Modal wizards** - For complex workflows
6. **Inline editing** - Click-to-edit patterns
7. **Toast notifications** - Non-blocking feedback
8. **Loading spinners** - Clear async states
9. **Validation error display** - Form feedback
10. **Responsive grid layouts** - Adaptive design

---

## 14. DEVELOPMENT QUALITY METRICS

### Testing Coverage
- Comprehensive test files (.test.js, .test.ts)
- Unit tests for utilities
- Component snapshot tests
- Store tests with mock data
- Service tests with API mocking

### Code Organization
- Clear separation of concerns
- Services for API logic
- Stores for state management
- Components for UI
- Utils for helpers
- Composables for reusable logic

### Documentation
- README files in key modules
- Type definitions (TypeScript)
- JSDoc comments
- Test files as documentation
- API schema files (JSON/YAML)

---

## CONCLUSION

Galaxy's frontend is a mature, enterprise-grade bioinformatics platform UI. It demonstrates:

1. **Scalability** - Handles thousands of items with virtual scrolling
2. **Usability** - Multiple ways to accomplish tasks (drag-drop, forms, CLI)
3. **Extensibility** - Plugin system for visualizations and tools
4. **Maintainability** - Clear patterns, good separation of concerns
5. **Accessibility** - ARIA labels, keyboard navigation support
6. **Performance** - Web workers, lazy loading, smart caching
7. **User Experience** - Real-time feedback, undo/redo, informative errors

For BioMate, the most valuable takeaways are the workflow editor UI, the form builder system, the virtual scrolling patterns, and the overall state management architecture.
