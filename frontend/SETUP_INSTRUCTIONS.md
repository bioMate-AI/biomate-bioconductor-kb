# GalaxyChat Version 2 - Setup Instructions

## Current Status
✅ Repository cloned from https://github.com/bioMate-AI/GalaxyChat_version2
✅ Dependencies installed (480 packages)
✅ Project structure in place

## What's Ready
- **React + TypeScript** frontend with Vite
- **Express** backend server
- **Tailwind CSS** with shadcn/ui components
- **OpenAI integration** for chat
- **Full-stack architecture** (client + server)

## To Launch the UI

### 1. Add Your OpenAI API Key

Edit the `.env` file in `/private/tmp/GalaxyChat_version2/.env`:

```bash
# Replace with your actual OpenAI API key
OPENAI_API_KEY=sk-your-actual-api-key-here
```

### 2. Start the Development Server

```bash
cd /private/tmp/GalaxyChat_version2
npm run dev
```

This will start:
- **Frontend** (Vite dev server with React)
- **Backend** (Express server with OpenAI chat)
- **Auto-reload** on file changes

### 3. Open in Browser

The server will automatically open your browser to:
```
http://localhost:5173
```

Or open it manually in your browser.

## Project Structure

```
/private/tmp/GalaxyChat_version2/
├── client/                    # Frontend React app
│   └── src/
│       ├── App.tsx           # Main app component
│       ├── components/       # UI components (26 components)
│       ├── pages/            # Page components
│       ├── hooks/            # React hooks
│       ├── lib/              # Utilities
│       └── index.css         # Tailwind styles
│
├── server/                    # Backend Express server
│   ├── index.ts              # Server entry point
│   ├── routes.ts             # API routes
│   └── storage/              # Data storage
│
├── shared/                    # Shared types/schemas
│
├── package.json               # Dependencies
├── vite.config.ts            # Vite configuration
└── tsconfig.json             # TypeScript config
```

## Features

### Current UI Components
Based on the parameter design documents, the UI should include:

1. **Chat Interface**
   - Natural language input
   - Conversation history
   - AI-powered responses

2. **Workflow Builder**
   - Visual pipeline creation
   - Step-by-step configuration
   - Parameter editing

3. **Parameter System** (from PARAMETER_INTERFACE_DESIGN.md)
   - Three-layer progressive disclosure:
     - **Layer 1:** Essential parameters (3-5 params)
     - **Layer 2:** Common adjustments
     - **Layer 3:** Advanced parameters
   - Smart defaults
   - AI suggestions

4. **Data Upload**
   - File upload interface
   - Data validation
   - Format detection

## Getting Your OpenAI API Key

1. Go to https://platform.openai.com/api-keys
2. Sign in or create an account
3. Click "Create new secret key"
4. Copy the key and paste it in `.env`

## Alternative: Run Without OpenAI (Mock Mode)

If you want to test the UI without OpenAI, you can modify `server/routes.ts` to use mock responses instead of calling the OpenAI API. Let me know if you need help with this.

## Troubleshooting

### Issue: Missing OpenAI API Key
```
Error: Missing credentials. Please pass an `apiKey`
```
**Solution:** Add your API key to `.env` file

### Issue: Port Already in Use
```
Error: listen EADDRINUSE: address already in use :::5173
```
**Solution:** Kill the process using port 5173
```bash
lsof -ti:5173 | xargs kill -9
```

### Issue: npm Install Errors
```
Error: EACCES: permission denied
```
**Solution:** Use local cache
```bash
npm install --cache /private/tmp/npm-cache
```

## Next Steps

1. ✅ Add OpenAI API key to `.env`
2. ✅ Run `npm run dev`
3. ✅ Open http://localhost:5173
4. ✅ Start modifying the UI!

## Customization

The UI uses:
- **Tailwind CSS** for styling
- **shadcn/ui** for components
- **Radix UI** for primitives
- **Framer Motion** for animations

All components are in `client/src/components/ui/` and can be customized.

---

**Status:** Ready to launch (just needs OpenAI API key)
**Location:** `/private/tmp/GalaxyChat_version2/`
