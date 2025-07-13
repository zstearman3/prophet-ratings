import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["expandableRow"];

  connect() {}

  toggle(event) {
    const row = event.currentTarget;
    const detailRow = row.nextElementSibling;
    if (detailRow && detailRow.classList.contains("expandable-row")) {
      detailRow.classList.toggle("hidden");
    }
  }
}
