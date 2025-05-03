// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import Chartkick from "chartkick"
import Chart from "chart.js/auto"
import "chartjs-adapter-date-fns"

Chartkick.use(Chart)

