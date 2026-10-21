import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "popover"]

  position(event) {
    const popover = this.popoverTarget
    if (event.newState === "closed") return
    if (event.type !== "beforetoggle" && !popover.matches(":popover-open")) return

    const anchor = this.triggerTarget.getBoundingClientRect()
    const bounds = popover.getBoundingClientRect()
    const gap = 8
    const width = bounds.width || Math.min(224, window.innerWidth - gap * 2)
    const left = Math.max(gap, Math.min(anchor.left, window.innerWidth - width - gap))
    const below = anchor.bottom + gap
    const top = below + bounds.height <= window.innerHeight - gap
      ? below
      : Math.max(gap, anchor.top - bounds.height - gap)

    popover.style.left = `${left}px`
    popover.style.top = `${top}px`
  }
}
