import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["toggle"];

  toggle(event) {
    if (event.target.closest("a")) return;

    const row = event.currentTarget;
    const detailRow = row.nextElementSibling;
    if (detailRow && detailRow.classList.contains("expandable-row")) {
      const hidden = detailRow.classList.toggle("hidden");
      this.toggleTarget.setAttribute("aria-expanded", String(!hidden));
    }
  }
}
