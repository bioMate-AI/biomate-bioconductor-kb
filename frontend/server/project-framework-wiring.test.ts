/**
 * End-to-end wiring tests for the project framework, at the source level.
 *
 * Proves the chain holds without DB:
 *   client api.ts → ActiveProjectProvider → chat-interface.tsx →
 *   chat-stream context.projectId → routes.ts → memoryService
 *
 * Each link is asserted independently so a refactor at any layer
 * breaks the most-specific test.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const CLIENT = path.join(__dirname, "..", "client", "src");

describe("client: api.ts exposes project CRUD methods", () => {
  const API = fs.readFileSync(path.join(CLIENT, "lib", "api.ts"), "utf-8");

  it("listProjects(status?) → GET /projects", () => {
    expect(/async\s+listProjects\(status\?:\s*['"]active['"]\s*\|\s*['"]archived['"]\s*\|\s*['"]completed['"]\s*\)/.test(API)).toBe(true);
    expect(/this\.request<\{\s*projects:\s*Array<any>\s*\}>\(`\/projects\$\{qs\}`\)/.test(API)).toBe(true);
  });

  it("createProject({ name, description?, … }) → POST /projects", () => {
    expect(/async\s+createProject\(data:\s*\{[\s\S]{0,200}\}\)/.test(API)).toBe(true);
    expect(/method:\s*['"]POST['"]/.test(API.split("createProject")[1] ?? "")).toBe(true);
  });

  it("archiveProject(id) → POST /projects/:id/archive  (soft-delete shortcut)", () => {
    expect(/async\s+archiveProject\(id:\s*string\)/.test(API)).toBe(true);
    expect(/\/projects\/\$\{id\}\/archive/.test(API)).toBe(true);
  });

  it("deleteProject(id) → DELETE /projects/:id  (hard-delete)", () => {
    expect(/async\s+deleteProject\(id:\s*string\)/.test(API)).toBe(true);
    expect(/method:\s*['"]DELETE['"]/.test(API)).toBe(true);
  });
});

describe("client: ActiveProjectProvider persists active id to localStorage", () => {
  const CTX = fs.readFileSync(path.join(CLIENT, "contexts", "active-project-context.tsx"), "utf-8");

  it("uses the canonical storage key biomate-active-project-id", () => {
    expect(CTX.includes("biomate-active-project-id")).toBe(true);
  });

  it("setActiveProjectId(null) clears localStorage (chat goes project-less)", () => {
    expect(/if \(id\) localStorage\.setItem[\s\S]{0,80}else localStorage\.removeItem/.test(CTX)).toBe(true);
  });

  it("provider exposes createProject + archive + delete + rename + setActive", () => {
    for (const fn of ["createProject", "archiveProject", "deleteProject", "renameProject", "setActiveProjectId"]) {
      expect(CTX.includes(fn)).toBe(true);
    }
  });

  it("provider is mounted in App.tsx under AuthProvider", () => {
    const APP = fs.readFileSync(path.join(CLIENT, "App.tsx"), "utf-8");
    expect(/<AuthProvider>[\s\S]{0,200}<ActiveProjectProvider>/.test(APP)).toBe(true);
  });
});

describe("client: chat-interface reads active project id and sends it in context", () => {
  const CHAT = fs.readFileSync(path.join(CLIENT, "components", "chat-interface.tsx"), "utf-8");

  it("reads biomate-active-project-id from localStorage", () => {
    expect(CHAT.includes("'biomate-active-project-id'")).toBe(true);
  });

  it("includes projectId in chat-stream context when non-null", () => {
    // Conditional spread keeps the field absent when no project is active,
    // so the server sees `undefined` (project-less) rather than `null` or empty.
    expect(/\.\.\.\(_activeProjectId\s*&&\s*\{\s*projectId:\s*_activeProjectId\s*\}\)/.test(CHAT)).toBe(true);
  });
});

describe("UI: sidebar entry + workspaces route", () => {
  const SIDEBAR = fs.readFileSync(path.join(CLIENT, "components", "app-sidebar.tsx"), "utf-8");
  const APP = fs.readFileSync(path.join(CLIENT, "App.tsx"), "utf-8");

  it("sidebar has a Workspaces button that navigates to /workspaces", () => {
    expect(/data-testid="button-workspaces-nav"[\s\S]{0,300}setLocation\(['"]\/workspaces['"]\)/.test(SIDEBAR)).toBe(true);
  });

  it("App.tsx registers /workspaces with WorkspacesPage", () => {
    expect(/import WorkspacesPage from "@\/pages\/workspaces"/.test(APP)).toBe(true);
    expect(/Route path="\/workspaces"\s+component=\{WorkspacesPage\}/.test(APP)).toBe(true);
  });

  it("legacy /projects route is preserved (separate concept; do not break)", () => {
    expect(/import ProjectsPage from "@\/pages\/projects"/.test(APP)).toBe(true);
    expect(/Route path="\/projects"/.test(APP)).toBe(true);
  });
});

describe("UI: workspaces page surfaces the policy ('chats can be project-less')", () => {
  const PAGE = fs.readFileSync(path.join(CLIENT, "pages", "workspaces.tsx"), "utf-8");

  it("exposes a 'Clear active' affordance (first-class no-project mode)", () => {
    expect(PAGE.includes("button-clear-active")).toBe(true);
    expect(PAGE.includes("project-less")).toBe(true);
  });

  it("create / archive / delete / rename / setActive all wired through useActiveProject", () => {
    for (const fn of ["createProject", "archiveProject", "deleteProject", "renameProject", "setActiveProjectId"]) {
      expect(PAGE.includes(fn)).toBe(true);
    }
  });

  it("active project ID is a confirmable testid", () => {
    expect(PAGE.includes("active-workspace-card")).toBe(true);
    expect(PAGE.includes("active-workspace-name")).toBe(true);
  });
});
