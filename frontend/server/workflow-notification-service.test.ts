import { describe, it, expect, vi, beforeEach } from "vitest";
import { EventEmitter } from "events";
import { WorkflowNotificationService } from "./workflow-notification-service";

const emailMocks = vi.hoisted(() => ({
  sendWorkflowCompleteEmail: vi.fn().mockResolvedValue(undefined),
  sendWorkflowErrorEmail: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("./email-service", () => ({
  emailService: {
    sendWorkflowCompleteEmail: emailMocks.sendWorkflowCompleteEmail,
    sendWorkflowErrorEmail: emailMocks.sendWorkflowErrorEmail,
  },
}));

class MockPoller extends EventEmitter {
  getState(_invocationId: string) {
    return {
      steps: [{ state: "ok", jobs: [{ state: "ok" }] }],
    };
  }
}

describe("WorkflowNotificationService", () => {
  let poller: MockPoller;
  let service: WorkflowNotificationService;

  beforeEach(() => {
    vi.clearAllMocks();
    poller = new MockPoller();
    service = new WorkflowNotificationService(poller as any, {} as any);
  });

  it("sends only one completion email for duplicate workflow_completed events", async () => {
    service.registerInvocation("inv-1", {
      userId: "u1",
      userEmail: "user@example.com",
      userName: "user",
      workflowName: "wf",
      workflowId: "wf-1",
      startTime: new Date(),
    });

    poller.emit("workflow_completed", { invocation_id: "inv-1", state: "ok" });
    poller.emit("workflow_completed", { invocation_id: "inv-1", state: "ok" });
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(emailMocks.sendWorkflowCompleteEmail).toHaveBeenCalledTimes(1);
    expect(emailMocks.sendWorkflowErrorEmail).toHaveBeenCalledTimes(0);
  });

  it("does not send polling_failed email after completion already handled", async () => {
    service.registerInvocation("inv-2", {
      userId: "u1",
      userEmail: "user@example.com",
      userName: "user",
      workflowName: "wf",
      workflowId: "wf-1",
      startTime: new Date(),
    });

    poller.emit("workflow_completed", { invocation_id: "inv-2", state: "ok" });
    await new Promise((resolve) => setTimeout(resolve, 10));
    poller.emit("polling_failed", { invocation_id: "inv-2", error: "timeout" });
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(emailMocks.sendWorkflowCompleteEmail).toHaveBeenCalledTimes(1);
    expect(emailMocks.sendWorkflowErrorEmail).toHaveBeenCalledTimes(0);
  });

  it("sends only one polling_failed email for duplicate polling_failed events", async () => {
    service.registerInvocation("inv-3", {
      userId: "u1",
      userEmail: "user@example.com",
      userName: "user",
      workflowName: "wf",
      workflowId: "wf-1",
      startTime: new Date(),
    });

    poller.emit("polling_failed", { invocation_id: "inv-3", error: "timeout" });
    poller.emit("polling_failed", { invocation_id: "inv-3", error: "timeout" });
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(emailMocks.sendWorkflowCompleteEmail).toHaveBeenCalledTimes(0);
    expect(emailMocks.sendWorkflowErrorEmail).toHaveBeenCalledTimes(1);
  });
});
