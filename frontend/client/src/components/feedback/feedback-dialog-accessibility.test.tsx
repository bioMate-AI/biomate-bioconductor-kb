import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { PostRunMicroSurvey } from "./post-run-micro-survey";
import { SessionEndPulse } from "./session-end-pulse";

describe("Feedback dialog accessibility", () => {
  it("renders post-run survey with description and guarded submit", async () => {
    render(
      <PostRunMicroSurvey
        open
        onOpenChange={vi.fn()}
        runId="run-1"
        runStatus="completed"
        sessionId="session-1"
      />
    );

    expect(screen.getByRole("dialog", { name: /quick feedback/i })).toBeInTheDocument();
    expect(
      screen.getByText("Share quick feedback on run clarity, outputs, and usability.")
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Submit" })).toBeDisabled();
  });

  it("renders session pulse with description and guarded submit", async () => {
    render(<SessionEndPulse open onOpenChange={vi.fn()} sessionId="session-1" runId="run-1" />);

    expect(screen.getByRole("dialog", { name: /before you go/i })).toBeInTheDocument();
    expect(
      screen.getByText("Two quick questions to improve the session experience.")
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Submit" })).toBeDisabled();
  });
});
