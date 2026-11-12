import { useEffect, useState } from "react";

interface LicenseStatus {
  valid: boolean;
  status: string;
  tier: string;
  expires: string | null;
  message: string;
}

interface Props {
  children: React.ReactNode;
}

export function OnPremLicenseGate({ children }: Props) {
  const [license, setLicense] = useState<LicenseStatus | null>(null);
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    fetch("/api/license/status")
      .then((r) => r.json())
      .then((data: LicenseStatus) => { setLicense(data); setChecking(false); })
      .catch(() => {
        // Network error — don't block
        setLicense({ valid: true, status: "unknown", tier: "unknown", expires: null, message: "" });
        setChecking(false);
      });
  }, []);

  // Disabled in SaaS mode (no BIOMATE_ONPREM env var)
  // Only block on definitive invalid states, not network errors
  const blocked =
    !checking &&
    license !== null &&
    !license.valid &&
    license.status !== "unknown" &&
    license.status !== "backend_error";

  if (checking) return null;
  if (!blocked) return <>{children}</>;

  const isExpired = license?.status === "expired";

  return (
    <div style={{
      minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center",
      background: "#f8f9fa", fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    }}>
      <div style={{
        maxWidth: 480, width: "90%", background: "#fff", borderRadius: 12,
        padding: "40px 36px", boxShadow: "0 4px 24px rgba(0,0,0,0.08)", textAlign: "center",
      }}>
        <div style={{ marginBottom: 20 }}>
          <div style={{
            width: 60, height: 60, borderRadius: "50%",
            background: isExpired ? "#fff3cd" : "#fee2e2",
            display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 16px",
            fontSize: 'var(--fs-3xl)',
          }}>
            {isExpired ? "⏰" : "🔑"}
          </div>
          <h1 style={{ fontSize: 'var(--fs-xl)', fontWeight: 700, color: "#1a1a2e", margin: "0 0 4px" }}>
            BioMate AI · 本地部署版
          </h1>
          <h2 style={{ fontSize: 'var(--fs-lg)', fontWeight: 600, color: isExpired ? "#92400e" : "#991b1b", margin: "0 0 10px" }}>
            {isExpired ? "许可证已过期" : "许可证无效"}
          </h2>
          <p style={{ fontSize: 'var(--fs-base)', color: "#6b7280", margin: 0, lineHeight: 1.6 }}>
            {license?.message}
          </p>
        </div>

        <div style={{
          background: "#f9fafb", borderRadius: 8, padding: "16px 20px",
          textAlign: "left", margin: "24px 0",
        }}>
          <p style={{ fontSize: 'var(--fs-base)', fontWeight: 600, color: "#374151", margin: "0 0 10px" }}>
            激活步骤
          </p>
          <ol style={{ fontSize: 'var(--fs-base)', color: "#4b5563", margin: 0, paddingLeft: 18, lineHeight: 2.2 }}>
            <li>
              联系 BioMate 团队获取许可证密钥：
              <a href="mailto:support@biomate.ai" style={{ color: "#4f46e5", marginLeft: 4 }}>
                support@biomate.ai
              </a>
            </li>
            <li>
              在服务器 <code style={{ background: "#e5e7eb", padding: "1px 6px", borderRadius: 4 }}>.env</code> 中设置：
              <code style={{
                display: "block", background: "#1f2937", color: "#d1fae5",
                padding: "6px 12px", borderRadius: 6, marginTop: 4, fontSize: 'var(--fs-sm)', fontFamily: "monospace",
              }}>
                BIOMATE_LICENSE_KEY=BMOP-XXXX-XXXX-XXXX-XXXX
              </code>
            </li>
            <li>
              重启后端：{" "}
              <code style={{ background: "#e5e7eb", padding: "1px 6px", borderRadius: 4 }}>
                docker restart biomate-galaxy
              </code>
            </li>
          </ol>
        </div>

        <button
          onClick={() => window.location.reload()}
          style={{
            background: "#4f46e5", color: "#fff", border: "none", borderRadius: 8,
            padding: "10px 0", fontSize: 'var(--fs-base)', fontWeight: 500, cursor: "pointer", width: "100%",
          }}
        >
          重新检查许可证
        </button>
      </div>
    </div>
  );
}
