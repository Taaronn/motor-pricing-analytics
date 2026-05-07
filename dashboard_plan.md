# Dashboard Plan — MTPL Pricing Intelligence

**Tool:** Looker Studio (free, shareable via URL)
**Data source:** CSVs in `data/exports/` — import once, refresh by re-uploading after a pipeline run
**Audience:** Pricing actuary reviewing rate adequacy by segment

---

## Chart 1 — KPI Scorecard (header row)

**Business question:** At a glance, is the portfolio's 2019 loss experience within a range that suggests the current rate level is adequate, and where is the highest concentration of risk?

**Type:** Scorecard tiles (4 cards)
**Source:** `mart_burning_cost_by_age.csv` filtered to `accident_year = 2019`

| Metric | Calculation | Purpose |
|---|---|---|
| Portfolio BC (€/py) | SUM(total_capped_losses) / SUM(earned_exposure) | Top-line rate adequacy indicator |
| Total earned exposure (py) | SUM(earned_exposure) | Volume sanity check |
| Highest-risk age band | MAX(burning_cost_capped) → display age_band label | Where to focus rate action |
| BC relativity spread | MAX(relativity) – MIN(relativity) | Width of the age pricing curve |

**Looker Studio config:**
- Add 4 Scorecard charts, each sourced from the age mart
- Filter each to `accident_year = 2019`
- Format BC values as currency (€, 0 decimal places)
- Arrange in a single horizontal row at the top of the report page

**Standalone read:** A stranger sees four numbers: the average loss cost per policy, the size of the book in policy-years, which age group is most expensive, and how wide the pricing curve is. Without reading anything else they know whether this is a large or small book, the rough level of loss, and that pricing is not flat across ages. No actuarial vocabulary required.

---

## Chart 2 — Burning Cost by Driver Age (bar chart)

**Business question:** Is the youth surcharge applied to drivers aged 18-24 justified by their observed loss costs, and are any age bands trending in a direction that warrants a rate change before the next renewal cycle?

**Type:** Vertical bar chart
**Source:** `mart_burning_cost_by_age.csv`
**X-axis:** `age_band` (sorted ascending — Looker Studio: sort by age_band A→Z)
**Y-axis:** `burning_cost_capped`
**Breakdown dimension:** `accident_year` (grouped bars, 3 colours)
**Filter:** None — show all 3 years for comparison

**What to look for:**
- 18-24 band should show the highest BC (~3× portfolio average) — confirms the youth surcharge is actuarially justified
- The 65+ band typically shows a secondary uptick (fatigue/reaction-time effect)
- YoY movement within each band: flat bars = stable book; diverging bars = emerging trend

**Looker Studio config:**
- Dimension: `age_band`
- Metric: `burning_cost_capped`
- Breakdown dimension: `accident_year`
- Sort: `age_band` ascending
- Style → Bar chart → Grouped (not stacked)
- Add data labels (value) on each bar
- Title: "Burning Cost by Driver Age Band (€/policy-year)"

**Standalone read:** A stranger sees bars grouped by age band. The tallest bars on the left (young drivers) immediately explain why young drivers pay higher premiums — their observed losses are higher, not an arbitrary commercial decision. If bars within an age band differ noticeably by year, loss experience is changing and a rate review may be warranted. No actuarial knowledge needed to read the direction of the age effect.

---

## Chart 3 — Burning Cost by Bonus-Malus Band (bar chart)

**Business question:** Does the French CRM system correctly identify and price the highest-risk drivers? Is the BM 101+ surcharge proportional to actual observed loss experience, or is it over- or under-loaded?

**Type:** Horizontal bar chart
**Source:** `mart_burning_cost_by_bonus_malus.csv`
**Y-axis:** `bm_band` (sorted ascending)
**X-axis:** `burning_cost_capped`
**Breakdown dimension:** `accident_year`
**Filter:** None

**What to look for:**
- BM 101+ (loaded drivers) should be the worst band — confirms the CRM surcharge is proportional to actual loss
- BM floor (50) should be the lowest — long-standing claim-free drivers are the most profitable segment
- Relativity spread: the ratio of BM 101+ BC to BM=50 BC quantifies the CRM pricing leverage

**Looker Studio config:**
- Same grouped bar setup as Chart 2 but horizontal orientation
- Dimension: `bm_band`, Metric: `burning_cost_capped`, Breakdown: `accident_year`
- Sort: `bm_band` ascending
- Title: "Burning Cost by Bonus-Malus Band (€/policy-year)"

**Standalone read:** A stranger sees bars for each BM band. The longest bars (BM 101+) confirm that the drivers who have been penalised by the CRM system genuinely cost more — the system is working as intended. The shortest bars (BM=50) represent long-standing claim-free customers who are the book's most profitable segment. The gap between the two extremes is the headline pricing leverage the CRM system provides.

---

## Chart 4 — Age × Accident Year Trend (grouped bar, with caveat)

**Business question:** Is there a genuine year-over-year trend in loss costs by age segment that would warrant a rate change? *(With this dataset: demonstrates the query structure; synthetic accident years mean movements are noise, not signal — see caveat below.)*

**Type:** Grouped bar chart
**Source:** `mart_age_x_vehage_heatmap.csv` aggregated to age_band level
**X-axis:** `age_band`
**Y-axis:** `burning_cost_capped` (computed field: `total_capped_losses / earned_exposure`)
**Breakdown:** `accident_year`

**Synthetic data caveat (include as chart subtitle or annotation):**
> "accident_year is a synthetic dimension (HASH(IDpol) % 100 assignment). Year-over-year movements
> reflect random variation in the hash split, not genuine loss trends. This chart demonstrates
> the query structure; replace with real accident-year data for pricing decisions."

**What to look for (with real data):**
- Bars rising year-on-year within a segment → loss inflation or deteriorating risk quality → rate increase candidate
- Bars falling → improving segment → competitive opportunity to reduce premium
- Divergence between segments → the rate change needed is segment-specific, not a portfolio-wide flat adjustment

**Looker Studio config:**
- Create a calculated field: `BC = SUM(total_capped_losses) / SUM(earned_exposure)`
- Dimension: `age_band`, Breakdown: `accident_year`
- Add the caveat as a Text box below the chart title
- Title: "Burning Cost Trend by Age Band and Accident Year"

**Standalone read:** A stranger sees bars for each age band split by colour per year. If bars within a band are similar heights, loss experience is stable. If they diverge, something changed year-on-year. The synthetic data caveat (visible as an on-chart annotation) tells them not to act on these specific numbers — the chart's purpose is to demonstrate the analytical pattern. With real accident-year data, this view would be a primary input to the annual rate review.

---

## Chart 5 — Age × Vehicle Age Heatmap

**Business question:** Does vehicle age interact with driver age to create risk concentrations that a one-dimensional age rate table would miss? Which specific (age × vehicle age) cells warrant a two-way interaction loading factor?

**Type:** Pivot table with conditional formatting (heatmap substitute in Looker Studio)
**Source:** `mart_age_x_vehage_heatmap.csv`
**Filter:** `accident_year = 2019` (single-year rate basis — cleanest view for underwriting)
**Rows:** `age_band`
**Columns:** `veh_age_band`
**Values:** `burning_cost_capped`

**Why a pivot table:**
Looker Studio has no native heatmap chart. A pivot table with conditional formatting (low=green, high=red colour scale) replicates the heatmap view. It is the actuarial standard format for two-way interaction analysis.

**What to look for:**
- The 18-24 × 0-1yr cell: young driver + new vehicle = maximum exposure (new-driver risk + high repair costs)
- Cells where BC exceeds 150% of the age-band row average → candidates for vehicle-age interaction factor (see showcase query 4)
- Diagonal pattern: vehicle age and driver age often correlate (older drivers keep cars longer), so the interaction may be partially mechanical

**Looker Studio config:**
- Insert → Pivot table
- Row dimension: `age_band`, Column dimension: `veh_age_band`
- Metric: `burning_cost_capped`
- Sort rows/columns: ascending
- Style → Conditional formatting → colour scale (white → red, min=0, max=auto)
- Filter: `accident_year = 2019`
- Title: "Burning Cost Heatmap — Age × Vehicle Age (2019, €/policy-year)"

**Standalone read:** A stranger sees a grid where darker red means higher loss cost. They can immediately identify the highest-risk combinations — young driver with a nearly-new vehicle in the top-left corner — without knowing anything about actuarial pricing. The colour gradient communicates the interaction effect at a glance; the numbers in each cell provide precision for anyone who wants to quantify it. A flat age-only rate table treats each row uniformly — this chart shows where that assumption breaks down.

---

## Build order

1. Upload all three CSVs to Looker Studio as separate data sources
2. Create a new report, set theme to minimal/white
3. Add Charts 1–5 in order (scorecard first anchors the page layout)
4. Add a text box at the top: report title, data vintage (2019 rate basis), link to GitHub repo
5. Share → "Anyone with the link can view" → copy URL into `README.md`

---

## Files referenced

| File | Mart | Rows |
|---|---|---|
| `data/exports/mart_burning_cost_by_age.csv` | `mart_burning_cost_by_age` | 21 |
| `data/exports/mart_burning_cost_by_bonus_malus.csv` | `mart_burning_cost_by_bonus_malus` | 12 |
| `data/exports/mart_age_x_vehage_heatmap.csv` | `mart_age_x_vehage_heatmap` | 105 |