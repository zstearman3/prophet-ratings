import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { state: Boolean }
  static targets = ["menu", "button", "x", "bars"]

  connect() {
    this.stateValue = false
    this.render()
    this.menuLinkWasFocused = false
    document.addEventListener("focusin", this.rememberFocus)
    this.breakpoint = window.matchMedia("(min-width: 768px)")
    this.breakpoint.addEventListener("change", this.handleBreakpointChange)
  }

  disconnect() {
    this.breakpoint?.removeEventListener("change", this.handleBreakpointChange)
    document.removeEventListener("focusin", this.rememberFocus)
  }

  toggle() {
    this.stateValue = !this.stateValue
    this.render()
  }

  blurAlreadyFocusedControl(event) {
    const control = event.target.closest?.("a, button")
    if (control === document.activeElement) control.blur()
  }

  close() {
    if (!this.stateValue || this.breakpoint.matches) return

    this.stateValue = false
    this.render()
    this.buttonTarget.focus()
  }

  rememberFocus = (event) => {
    if (event.target !== document.body) {
      this.menuLinkWasFocused = this.menuTarget.contains(event.target)
    }
  }

  handleBreakpointChange = (event) => {
    if (event.matches && document.activeElement === this.buttonTarget) {
      this.buttonTarget.blur()
    } else if (!event.matches && !this.stateValue && (this.menuTarget.contains(document.activeElement) || this.menuLinkWasFocused)) {
      this.buttonTarget.focus()
    }
  }

  render() {
    this.menuTarget.classList.toggle("hidden", !this.stateValue)
    this.buttonTarget.setAttribute("aria-expanded", String(this.stateValue))
    this.buttonTarget.setAttribute("aria-label", this.stateValue ? "Collapse menu" : "Expand menu")
    this.xTarget.classList.toggle("hidden", !this.stateValue)
    this.barsTarget.classList.toggle("hidden", this.stateValue)
  }
}
