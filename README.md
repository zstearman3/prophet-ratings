# 🏀 Prophet Ratings

**Prophet Ratings** is a college basketball analytics engine focused on predicting game outcomes using adjusted team statistics and probabilistic modeling. It combines numerical optimization, expanded stat adjustment, and simulation to generate predictions and insights — and will soon support natural language queries via GPT.

---

## 🎯 Purpose

Use team-season-level performance data to:

- Predict game scores using adjusted offensive/defensive ratings and pace
- Simulate outcomes with Gaussian distributions to represent volatility
- Enable questions like _"Who is most likely to pull an upset today?"_
- Surface matchup-specific advantages using adjusted **Five Factors** (eFG%, TO%, ORB%, FT Rate, 3PT%)

---

## 🧠 How It Works

### Models
- `TeamSeason`: Holds season-level stats and rating snapshots per team
- `TeamGame`: Stores box score-level stats per team per game
- `Game`: Connects home/away TeamGames and metadata
- `RatingSnapshot`: Tracks daily ratings with a config hash for validation

### Core Services
- `ProphetRatings::OverallRatingsCalculator`: Iteratively computes adjusted offensive/defensive efficiency and pace
- `ProphetRatings::LeastSquaresAdjustedStatCalculator`: Uses ridge regression to calculate adjusted values for metrics like eFG% and ORB%
- `ProphetRatings::GamePredictor`: Simulates outcomes based on adjusted stats, standard deviation, and home court advantage
- Python script (`adjusted_stat_solver.py`) invoked from Rails to solve the least squares system

### Simulation Logic
- Performance is modeled as a **normal distribution** centered on adjusted ratings
- Simulations include:
  - Team-specific volatility (off/def stddev)
  - Static or configurable home court advantage
  - Analytical win probability via Gaussian difference (in progress)

---

## ✅ Key Completed Features

- Adjusted efficiency ratings and pace via matrix solve
- Expanded adjusted stat support (eFG%, ORB%, etc.)
- Daily snapshots with configuration hash tracking
- Probabilistic game predictions with volatility modeling
- Model evaluation and diagnostic tools
- Initial AWS ECS deployment (via Terraform)
- Admin UI and seedable data pipeline

---

## 🚧 Roadmap Highlights (2025)

> Full roadmap in `project.md`

- Integrate Vegas odds and conferences
- Add adjusted play style and betting value indicators
- Build GPT-based interface for conversational queries
- Develop March Madness tools and mobile-friendly UI
- Begin content publishing via blog

Soft launch planned for early 2026 with a wider release before March Madness.

---

## 🧪 Future Ideas

- Auto-tune model parameters based on prediction residuals
- Use time-series filtering (e.g., “since January 1”) in GPT queries
- Visualize team trajectories and matchup graphs
- Power betting recommendations with value indicators
- Ingest play-by-play for enhanced game-level modeling

---

## 📝 Notes

- All ratings are **per 100 possessions**
- League-wide averages stored on the `Season` model
- Home court advantage currently static but configurable
- Regularization uses ridge regression (λ = 0.001)
- Adjusted stats are not used directly in predictions but will power the GPT query engine

---

## ⚖️ Licensing & Commercial Use

This project is open source under the MIT License for educational and non-commercial use.

If you are interested in using Prophet Ratings or any of its model output in a commercial product or paid service, please reach out for licensing options. All predictions and derived analytics remain © Prophet Ratings.

---

> Built with 💻 Ruby on Rails, Python, Tailwind, and caffeine.