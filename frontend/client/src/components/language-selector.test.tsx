import { fireEvent, render, screen } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import { LanguageSelector } from "./language-selector";
import { setLanguagePreference } from "@/lib/i18n";
vi.mock("@/lib/i18n", () => ({ locale: "en", setLanguagePreference: vi.fn() }));
describe("explicit UI language switch", () => {
  it("offers both languages in their own names and persists the chosen language", () => {
    render(<LanguageSelector />);
    const control = screen.getByRole("combobox", { name: "Language / 语言" });
    expect(control).toHaveValue("english");
    expect(screen.getByRole("option", { name: "简体中文" })).toBeInTheDocument();
    fireEvent.change(control, { target: { value: "chinese" } });
    expect(setLanguagePreference).toHaveBeenCalledWith("chinese");
    fireEvent.change(control, { target: { value: "english" } });
    expect(setLanguagePreference).toHaveBeenCalledWith("english");
  });
});
