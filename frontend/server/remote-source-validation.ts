/**
 * Validation shared by immediate and deferred URL imports.
 *
 * A URL import represents exactly one remote object.  In particular, an S3
 * prefix is not a file: passing it to Galaxy's URL uploader does not browse or
 * attach its contents.  Keep that distinction explicit so the UI never claims
 * a folder was imported when it was not.
 */
const SUPPORTED_PROTOCOLS = new Set(["http:", "https:", "ftp:", "s3:"]);

export type RemoteFileUrlValidation =
  | { ok: true; url: URL; filename: string }
  | { ok: false; error: string };

/**
 * Rewrite a cloud share link (Google Drive, Dropbox) into a **direct-download**
 * URL that Galaxy's server-side fetcher can pull — including large files, which
 * browser upload chokes on. The file must be shared "anyone with the link"; a
 * private file returns an HTML login page, which the import then surfaces as a
 * failed fetch rather than silently importing HTML.
 */
export function normalizeCloudShareUrl(url: URL): URL {
  const host = url.hostname.toLowerCase();
  if (host === "drive.google.com" || host === "drive.usercontent.google.com" || host === "docs.google.com") {
    // Accept /file/d/<id>/..., /d/<id>, open?id=<id>, uc?id=<id>, download?id=<id>
    let id = url.searchParams.get("id") || "";
    const m = url.pathname.match(/\/(?:file\/)?d\/([A-Za-z0-9_-]{10,})/);
    if (m) id = m[1];
    if (id) {
      // usercontent download endpoint + confirm=t bypasses the large-file virus-scan interstitial.
      return new URL(`https://drive.usercontent.google.com/download?id=${encodeURIComponent(id)}&export=download&confirm=t`);
    }
  }
  if (host === "www.dropbox.com" || host === "dropbox.com" || host === "dl.dropboxusercontent.com") {
    const u = new URL(url.toString());
    u.searchParams.set("dl", "1"); // dl=1 forces a direct download
    return u;
  }
  return url;
}

export function validateRemoteFileUrl(value: unknown): RemoteFileUrlValidation {
  if (typeof value !== "string" || !value.trim()) {
    return { ok: false, error: "URL is required" };
  }

  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return { ok: false, error: "Invalid URL format" };
  }

  // Cloud share links (Drive/Dropbox) → direct-download URL before the checks below.
  url = normalizeCloudShareUrl(url);

  if (!SUPPORTED_PROTOCOLS.has(url.protocol)) {
    return { ok: false, error: "Unsupported protocol. Use HTTP, HTTPS, FTP, or S3 URLs." };
  }
  // Credentials in a URL would otherwise be written to application/Galaxy
  // logs and session dataset metadata. Provider credentials need a dedicated,
  // encrypted connection flow instead.
  if (url.username || url.password) {
    return { ok: false, error: "URLs containing credentials are not supported. Use a public URL or configure a managed storage connection." };
  }
  // `s3://bucket/prefix/` is a directory-like prefix, not an object.  The
  // supported folder operation is browse_data / the S3 workspace browser.
  if (url.protocol === "s3:" && (!url.pathname || url.pathname.endsWith("/"))) {
    return { ok: false, error: "An S3 folder cannot be imported as one file. Browse the S3 workspace and select files, or provide an S3 object URI." };
  }

  const filename = url.pathname.split("/").filter(Boolean).pop() || "remote-file";
  return { ok: true, url, filename };
}
