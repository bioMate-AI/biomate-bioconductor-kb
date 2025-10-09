# Overview

BioMate is a conversational AI-powered bioinformatics platform that simplifies complex genomic analysis workflows. The application transforms traditional command-line bioinformatics tools into an intuitive chat interface, allowing researchers to discover tools, build workflows, and analyze data through natural language interactions. The platform focuses on making bioinformatics accessible to users of all skill levels by providing guided workflows, tool recommendations, and automated pipeline generation.

# User Preferences

Preferred communication style: Simple, everyday language.

# System Architecture

## Frontend Architecture
- **Framework**: React 18 with TypeScript and Vite for fast development and building
- **UI Components**: Radix UI primitives with shadcn/ui component library for accessible, customizable components
- **Styling**: Tailwind CSS with custom design tokens following a light-first approach
- **State Management**: TanStack Query for server state management and caching
- **Routing**: Wouter for lightweight client-side routing
- **Theme System**: Custom theme provider supporting light/dark modes with CSS custom properties

## Backend Architecture
- **Server Framework**: Express.js with TypeScript for REST API endpoints
- **Database ORM**: Drizzle ORM for type-safe database operations with PostgreSQL
- **Session Management**: In-memory storage with planned database persistence
- **AI Integration**: OpenAI GPT-4 for conversational AI and bioinformatics assistance
- **Development Setup**: Hot module replacement with Vite integration for seamless development

## Component Design System
- **Design Philosophy**: Reference-based approach inspired by ChatGPT/Claude interfaces with scientific tool discovery overlay
- **Color Palette**: Modern blue primary (220 85% 45%) with warm light backgrounds and comprehensive dark mode support
- **Typography**: Inter for UI text, JetBrains Mono for code/technical content
- **Layout System**: Consistent spacing using Tailwind's 2/4/6/8/12/16 unit scale
- **Interactive Elements**: Hover and active states with elevation effects for tactile feedback

## Core Features Architecture
- **Chat Interface**: Message bubbles with role-based styling, typing indicators, and suggestion chips
- **Workflow Builder**: Visual workflow representation with drag-and-drop functionality and step-by-step configuration
- **Tool Discovery**: Categorized tool browser with search functionality and complexity indicators
- **Progress Tracking**: Real-time workflow execution monitoring with status updates and time estimates

# External Dependencies

## Core Dependencies
- **@neondatabase/serverless**: Neon PostgreSQL database connectivity
- **@tanstack/react-query**: Server state management and data fetching
- **drizzle-orm**: Type-safe database ORM with PostgreSQL dialect
- **express**: Node.js web application framework

## AI Integration
- **openai**: Official OpenAI API client for GPT-4 chat completions

## UI Framework
- **@radix-ui/***: Comprehensive set of accessible, unstyled UI primitives
- **tailwindcss**: Utility-first CSS framework with custom configuration
- **class-variance-authority**: Type-safe variant API for component styling
- **clsx**: Conditional className utility for dynamic styling

## Development Tools
- **vite**: Fast build tool with React plugin and development server
- **typescript**: Type safety and enhanced developer experience
- **wouter**: Minimalist router for React applications
- **date-fns**: Modern date utility library for formatting and manipulation