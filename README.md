# Prophet Ratings

A college basketball analytics engine focused on predicting game outcomes using adjusted team statistics and probabilistic modeling.

## 🎯 Purpose
Use team-season-level performance data to:
- Predict game scores based on offensive/defensive ratings and pace
- Simulate possible outcomes with Gaussian distributions
- Eventually support natural-language queries like "Who is most likely to pull an upset today?"

## 📦 Current Architecture
### Models:
- `TeamSeason`: Holds season-level ratings for each team
- `TeamGame`: Stores box score-level data per team per game
- `Game`: Connects home and away `TeamGame`s and metadata

### Services:
- `ProphetRatings::OverallRatingsCalculator`: Iteratively calculates adjusted offensive/defensive efficiency and pace
- `ProphetRatings::LeastSquaresAdjustedStatCalculator`: Uses ridge regression to calculate adjusted stats (e.g., eFG%)
- `ProphetRatings::GamePredictor`: Predicts scores using adjusted ratings + Gaussian distributions to simulate volatility

### Simulation:
- Performance on any given night is modeled as a normal distribution centered around adjusted ratings
- Simulated outcomes account for league-wide efficiency standard deviation and home court advantage (currently static at +1.8)

## ✅ Key Completed Features
- Matrix-based adjusted stat calculation using ridge regression
- Working adjusted eFG% for all teams from full season data (11k+ TeamGames)
- Probabilistic game simulation using Gaussian sampling
- Tests and factories built for TeamGames, adjusted stat calculator, and prediction logic

## 🔜 Next Up (Prioritized)
1. **Implement team-specific variance**
   - Capture residuals between actual and predicted performance per team
   - Use that to compute `offensive_efficiency_stddev`, `defensive_efficiency_stddev`, etc.
   - Use in `GamePredictor` instead of global season stddev

2. **Add win probability calculation**
   - Use analytical Gaussian difference to calculate win percentage
   - No need for simulation loop (but retain for later percentile analysis)

3. **Support more adjusted stats**
   - Turnover rate
   - Pace
   - Free throw rate
   - Home court advantage as a per-team stat

4. **Build a GPT interface**
   - Ask questions like "How has Team A improved since January?"
   - Requires support for stat-by-date (e.g., time-series snapshots or filtering by date range)

## 🧪 Long-Term Ideas
- Run predictions across full seasons and compare to real outcomes
- Track residuals over time to auto-tune model parameters
- Visualize game-level predictions and confidence intervals
- Power a daily betting model with value picks, upsets, and spreads

## 📎 Notes
- All ratings are per-100 possessions
- League averages (efficiency, pace) are stored on `Season`
- Home court advantage is currently a constant but will evolve
- Regularization is done via ridge regression (`λ = 0.001`) to ensure stable matrix inversion


