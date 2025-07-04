import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["row"];

  connect() {
    this.currentSort = { column: null, direction: "desc" };
  }

  sort(event) {
    const column = event.currentTarget.dataset.column;
    let direction = "desc";
    if (this.currentSort.column === column && this.currentSort.direction === "desc") {
      direction = "asc";
    }
    this.currentSort = { column, direction };
    this.sortRows(column, direction);
  }

  sortRows(column, direction) {
    const rows = Array.from(this.rowTargets);
    const getEV = (row) => {
      const evCell = row.querySelector(`[data-ev-for='${column}']`);
      return evCell ? parseFloat(evCell.dataset.ev) : -Infinity;
    };
    rows.sort((a, b) => {
      const evA = getEV(a);
      const evB = getEV(b);
      return direction === "asc" ? evA - evB : evB - evA;
    });
    const tbody = this.element.querySelector("tbody");
    rows.forEach((row) => {
      const expanded = row.nextElementSibling.classList.contains("expandable-row") ? row.nextElementSibling : null;
      tbody.appendChild(row);
      if (expanded) tbody.appendChild(expanded);
    });
  }
}
