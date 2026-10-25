import { Controller } from "@hotwired/stimulus"

// Only active preseason review screens poll, with a bounded lifetime and no full report fetches.
export default class extends Controller {
  static values = { url: String, status: String }

  connect() {
    this.deadline = Date.now() + 10 * 60 * 1000
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
  }

  schedule() {
    if (Date.now() < this.deadline) this.timer = setTimeout(() => this.check(), 5000)
  }

  async check() {
    if (document.hidden) return this.schedule()
    this.request = new AbortController()
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, signal: this.request.signal })
      if (!response.ok) return
      const progress = await response.json()
      if (progress.status !== this.statusValue) return window.location.reload()
    } catch (error) {
      if (error.name === "AbortError") return
    }
    this.schedule()
  }
}
