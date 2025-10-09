# Galaxy Chatbot Interface Design Guidelines

## Design Approach
**Reference-Based Approach**: Drawing inspiration from ChatGPT and Claude interfaces, focusing on conversational UX patterns with a scientific tool discovery overlay. The design prioritizes clarity, accessibility, and workflow simplification over the complex Galaxy interface.

## Core Design Principles
- **Conversational First**: Chat interface as primary interaction method
- **Progressive Disclosure**: Reveal complexity gradually through simplified workflows
- **Light & Friendly**: Transform Galaxy's dark scientific aesthetic to approachable, modern styling
- **Tool Discovery**: Make complex bioinformatics tools discoverable through natural conversation

## Color Palette

### Light Mode (Primary)
- **Primary**: 220 85% 45% (Modern blue for trust and scientific credibility)
- **Background**: 220 15% 98% (Warm white for friendliness)
- **Surface**: 220 10% 95% (Subtle gray for cards and panels)
- **Text Primary**: 220 15% 15% (Near black for readability)
- **Text Secondary**: 220 10% 45% (Medium gray for supporting text)

### Dark Mode (Secondary)
- **Primary**: 220 85% 60% (Lighter blue for dark backgrounds)
- **Background**: 220 15% 8% (Deep blue-gray)
- **Surface**: 220 10% 12% (Elevated surfaces)
- **Text Primary**: 220 15% 95% (Near white)
- **Text Secondary**: 220 10% 65% (Light gray)

### Accent Colors
- **Success**: 145 65% 45% (Green for completed workflows)
- **Warning**: 35 85% 55% (Orange for complex workflow alerts)
- **Error**: 355 75% 50% (Red for errors)

## Typography
- **Primary Font**: Inter (Google Fonts) - Clean, technical readability
- **Code Font**: JetBrains Mono (Google Fonts) - For workflow syntax and tool parameters
- **Hierarchy**: Scale from 12px to 32px using 1.125 ratio

## Layout System
**Tailwind Spacing Units**: Consistent use of 2, 4, 6, 8, 12, 16 units
- Tight spacing: p-2, m-2 (8px)
- Standard spacing: p-4, m-4 (16px) 
- Generous spacing: p-8, m-8 (32px)
- Section spacing: p-12, m-12 (48px)

## Component Library

### Chat Interface
- **Message Bubbles**: Rounded-lg with user/assistant distinction
- **Typing Indicators**: Animated dots with primary color
- **Input Field**: Large, rounded with tool suggestion dropdown
- **Message Actions**: Copy, regenerate, create workflow buttons

### Tool Discovery
- **Category Cards**: Grid layout with icons and descriptions
- **Tool Browser**: Searchable list with filtering capabilities
- **Quick Actions**: Floating action buttons for common workflows

### Workflow Builder
- **Step Cards**: Visual workflow steps with progress indicators
- **Drag & Drop**: Intuitive workflow construction
- **Complexity Meter**: Visual indicator for workflow difficulty
- **Simplification Suggestions**: AI-powered workflow optimization

### Navigation
- **Sidebar**: Collapsible with chat history and tool categories
- **Header**: Minimal with search and user settings
- **Breadcrumbs**: For deep tool navigation

## Visual Treatments
**Gradients**: Subtle blue gradients (220 85% 50% to 220 75% 60%) for hero sections and primary buttons
**Shadows**: Soft drop shadows using gray-900/5 for depth
**Borders**: 1px solid borders using gray-200 for definition
**Animations**: Minimal, focused on state transitions and loading states

## Images
**Hero Section**: Large background image showing abstract data visualization or scientific imagery with gradient overlay (220 85% 45% to transparent)
**Tool Icons**: Simple, monochromatic icons representing each Galaxy tool category
**Workflow Diagrams**: Clean, schematic representations of simplified workflows
**Avatar Placeholders**: Circular user and assistant avatars for chat interface

The design transforms Galaxy's complex scientific interface into an approachable, conversation-driven experience while maintaining the powerful functionality scientists need.