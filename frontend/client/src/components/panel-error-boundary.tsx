import { Component, type ReactNode } from "react";

/**
 * Panel-scoped React error boundary.
 *
 * main.tsx's AppErrorBoundary wraps the whole <App/>, so without a nested
 * boundary a render throw inside the chat/workflow panel blanks the ENTIRE app.
 * This component (same contract: getDerivedStateFromError + componentDidCatch)
 * catches a crash within its subtree and shows a localized, on-theme fallback —
 * the rest of the app keeps working.
 *
 * "Reload" resets the boundary so the subtree re-mounts (recovers from a
 * transient render error); a deterministic crash simply re-shows the fallback.
 */
interface PanelErrorBoundaryProps {
  children: ReactNode;
  /** Short label for the fallback copy, e.g. "workflow panel". */
  label?: string;
}

interface PanelErrorBoundaryState {
  error: Error | null;
}

export class PanelErrorBoundary extends Component<PanelErrorBoundaryProps, PanelErrorBoundaryState> {
  constructor(props: PanelErrorBoundaryProps) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error: Error): PanelErrorBoundaryState {
    return { error };
  }

  componentDidCatch(error: Error, info: { componentStack: string }) {
    const scope = this.props.label ? ` [${this.props.label}]` : "";
    console.error(`[PanelErrorBoundary]${scope} render crash:`, error.message);
    console.error(`[PanelErrorBoundary]${scope} Stack:`, error.stack);
    console.error(
      `[PanelErrorBoundary]${scope} Component stack:`,
      info.componentStack?.split("\n").slice(0, 8).join("\n"),
    );
  }

  private handleReload = () => {
    this.setState({ error: null });
  };

  render() {
    if (this.state.error) {
      return (
        <div
          data-testid="panel-error-boundary-fallback"
          className="flex h-full flex-col items-center justify-center gap-3 p-6 text-center"
        >
          <p className="text-sm font-medium text-destructive">
            This panel hit an error.
          </p>
          <p className="max-w-xs text-xs text-muted-foreground">
            The rest of the app is still working. You can reload this panel to try again.
          </p>
          <button
            type="button"
            onClick={this.handleReload}
            className="rounded-md border px-3 py-1.5 text-xs font-medium hover:bg-muted"
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
