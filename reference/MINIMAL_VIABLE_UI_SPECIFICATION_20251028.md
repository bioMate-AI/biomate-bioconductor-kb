# BioMate Minimal Viable UI Specification (2-Week Launch)

**Document Created:** 2025-10-28
**Priority:** P0 - Critical for Launch
**Status:** UI/UX Specification
**Estimated Implementation:** 4-6 days

---

## Executive Summary

This document defines the **Minimal Viable UI** for BioMate's 2-week launch. The goal is to deliver a functional, simple interface that enables pilot customers to use the platform immediately, while deferring the ambitious **Chatboard UX** transformation to Month 2-3 (P1).

**Key Principles:**
- **Simplicity:** Single-page interface, minimal navigation
- **Focus:** Chat-driven workflow generation (core value proposition)
- **Functionality:** File upload, workflow visualization, execution monitoring
- **Defer Complexity:** No Chatboard, no real-time collaboration, no knowledge panel

**Target:** 5-10 pilot customers can successfully generate and run workflows within 2 weeks.

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [User Flow](#user-flow)
3. [Component Specifications](#component-specifications)
4. [Visual Design](#visual-design)
5. [Error Handling](#error-handling)
6. [Performance Requirements](#performance-requirements)
7. [Implementation Plan](#implementation-plan)
8. [What We're NOT Building](#what-were-not-building)

---

## Design Philosophy

### Core Principles

1. **Chat-First:** All interactions start with natural language chat
2. **Progressive Disclosure:** Show complexity only when needed
3. **Immediate Feedback:** Every action has visible response within 1 second
4. **Graceful Degradation:** Errors are helpful, not cryptic
5. **Mobile-Aware:** Functional on tablets (desktop-first for launch)

### What Makes This "Minimal"

**We're Keeping:**
- ✅ Basic chat interface (text input, message history)
- ✅ File upload widget
- ✅ Workflow visualization (simplified, read-only)
- ✅ Execution monitoring (status, progress bars)
- ✅ Basic error messages

**We're Deferring (to Chatboard P1):**
- ❌ Multi-panel workspace (Chat + Canvas + Knowledge + Context)
- ❌ Interactive workflow canvas (drag-drop editing)
- ❌ Knowledge panel (literature, AI suggestions)
- ❌ Context panel (decision logs, version history)
- ❌ Real-time collaboration

---

## User Flow

### Primary User Journey

```
┌─────────────────────────────────────────────────────────────────┐
│                       BioMate MVP User Flow                      │
└─────────────────────────────────────────────────────────────────┘

1. LANDING
   User arrives at homepage
   ↓
   Sees hero section: "AI-Powered Bioinformatics Workflows"
   ↓
   Clicks "Start Analyzing" → Redirects to Chat Interface

2. AUTHENTICATION (if not logged in)
   Login/Signup modal appears
   ↓
   User enters email + password (or SSO)
   ↓
   Redirected to Chat Interface

3. CHAT INTERFACE
   ┌─────────────────────────────────────────────┐
   │  BioMate AI Assistant                        │
   ├─────────────────────────────────────────────┤
   │  Hello! I can help you create bioinfor-     │
   │  matics workflows. What would you like to   │
   │  analyze today?                              │
   │                                              │
   │  ┌────────────────────────────────────────┐ │
   │  │ Type your question or describe your    │ │
   │  │ analysis needs...                      │ │
   │  └────────────────────────────────────────┘ │
   │                                              │
   │  📎 Upload Files                             │
   └─────────────────────────────────────────────┘

4. USER INTERACTION
   User types: "I want to analyze RNA-seq data from paired-end FASTQ files"
   ↓
   AI responds with workflow suggestions
   ↓
   User uploads FASTQ files via 📎 button
   ↓
   Upload progress bar appears

5. WORKFLOW GENERATION
   AI generates workflow
   ↓
   Workflow visualization appears (simplified graph)
   ↓
   User reviews steps:
   - Step 1: Quality Control (FastQC)
   - Step 2: Alignment (STAR)
   - Step 3: Quantification (featureCounts)
   - Step 4: Differential Expression (DESeq2)

6. EXECUTION
   User clicks "Run Workflow" button
   ↓
   Execution timeline appears
   ↓
   Progress updates in real-time:
   - Step 1: Running... (progress bar)
   - Step 2: Queued
   - Step 3: Pending
   - Step 4: Pending

7. COMPLETION
   All steps complete (green checkmarks)
   ↓
   User clicks "View Results" button
   ↓
   Results panel appears with download links

8. ITERATION (Optional)
   User asks: "Can you add GO enrichment analysis?"
   ↓
   AI adds new step to workflow
   ↓
   User runs updated workflow
```

---

## Component Specifications

### 1. Header Bar

**Location:** Top of page, fixed position

**Content:**
- BioMate logo (left)
- Project dropdown (center) - switches between projects
- User menu (right) - settings, logout

**Implementation:**

```tsx
<header className="sticky top-0 z-50 border-b bg-background">
  <div className="flex h-16 items-center px-4">
    {/* Logo */}
    <div className="flex items-center space-x-2">
      <Logo size={32} />
      <span className="font-bold text-xl">BioMate</span>
    </div>

    {/* Project Selector */}
    <div className="flex-1 px-4">
      <Select value={currentProjectId} onValueChange={switchProject}>
        <SelectTrigger className="w-[300px]">
          <SelectValue placeholder="Select project" />
        </SelectTrigger>
        <SelectContent>
          {projects.map(p => (
            <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Button variant="ghost" size="sm" onClick={createProject}>
        + New Project
      </Button>
    </div>

    {/* User Menu */}
    <div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon">
            <UserIcon />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={openSettings}>
            Settings
          </DropdownMenuItem>
          <DropdownMenuItem onClick={logout}>
            Logout
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  </div>
</header>
```

**Styling:**
- Height: 64px
- Background: White (light mode), Dark gray (dark mode)
- Border bottom: 1px solid border color

---

### 2. Main Chat Interface

**Location:** Left side or full-width (responsive)

**Content:**
- Message history (scrollable)
- Chat input (bottom, fixed)
- File upload button (in chat input)

**Message Types:**

```tsx
// User Message
<div className="flex justify-end mb-4">
  <div className="bg-primary text-primary-foreground rounded-lg px-4 py-2 max-w-[70%]">
    I want to analyze RNA-seq data from paired-end FASTQ files
  </div>
</div>

// AI Message
<div className="flex justify-start mb-4">
  <div className="bg-muted rounded-lg px-4 py-2 max-w-[70%]">
    <Avatar className="inline-block mr-2">🤖</Avatar>
    Great! I'll help you create an RNA-seq analysis workflow.
    Let me suggest the following steps:
    1. Quality Control (FastQC)
    2. Alignment (STAR)
    3. Quantification (featureCounts)
    4. Differential Expression (DESeq2)

    Please upload your FASTQ files to get started.

    <Button variant="outline" size="sm" className="mt-2">
      Upload Files
    </Button>
  </div>
</div>

// System Message (e.g., workflow generated)
<div className="flex justify-center mb-4">
  <div className="bg-accent rounded-lg px-4 py-2 text-sm">
    ✨ Workflow generated successfully
  </div>
</div>
```

**Chat Input:**

```tsx
<div className="sticky bottom-0 border-t bg-background p-4">
  <form onSubmit={handleSubmit} className="flex space-x-2">
    {/* File Upload Button */}
    <Button
      type="button"
      variant="outline"
      size="icon"
      onClick={triggerFileUpload}
    >
      📎
    </Button>

    {/* Text Input */}
    <Textarea
      value={input}
      onChange={(e) => setInput(e.target.value)}
      placeholder="Type your question or describe your analysis needs..."
      className="flex-1 min-h-[60px] max-h-[200px]"
      onKeyDown={handleKeyDown}  // Cmd/Ctrl+Enter to submit
    />

    {/* Send Button */}
    <Button type="submit" disabled={!input.trim()}>
      Send
    </Button>
  </form>

  {/* File upload indicator (if files are being uploaded) */}
  {uploading && (
    <div className="mt-2 text-sm text-muted-foreground">
      Uploading {uploadCount} file(s)... {uploadProgress}%
    </div>
  )}
</div>
```

**Features:**
- Auto-resize textarea (min 60px, max 200px)
- Cmd/Ctrl+Enter to send message
- Disable send button if input empty
- Show typing indicator when AI is responding
- Scroll to bottom on new message

---

### 3. File Upload Widget

**Trigger:** Click 📎 button in chat input

**UI:** Modal dialog with drag-and-drop area

**Implementation:**

```tsx
<Dialog open={uploadDialogOpen} onOpenChange={setUploadDialogOpen}>
  <DialogContent className="max-w-2xl">
    <DialogHeader>
      <DialogTitle>Upload Files</DialogTitle>
      <DialogDescription>
        Upload FASTQ, BAM, VCF, or other bioinformatics files.
        Maximum file size: 100GB per file.
      </DialogDescription>
    </DialogHeader>

    {/* Drag-and-Drop Area */}
    <div
      className={cn(
        "border-2 border-dashed rounded-lg p-12 text-center",
        isDragging && "border-primary bg-primary/10"
      )}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <UploadIcon className="mx-auto h-12 w-12 text-muted-foreground" />
      <p className="mt-2 text-sm">
        Drag and drop files here, or{" "}
        <Button variant="link" onClick={triggerFilePicker}>
          browse
        </Button>
      </p>
      <p className="text-xs text-muted-foreground mt-1">
        Supported formats: FASTQ, BAM, VCF, BED, GTF, etc.
      </p>
    </div>

    {/* File List (if files selected) */}
    {files.length > 0 && (
      <div className="mt-4 space-y-2">
        {files.map((file, i) => (
          <div key={i} className="flex items-center justify-between p-2 bg-muted rounded">
            <div className="flex items-center space-x-2">
              <FileIcon />
              <div>
                <p className="text-sm font-medium">{file.name}</p>
                <p className="text-xs text-muted-foreground">
                  {formatFileSize(file.size)}
                </p>
              </div>
            </div>

            {/* Progress Bar */}
            {file.status === "uploading" && (
              <Progress value={file.progress} className="w-24" />
            )}

            {/* Status Icons */}
            {file.status === "completed" && <CheckIcon className="text-green-500" />}
            {file.status === "failed" && <XIcon className="text-red-500" />}

            {/* Remove Button */}
            <Button
              variant="ghost"
              size="icon"
              onClick={() => removeFile(i)}
              disabled={file.status === "uploading"}
            >
              <TrashIcon />
            </Button>
          </div>
        ))}
      </div>
    )}

    <DialogFooter>
      <Button variant="outline" onClick={() => setUploadDialogOpen(false)}>
        Cancel
      </Button>
      <Button onClick={startUpload} disabled={files.length === 0}>
        Upload {files.length} file(s)
      </Button>
    </DialogFooter>
  </DialogContent>
</Dialog>
```

**Features:**
- Drag-and-drop support
- Multi-file selection
- Real-time progress bars (per file)
- Chunked upload with resume capability (backend)
- File validation (format, size)
- Error messages for failed uploads

---

### 4. Workflow Visualization (Simplified)

**Display:** Appears in chat as AI-generated artifact

**UI:** Linear step-by-step list (NOT graph for MVP)

**Implementation:**

```tsx
<Card className="mt-4">
  <CardHeader>
    <CardTitle>Generated Workflow</CardTitle>
    <CardDescription>
      {workflowSteps.length} steps • Estimated time: {estimatedTime}
    </CardDescription>
  </CardHeader>

  <CardContent>
    <div className="space-y-3">
      {workflowSteps.map((step, i) => (
        <div key={i} className="flex items-start space-x-3 p-3 border rounded">
          {/* Step Number */}
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-bold">
            {i + 1}
          </div>

          {/* Step Details */}
          <div className="flex-1">
            <h4 className="font-medium">{step.name}</h4>
            <p className="text-sm text-muted-foreground">{step.tool}</p>

            {/* Parameters (collapsible) */}
            <Collapsible>
              <CollapsibleTrigger className="text-xs text-muted-foreground mt-1">
                View parameters →
              </CollapsibleTrigger>
              <CollapsibleContent className="mt-2 text-xs">
                <pre className="bg-muted p-2 rounded overflow-x-auto">
                  {JSON.stringify(step.parameters, null, 2)}
                </pre>
              </CollapsibleContent>
            </Collapsible>
          </div>

          {/* Edit Button (P1 - disabled for MVP) */}
          <Button variant="ghost" size="sm" disabled>
            Edit
          </Button>
        </div>
      ))}
    </div>
  </CardContent>

  <CardFooter className="flex justify-between">
    <Button variant="outline" onClick={exportWorkflow}>
      Export
    </Button>
    <Button onClick={executeWorkflow}>
      Run Workflow
    </Button>
  </CardFooter>
</Card>
```

**Features:**
- Linear list view (no complex graph)
- Step numbering (1, 2, 3...)
- Collapsible parameters (advanced users only)
- Export button (download JSON)
- Run button (starts execution)

**Defer to Chatboard (P1):**
- ❌ Interactive graph editor
- ❌ Drag-and-drop rearranging
- ❌ Real-time parameter editing

---

### 5. Execution Timeline

**Display:** Appears after "Run Workflow" is clicked

**UI:** Vertical timeline with status indicators

**Implementation:**

```tsx
<Card className="mt-4">
  <CardHeader>
    <CardTitle>Workflow Execution</CardTitle>
    <CardDescription>
      {completedSteps}/{totalSteps} steps completed
    </CardDescription>
  </CardHeader>

  <CardContent>
    <div className="space-y-4">
      {executionSteps.map((step, i) => (
        <div key={i} className="flex items-start space-x-4">
          {/* Status Icon */}
          <div className="flex-shrink-0">
            {step.status === "completed" && (
              <CheckCircleIcon className="w-6 h-6 text-green-500" />
            )}
            {step.status === "running" && (
              <LoaderIcon className="w-6 h-6 text-blue-500 animate-spin" />
            )}
            {step.status === "failed" && (
              <XCircleIcon className="w-6 h-6 text-red-500" />
            )}
            {step.status === "pending" && (
              <CircleIcon className="w-6 h-6 text-muted-foreground" />
            )}
          </div>

          {/* Step Info */}
          <div className="flex-1">
            <div className="flex items-center justify-between">
              <h4 className="font-medium">{step.name}</h4>
              <span className="text-xs text-muted-foreground">
                {step.duration || "Pending"}
              </span>
            </div>

            {/* Progress Bar (for running steps) */}
            {step.status === "running" && (
              <div className="mt-2">
                <Progress value={step.progress} className="h-2" />
                <p className="text-xs text-muted-foreground mt-1">
                  {step.progress}% complete
                </p>
              </div>
            )}

            {/* Error Message (for failed steps) */}
            {step.status === "failed" && (
              <Alert variant="destructive" className="mt-2">
                <AlertDescription>{step.error}</AlertDescription>
              </Alert>
            )}

            {/* Action Buttons */}
            <div className="mt-2 flex space-x-2">
              {step.status === "completed" && (
                <>
                  <Button variant="outline" size="sm" onClick={() => viewOutput(step.id)}>
                    View Output
                  </Button>
                  <Button variant="outline" size="sm" onClick={() => downloadOutput(step.id)}>
                    Download
                  </Button>
                </>
              )}
              {step.status === "failed" && (
                <Button variant="outline" size="sm" onClick={() => retryStep(step.id)}>
                  Retry
                </Button>
              )}
            </div>
          </div>
        </div>
      ))}
    </div>
  </CardContent>

  <CardFooter>
    {allCompleted && (
      <Button className="w-full" onClick={viewAllResults}>
        View All Results
      </Button>
    )}
  </CardFooter>
</Card>
```

**Features:**
- Real-time status updates (WebSocket)
- Progress bars for running steps
- Error messages for failed steps
- Retry button for failures
- View/download outputs for completed steps

**Update Frequency:**
- Status: Real-time (WebSocket)
- Progress: Every 5 seconds (HTTP polling fallback)

---

### 6. Error Handling UI

**Error Types:**

```tsx
// Inline Error (within chat)
<div className="flex items-start space-x-2 p-3 bg-destructive/10 border-l-4 border-destructive rounded">
  <AlertTriangleIcon className="w-5 h-5 text-destructive flex-shrink-0 mt-0.5" />
  <div>
    <p className="text-sm font-medium text-destructive">Upload Failed</p>
    <p className="text-sm text-muted-foreground mt-1">
      File size exceeds 100GB limit. Please compress or split the file.
    </p>
    <Button variant="link" size="sm" className="mt-2 p-0 h-auto">
      Learn more about file size limits
    </Button>
  </div>
</div>

// Toast Error (for transient errors)
<Toast variant="destructive">
  <ToastTitle>Network Error</ToastTitle>
  <ToastDescription>
    Failed to connect to server. Retrying in 5 seconds...
  </ToastDescription>
</Toast>

// Modal Error (for critical errors)
<AlertDialog open={criticalError} onOpenChange={setCriticalError}>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Workflow Execution Failed</AlertDialogTitle>
      <AlertDialogDescription>
        The workflow failed due to insufficient memory.
        Try reducing the input file size or contact support.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel>Close</AlertDialogCancel>
      <AlertDialogAction onClick={contactSupport}>
        Contact Support
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

**Error Categories:**

| Error Type | Display Method | User Action |
|------------|----------------|-------------|
| Upload failure | Inline (chat) | Retry, contact support |
| Network issue | Toast | Auto-retry |
| Workflow failure | Inline (timeline) | Retry step, adjust parameters |
| Auth failure | Modal | Re-login |
| Critical system error | Modal | Contact support |

**Helpful Error Messages:**

❌ **Bad:** "Error 500"
✅ **Good:** "Server error. Our team has been notified. Please try again in a few minutes."

❌ **Bad:** "Invalid input"
✅ **Good:** "The FASTQ file is missing quality scores. Please check that it's a valid FASTQ file."

---

## Visual Design

### Color Palette

**Light Mode:**
- Background: #FFFFFF (white)
- Foreground: #09090B (near-black)
- Primary: #0EA5E9 (sky blue)
- Accent: #F0F9FF (light blue)
- Border: #E4E4E7 (light gray)

**Dark Mode:**
- Background: #09090B (near-black)
- Foreground: #FAFAFA (near-white)
- Primary: #0EA5E9 (sky blue)
- Accent: #0C4A6E (dark blue)
- Border: #27272A (dark gray)

### Typography

- **Headings:** Inter, 600-700 weight
- **Body:** Inter, 400 weight
- **Code:** JetBrains Mono, 400 weight

### Spacing

- Base unit: 4px (0.25rem)
- Common spacing: 8px, 12px, 16px, 24px, 32px, 48px

### Component Library

**Using shadcn/ui (already in project):**
- Button
- Input, Textarea
- Card
- Dialog, AlertDialog
- DropdownMenu
- Progress
- Toast
- Collapsible
- Select

---

## Performance Requirements

### Load Times

| Metric | Target (95th percentile) |
|--------|--------------------------|
| Initial page load | <2 seconds |
| Chat message send → response | <1 second |
| File upload (1GB) | <2 minutes |
| Workflow visualization render | <500ms |
| Execution status update | <100ms (real-time) |

### Responsiveness

| Breakpoint | Layout |
|------------|--------|
| Desktop (>1024px) | Full interface |
| Tablet (768px-1024px) | Single column, collapsible sidebar |
| Mobile (<768px) | Not supported (show "Please use desktop" message) |

**Note:** Full mobile support deferred to P2.

---

## Implementation Plan

### Day 1: Core Layout & Header

- [ ] Header bar with logo, project selector, user menu
- [ ] Main layout (chat on left, artifacts on right)
- [ ] Responsive breakpoints
- [ ] Theme toggle (light/dark mode)

### Day 2: Chat Interface

- [ ] Message history (scrollable)
- [ ] Chat input with auto-resize
- [ ] Send message functionality
- [ ] Typing indicator
- [ ] Auto-scroll to bottom

### Day 3: File Upload

- [ ] File upload dialog
- [ ] Drag-and-drop support
- [ ] Multi-file selection
- [ ] Progress bars
- [ ] Error handling

### Day 4: Workflow Visualization

- [ ] Workflow card component
- [ ] Linear step list
- [ ] Collapsible parameters
- [ ] Export functionality
- [ ] Run button integration

### Day 5: Execution Timeline

- [ ] Timeline component
- [ ] Status icons (pending, running, completed, failed)
- [ ] Progress bars
- [ ] Error messages
- [ ] Retry functionality

### Day 6: Error Handling & Polish

- [ ] Toast notifications
- [ ] Inline error messages
- [ ] Modal error dialogs
- [ ] Loading states
- [ ] Empty states

**Testing:** Days 5-6 (parallel with implementation)
**Deployment:** Day 7 (after E2E tests pass)

---

## What We're NOT Building

### Deferred to Chatboard (P1, Month 2-3)

**Multi-Panel Workspace:**
- ❌ Separate panels for Chat, Canvas, Knowledge, Context
- ❌ Resizable panels
- ❌ Panel state persistence

**Interactive Workflow Canvas:**
- ❌ Drag-and-drop node editor
- ❌ Visual connections between steps
- ❌ Real-time parameter editing
- ❌ Multiple workflow tabs

**Knowledge Panel:**
- ❌ Literature search results
- ❌ AI suggestions
- ❌ Tool documentation
- ❌ Best practices

**Context Panel:**
- ❌ Decision logs
- ❌ Version history
- ❌ Annotations
- ❌ Change tracking

**Collaboration:**
- ❌ Real-time co-editing
- ❌ User cursors
- ❌ Chat with team members
- ❌ Commenting on steps

### Deferred to P2-P3

**Advanced Features:**
- ❌ Custom dashboards
- ❌ Report generation UI
- ❌ Batch workflow execution
- ❌ API playground
- ❌ Mobile app

---

## Success Metrics

### Launch (Week 2)

- ✅ 5-10 pilot customers can log in and navigate UI
- ✅ <3 seconds page load time (95th percentile)
- ✅ File upload success rate >95%
- ✅ Zero critical UI bugs
- ✅ User satisfaction >7/10

### Month 1

- ✅ 50+ workflows generated via chat interface
- ✅ 80%+ user satisfaction with chat UX
- ✅ <2 support tickets per user (UI confusion)
- ✅ 100% of pilot users complete at least one workflow

---

## Appendix

### Example Wireframes

**Main Interface (Desktop):**

```
┌───────────────────────────────────────────────────────────────────┐
│ [Logo] BioMate    [Project: RNA-seq Analysis ▾]         [User ▾] │
├───────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────────────────────────────┬──────────────────────────┐   │
│  │  Chat Interface                │  Workflow Visualization  │   │
│  │                                 │                          │   │
│  │  [AI Message]                  │  ┌────────────────────┐ │   │
│  │  Hello! How can I help?        │  │ Generated Workflow │ │   │
│  │                                 │  ├────────────────────┤ │   │
│  │  [User Message]                │  │ 1. FastQC          │ │   │
│  │  Analyze RNA-seq data          │  │ 2. STAR            │ │   │
│  │                                 │  │ 3. featureCounts   │ │   │
│  │  [AI Message]                  │  │ 4. DESeq2          │ │   │
│  │  Great! Let me create a        │  │                    │ │   │
│  │  workflow...                    │  │ [Export] [Run]    │ │   │
│  │                                 │  └────────────────────┘ │   │
│  │                                 │                          │   │
│  │                                 │  ┌────────────────────┐ │   │
│  │  ┌────────────────────────┐   │  │ Execution Timeline │ │   │
│  │  │ [📎] [Type message...] │   │  ├────────────────────┤ │   │
│  │  │                 [Send] │   │  │ ✓ FastQC (done)    │ │   │
│  │  └────────────────────────┘   │  │ ⏳ STAR (running)  │ │   │
│  │                                 │  │ ○ featureCounts   │ │   │
│  └────────────────────────────────┘  │ ○ DESeq2          │ │   │
│                                       └────────────────────┘ │   │
└───────────────────────────────────────────────────────────────────┘
```

**Mobile (Deferred):**
- Single column layout
- Collapsible sections
- Bottom navigation

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Next Review:** Before implementation (Week 1, Day 1)
**Owner:** BioMate Frontend Team
