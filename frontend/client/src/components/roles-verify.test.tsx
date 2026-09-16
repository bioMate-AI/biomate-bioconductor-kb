/**
 * RTL tests for <RolesCard> + <VerifyPattern>. Uses the ported ROLES and
 * VERIFY_KINDS fixtures.
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { RolesCard, VerifyPattern } from "./roles-verify"
import { ROLES_DATA, VERIFY_KINDS } from "./gaps-fixtures"

describe("<RolesCard>", () => {
  it("renders the user role, project, and every capability row", () => {
    render(<RolesCard data={ROLES_DATA} />)
    expect(screen.getByTestId("roles-you")).toHaveTextContent("Owner")
    expect(screen.getByText("Fibrosis target triage")).toBeInTheDocument()
    for (const c of ROLES_DATA.caps) {
      expect(screen.getByTestId(`role-cap-${c.capability}`)).toBeInTheDocument()
    }
  })

  it("shows 'you can' / 'you cannot' verdicts and names the required role (never hidden)", () => {
    render(<RolesCard data={ROLES_DATA} />)
    // An allowed capability.
    expect(screen.getByTestId("role-verdict-Register a model")).toHaveTextContent("you can")
    // A disallowed capability is shown, not hidden, with its required role.
    const denied = screen.getByTestId("role-cap-Approve a spend above £500")
    expect(denied).toBeInTheDocument()
    expect(denied).toHaveTextContent("needs Billing owner")
    expect(screen.getByTestId("role-verdict-Approve a spend above £500")).toHaveTextContent(
      "you cannot",
    )
  })

  it("a viewer sees an owner-only control disabled, naming the required role (not hidden)", () => {
    // Minimal viewer-scoped RolesData: the owner-only capability is present,
    // shown as "you cannot", and names the role it needs — disabled-not-hidden.
    render(
      <RolesCard
        data={{
          you: "Viewer",
          project: "Fibrosis target triage",
          caps: [
            { capability: "Read & download files", needs: "Viewer", allowed: true },
            { capability: "Run analyses & edit project content", needs: "Editor", allowed: false },
            { capability: "Manage members & roles", needs: "Owner", allowed: false },
          ],
        }}
      />,
    )
    expect(screen.getByTestId("roles-you")).toHaveTextContent("Viewer")
    // Owner-only control is rendered (not hidden) and names its required role.
    const manage = screen.getByTestId("role-cap-Manage members & roles")
    expect(manage).toBeInTheDocument()
    expect(manage).toHaveTextContent("needs Owner")
    expect(screen.getByTestId("role-verdict-Manage members & roles")).toHaveTextContent(
      "you cannot",
    )
    // The one capability a viewer DOES have shows "you can".
    expect(screen.getByTestId("role-verdict-Read & download files")).toHaveTextContent("you can")
  })
})

describe("<VerifyPattern>", () => {
  it("renders every gate kind as measured·by / stops / where", () => {
    render(<VerifyPattern kinds={VERIFY_KINDS} />)
    for (const k of VERIFY_KINDS) {
      expect(screen.getByTestId(`verify-kind-${k.kind}`)).toBeInTheDocument()
    }
    // Human approval is expressed as just another gate kind.
    const human = screen.getByTestId("verify-kind-Human approval")
    expect(human).toHaveTextContent("measured by a person")
    expect(human).toHaveTextContent("pauses until answered")
    expect(human).toHaveTextContent("Spec 07")
  })

  it("shows the explain link only when onExplain is provided", async () => {
    const user = userEvent.setup()
    const onExplain = vi.fn()
    const { rerender } = render(<VerifyPattern kinds={VERIFY_KINDS} />)
    expect(screen.queryByTestId("verify-explain")).not.toBeInTheDocument()
    rerender(<VerifyPattern kinds={VERIFY_KINDS} onExplain={onExplain} />)
    await user.click(screen.getByTestId("verify-explain"))
    expect(onExplain).toHaveBeenCalledTimes(1)
  })
})
