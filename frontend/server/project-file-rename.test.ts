/**
 * Rename / move of project files — behaviour of the pure name rules the routes apply
 * (PATCH /api/projects/:id/files/:fileId and POST /api/projects/:id/files/rename-folder),
 * plus the object-key allocation that keeps a renamed file's bytes from being overwritten.
 */
import { describe, expect, it } from "vitest";
import {
  normalizeProjectFileName,
  findNameConflict,
  planFileRename,
  planFolderRename,
  withKeySuffix,
  objectKeyCandidates,
  pickFreeObjectKey,
  projectInputPath,
} from "./project-file-paths";

const rows = [
  { id: "1", name: "x/a.csv", source: "upload" },
  { id: "2", name: "x/sub/c.tsv", source: "upload" },
  { id: "3", name: "top.csv", source: "url" },
  { id: "4", name: "multiqc_report.html", source: "run_output" },
  { id: "5", name: "QC_Report.txt", source: "run_code" },
];

describe("normalizeProjectFileName", () => {
  it("keeps folders, trims segments, drops empty and '.' segments", () => {
    expect(normalizeProjectFileName(" y / b.csv ")).toEqual({ ok: true, name: "y/b.csv" });
    expect(normalizeProjectFileName("./y//b.csv/")).toEqual({ ok: true, name: "y/b.csv" });
    expect(normalizeProjectFileName("y\\b.csv")).toEqual({ ok: true, name: "y/b.csv" });
    expect(normalizeProjectFileName("样本/数据 A.csv")).toEqual({ ok: true, name: "样本/数据 A.csv" });
  });

  it("produces the same stored name an upload with that relative path would", () => {
    const n = normalizeProjectFileName("run1/fastq/S1.fastq.gz");
    expect(n.ok && n.name).toBe(projectInputPath("S1.fastq.gz", "run1/fastq/S1.fastq.gz").name);
  });

  it("refuses what an upload would silently drop: '..', control characters, empty, over-long, too deep", () => {
    expect(normalizeProjectFileName("../etc/passwd").ok).toBe(false);
    expect(normalizeProjectFileName("a/../b.csv").ok).toBe(false);
    expect(normalizeProjectFileName("a\u0000b.csv").ok).toBe(false);
    expect(normalizeProjectFileName("a\nb.csv").ok).toBe(false);
    expect(normalizeProjectFileName("  / ./ ").ok).toBe(false);
    expect(normalizeProjectFileName("").ok).toBe(false);
    expect(normalizeProjectFileName(42).ok).toBe(false);
    expect(normalizeProjectFileName("x".repeat(201)).ok).toBe(false);
    expect(normalizeProjectFileName("x".repeat(200)).ok).toBe(true);
    expect(normalizeProjectFileName(Array(33).fill("d").join("/")).ok).toBe(false);
    expect(normalizeProjectFileName(Array(32).fill("d").join("/")).ok).toBe(true);
  });
});

describe("findNameConflict", () => {
  it("flags identical names and file/folder clashes", () => {
    expect(findNameConflict("x/a.csv", ["x/a.csv"])).toBe("x/a.csv");
    expect(findNameConflict("x", ["x/a.csv"])).toBe("x/a.csv");        // a file where a folder is
    expect(findNameConflict("top.csv/n.txt", ["top.csv"])).toBe("top.csv"); // a folder where a file is
    expect(findNameConflict("x/a.csv2", ["x/a.csv"])).toBeNull();
    expect(findNameConflict("xa.csv", ["x/a.csv"])).toBeNull();
  });
});

describe("planFileRename", () => {
  it("renames and moves into a new folder", () => {
    expect(planFileRename(rows, "1", "y/b.csv")).toEqual({ ok: true, moves: [{ id: "1", from: "x/a.csv", to: "y/b.csv" }] });
  });

  it("an unchanged name is a no-op, not a self-collision", () => {
    expect(planFileRename(rows, "1", " x/a.csv ")).toEqual({ ok: true, moves: [] });
  });

  it("409 when another file already has the name — including a run output or generated file", () => {
    const a = planFileRename(rows, "1", "top.csv");
    expect(a.ok).toBe(false);
    expect(!a.ok && a.status).toBe(409);
    expect(!a.ok && a.conflicts).toEqual([{ name: "top.csv", existing: "top.csv" }]);
    expect((planFileRename(rows, "3", "multiqc_report.html") as any).status).toBe(409);
    expect((planFileRename(rows, "3", "QC_Report.txt") as any).status).toBe(409);
    expect((planFileRename(rows, "3", "x") as any).status).toBe(409); // "x" is a folder
  });

  it("400 for an invalid name or a run output; 404 for an unknown file", () => {
    expect((planFileRename(rows, "1", "../b.csv") as any).status).toBe(400);
    expect((planFileRename(rows, "4", "renamed.html") as any).status).toBe(400);
    expect((planFileRename(rows, "nope", "b.csv") as any).status).toBe(404);
  });

  it("generated (run_code) files can be renamed", () => {
    expect(planFileRename(rows, "5", "reports/QC.txt").ok).toBe(true);
  });
});

describe("planFolderRename", () => {
  it("moves every file under the folder (nested too), prefix-exact", () => {
    const withLookalike = [...rows, { id: "6", name: "xy/d.csv", source: "upload" }];
    const p = planFolderRename(withLookalike, "x", "z/archive");
    expect(p).toEqual({
      ok: true, from: "x", to: "z/archive",
      moves: [
        { id: "1", from: "x/a.csv", to: "z/archive/a.csv" },
        { id: "2", from: "x/sub/c.tsv", to: "z/archive/sub/c.tsv" },
      ],
    });
  });

  it("renames a nested folder only", () => {
    const p = planFolderRename(rows, "x/sub", "x/sub2");
    expect(p.ok && p.moves).toEqual([{ id: "2", from: "x/sub/c.tsv", to: "x/sub2/c.tsv" }]);
  });

  it("all-or-nothing: any clash with a file that stays refuses the whole move", () => {
    const p = planFolderRename([...rows, { id: "7", name: "z/sub/c.tsv", source: "upload" }], "x", "z");
    expect(p.ok).toBe(false);
    expect(!p.ok && p.status).toBe(409);
    expect(!p.ok && p.conflicts).toEqual([{ name: "z/sub/c.tsv", existing: "z/sub/c.tsv" }]);
    // a FILE named like the destination folder also clashes
    expect((planFolderRename(rows, "x", "top.csv") as any).status).toBe(409);
  });

  it("swapping names inside the moving set is not a clash", () => {
    // x/a.csv → q/a.csv while nothing else is under q/
    expect(planFolderRename(rows, "x", "q").ok).toBe(true);
  });

  it("400 for same name, into itself, or an invalid path; 404 when no files are under it", () => {
    expect((planFolderRename(rows, "x", "x") as any).status).toBe(400);
    expect((planFolderRename(rows, "x", "x/inner") as any).status).toBe(400);
    expect((planFolderRename(rows, "x", "../z") as any).status).toBe(400);
    expect((planFolderRename(rows, "nope", "z") as any).status).toBe(404);
  });

  it("run outputs are never moved by a folder rename", () => {
    const p = planFolderRename([{ id: "8", name: "out/r.txt", source: "run_output" }], "out", "o2");
    expect((p as any).status).toBe(404);
  });
});

describe("object key allocation", () => {
  it("suffixes before the first dot of the last segment", () => {
    expect(withKeySuffix("projects/p/inputs/x/S1.fastq.gz", 2)).toBe("projects/p/inputs/x/S1-2.fastq.gz");
    expect(withKeySuffix("projects/p/inputs/x/a.csv.v3", 2)).toBe("projects/p/inputs/x/a-2.csv.v3");
    expect(withKeySuffix("projects/p/inputs/README", 3)).toBe("projects/p/inputs/README-3");
    expect(withKeySuffix("projects/p/inputs/.env", 2)).toBe("projects/p/inputs/.env-2");
  });

  it("uses the name-derived key when free, else the first free suffixed key", () => {
    const c = objectKeyCandidates("projects/p/inputs/x/a.csv", 4);
    expect(c).toEqual([
      "projects/p/inputs/x/a.csv", "projects/p/inputs/x/a-2.csv",
      "projects/p/inputs/x/a-3.csv", "projects/p/inputs/x/a-4.csv",
    ]);
    expect(pickFreeObjectKey(c, new Set())).toBe(c[0]);
    // after x/a.csv was renamed to y/b.csv its bytes still live at …/x/a.csv:
    // a new upload named x/a.csv must not reuse that key.
    expect(pickFreeObjectKey(c, new Set([c[0]]))).toBe(c[1]);
    expect(pickFreeObjectKey(c, new Set(c))).toBeNull();
  });
});
