import { createRoot } from "react-dom/client";
import { Component, type ReactNode } from "react";
import App from "./App";
import "./index.css";

// Global error boundary to capture React render crashes (prevents blank pages,
// logs the actual error so we can diagnose and fix the root cause).
class AppErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  constructor(props: { children: ReactNode }) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: { componentStack: string }) {
    // Log with full stack trace so Playwright/DevTools captures it
    console.error('[AppErrorBoundary] React render crash:', error.message);
    console.error('[AppErrorBoundary] Stack:', error.stack);
    console.error('[AppErrorBoundary] Component stack:', info.componentStack?.split('\n').slice(0, 8).join('\n'));
  }

  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: '24px', fontFamily: 'monospace', color: '#dc2626', background: '#fef2f2', minHeight: '100vh' }}>
          <h2 style={{ margin: '0 0 12px' }}>Application Error</h2>
          <pre style={{ fontSize: '12px', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
            {this.state.error.message}
            {'\n\n'}
            {this.state.error.stack}
          </pre>
          <button
            style={{ marginTop: '16px', padding: '8px 16px', cursor: 'pointer' }}
            onClick={() => { this.setState({ error: null }); window.location.reload(); }}
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

createRoot(document.getElementById("root")!).render(
  <AppErrorBoundary>
    <App />
  </AppErrorBoundary>
);
