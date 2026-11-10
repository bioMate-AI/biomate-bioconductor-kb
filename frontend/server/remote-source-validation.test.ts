import { describe, expect, it } from "vitest";
import { validateRemoteFileUrl } from "./remote-source-validation";

describe("validateRemoteFileUrl", () => {
  it.each([
    "https://data.example.org/reads.fastq.gz",
    "ftp://ftp.ncbi.nlm.nih.gov/path/file.fna.gz",
    "s3://research-bucket/project/sample.bam",
  ])("accepts one remote object: %s", (value) => {
    const result = validateRemoteFileUrl(value);
    expect(result.ok).toBe(true);
  });

  it("does not let URL credentials enter logs or dataset metadata", () => {
    const result = validateRemoteFileUrl("ftp://researcher:secret@ftp.example.org/data.fastq.gz");
    expect(result).toEqual(expect.objectContaining({ ok: false }));
    if (!result.ok) expect(result.error).toMatch(/credentials/i);
  });

  it("rejects an S3 prefix instead of falsely treating a folder as one dataset", () => {
    const result = validateRemoteFileUrl("s3://research-bucket/project/samples/");
    expect(result).toEqual(expect.objectContaining({ ok: false }));
    if (!result.ok) expect(result.error).toMatch(/folder/i);
  });

  it("rejects schemes with no fetch implementation", () => {
    expect(validateRemoteFileUrl("sftp://lab.example.org/data.fastq.gz")).toEqual(
      expect.objectContaining({ ok: false }),
    );
  });

  it.each([
    "https://drive.google.com/file/d/1MEtESuHlAQxaKpBiVKYg6j9hnXA6PhBH/view?usp=drive_link",
    "https://drive.google.com/open?id=1MEtESuHlAQxaKpBiVKYg6j9hnXA6PhBH",
    "https://drive.google.com/uc?id=1MEtESuHlAQxaKpBiVKYg6j9hnXA6PhBH&export=download",
  ])("rewrites a Google Drive share link to a direct large-file download: %s", (value) => {
    const result = validateRemoteFileUrl(value);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.url.hostname).toBe("drive.usercontent.google.com");
      expect(result.url.searchParams.get("id")).toBe("1MEtESuHlAQxaKpBiVKYg6j9hnXA6PhBH");
      expect(result.url.searchParams.get("confirm")).toBe("t");
    }
  });

  it("rewrites a Dropbox share link to a direct download (dl=1)", () => {
    const result = validateRemoteFileUrl("https://www.dropbox.com/s/abc123/reads.fastq.gz?dl=0");
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.url.searchParams.get("dl")).toBe("1");
  });
});
