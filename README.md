**Toronto Airbnb Market Intelligence**

A market-intelligence analysis of Toronto's short-term rental market, built to support a (simulated) property-management startup evaluating entry into the city. The project takes ~15,700 Airbnb listings from raw data through cleaning, profiling, and analysis in Google BigQuery (SQL), and delivers the findings as an interactive Tableau Public dashboard.

🔗 **Live dashboard**

    https://public.tableau.com/app/profile/shubham.gandhi2524/viz/TorontoAirbnbMarketIntelligenceReport/Dashboard1?publish=yes

**The Brief**

A data analyst at a property-management startup is asked to produce a market intelligence report before leadership commits resources to Toronto's short-term rental (STR) market. 

Four business questions drive the analysis:

1. Supply concentration — Which neighbourhoods and room types dominate?
2. Demand signals — Where is demand strongest?
3. Competitive landscape — Professional operators vs. casual hosts.
4. Regulatory compliance — How does licensing vary across the city?


**Methodology**

Proxy Metrics: The dataset (listings_raw.csv) intentionally contains no price column. 
Rather than treat this as a limitation, the project uses it as an opportunity to work with proxy metrics, a more transferable analytical skill than relying on an obvious target variable:

- Demand proxy — review activity. Airbnb guests review a consistent share of completed stays, so review velocity (reviews_per_month, number_of_reviews) approximates booking activity.
- Supply/occupancy proxy — availability. availability_365 indicates how open a listing's calendar is.

Where a proxy is ambiguous (e.g. low availability can mean booked up OR host-blocked), the analysis flags it rather than overclaiming.

**Tools & Stack**

1. Data cleaning, profiling, analysis - Google BigQuery (Standard SQL)
2. Visualization & dashboard          - Tableau Public Desktop Editio
3. Data source                        - Toronto open Airbnb listings (15,776 rows, 19 fields)

**Repository Contents**

1. FileDescription : toronto_airbnb_analysis.sqlFully commented BigQuery script: cleaning, profiling, and all four analytical questions, with the key insight noted for each query.
2. listing_raw.csv : Raw CSV file
3. listing_clean.csv : clean CSV file

**Analytical Process**

1. Data Cleaning -
Removed rows with non-numeric IDs or null neighbourhoods using SAFE_CAST and null checks. Only **72 of 15,776 raw rows (0.2%)** were dropped — confirming a clean dataset.

2. Data Profiling - 
Before analyzing, profiled the data to confirm each business question had real signal:
 - **15,704 listings across 10,398 hosts** (~1.5 listings/host) — multi-listing operators exist.
 - **140 unique neighbourhoods** (matches the data dictionary).
 - **3,220 listings (~20.5%) never reviewed** — excluded from demand analysis.
 - **~56.6% licensed** — a meaningful ~43% compliance gap.

3. Analysis
Answered all four questions with grouped, windowed, and conditional-aggregation queries. (See the SQL file for the full, commented logic.)

**Key Findings**

**Q1 — Supply is extremely concentrated**
   - **Waterfront Communities–The Island holds 16.9% of all listings (2,653)** — more than the next four neighbourhoods combined. The market is 67% entire homes, the segment a professional manager actually competes in. Kensington-Chinatown is the lone top neighbourhood that leans toward private rooms, hinting at a more residential character.
     
**Q2 — "Strongest demand" depends on the lens**
   - Ranking by average review rate flatters tiny suburbs (Elms-Old Rexdale tops the list with only 10 listings). By total volume, the Waterfront dominates with ~111,000 reviews — roughly 8× any other neighbourhood. The dashboard plots both intensity and volume together rather than trusting a single misleading ranking.
     
**Q3 — Casual and professional hosts run opposite models**
   - Casual hosts earn **nearly double the review rate per listing** (avg 1.83 vs 1.11), while professionals keep more units open longer (avg 223 vs 209 days/yr). Casual hosts capture sharp occasional demand; professionals spread thinner demand across a larger portfolio. (Caveat: review rate measures booking frequency, not revenue.)
     
**Q4 — Non-compliance is structural, not local**
   - **~43% of listings are unlicensed**, and the rate is remarkably even citywide (most neighbourhoods sit at 40–45% unlicensed) rather than concentrated in a few areas. Laggards: York University Heights (35%) and Kensington-Chinatown (40.5%).

**The Dashboard**

The Tableau Public dashboard presents all four questions in a single interactive view:

**Supply Map** — Top 15 neighbourhoods by listing count, stacked by room type.

**Demand vs Supply** — Scatter of supply volume vs. demand intensity, with quadrant reference lines (opportunity / competitive / saturated).

**Host Type** — Treemap of casual vs. professional operators.

**Compliance** — Highlight table of licensing rates by neighbourhood, on a red-to-green scale.

A **Room Type filter** applies across all four views for interactive exploration.

**What This Project Demonstrates**

- End-to-end workflow: raw data → SQL cleaning/profiling/analysis → BI dashboard.
- Working with proxy metrics where an obvious target variable is absent.
- Translating raw statistics into business-relevant insight (e.g. connecting a 28-night median minimum stay to Toronto's STR regulatory threshold).
- Reading past a default sort order to avoid misleading conclusions (Q2).
- Honest treatment of data limitations and caveats throughout.
