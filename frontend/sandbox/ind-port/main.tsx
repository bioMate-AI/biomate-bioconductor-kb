import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { IndReportPage } from "./pages/IndReportPage";

const root = document.getElementById("root");
if (!root) throw new Error("#root element missing in index.html");

createRoot(root).render(
  <StrictMode>
    <IndReportPage />
  </StrictMode>,
);
