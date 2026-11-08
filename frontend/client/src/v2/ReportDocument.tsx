import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { tOr } from "@/lib/i18n";
import "./ReportDocument.css";

/** Read-only report prose. The containing workflow panel owns vertical scrolling. */
export function ReportDocument({ markdown }: { markdown: string }) {
  return (
    <article className="bmx-report-doc" data-testid="after-report-doc">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          table: ({ children }) => (
            <div className="bmx-report-table" role="region" tabIndex={0}
              aria-label={tOr("afterrun.report_table", "Report table")}>
              <table>{children}</table>
            </div>
          ),
        }}
      >
        {markdown}
      </ReactMarkdown>
    </article>
  );
}
