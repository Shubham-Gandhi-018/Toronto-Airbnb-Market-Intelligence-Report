/* ============================================================================
   TORONTO AIRBNB MARKET INTELLIGENCE — BigQuery Analysis
   ----------------------------------------------------------------------------
   Source table : airbnbtoronto-498715.Airbnb_Toronto.Listings3
   Records       : 15,704 listings (cleaned from 15,776 raw)
   Goal          : Market intelligence for a property-management startup
                   evaluating entry into Toronto's short-term rental market.
   ============================================================================ */


/* ============================================================================
   STEP 1 — DATA QUALITY CLEANUP
   ----------------------------------------------------------------------------
   Rebuilds the table keeping only rows with a valid numeric id and a non-null
   neighbourhood (the key grouping dimension for 3 of the 4 questions).
   SAFE_CAST returns NULL instead of erroring on bad values, so junk ids are
   dropped without crashing the query.

   INSIGHT: Only 32 of 15,736 raw rows dropped (~0.2%). Dataset is clean.
   ============================================================================ */
CREATE OR REPLACE TABLE `airbnbtoronto-498715.Airbnb_Toronto.Listings3` AS
SELECT *
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
WHERE SAFE_CAST(id AS INT64) IS NOT NULL
  AND neighbourhood IS NOT NULL;


/* ============================================================================
   STEP 2 — DATA PROFILING
   ----------------------------------------------------------------------------
   One-row summary of shape and quality before analysis. COUNTIF counts rows
   where the condition is true.

   INSIGHT:
     - 15,704 listings across 10,398 hosts (~1.5 listings/host) -> multi-listing
       operators exist, so the professional-vs-casual question has real signal.
     - 140 unique neighbourhoods (matches the data dictionary).
     - 3,220 listings (~20.5%) never reviewed; null_review_per_month and
       null_last_review match exactly (3,220) -> nulls trace to the same cause,
       no hidden data issue.
     - 8,894 licensed (~56.6%) -> a meaningful ~43% compliance gap.
   ============================================================================ */
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT neighbourhood) AS unique_neighbourhoods,
  COUNT(DISTINCT host_id) AS unique_hosts,
  COUNTIF(reviews_per_month IS NULL) AS null_review_per_month,
  COUNTIF(last_review IS NULL) AS null_last_review,
  COUNTIF(license IS NOT NULL AND license != '') AS licensed_count
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`;


/* ----------------------------------------------------------------------------
   STEP 2b — ROOM TYPE DISTRIBUTION (with % share)
   ----------------------------------------------------------------------------
   SUM(COUNT(*)) OVER() is a window function: it sums the per-group counts
   across all groups to get the grand total in a single pass (no subquery).
   * 100.0 forces float division so percentages keep decimals.

   INSIGHT: Entire home/apt = 10,532 (67.1%), Private room = 5,113 (32.6%).
   Together 99.7%. Toronto is overwhelmingly a whole-unit market — the segment
   a professional manager actually competes in.
   ---------------------------------------------------------------------------- */
SELECT
  room_type,
  COUNT(*) AS listing_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
GROUP BY room_type
ORDER BY listing_count DESC;


/* ----------------------------------------------------------------------------
   STEP 2c — MINIMUM NIGHTS DISTRIBUTION
   ----------------------------------------------------------------------------
   APPROX_QUANTILES(col, 2) splits the data in half and returns
   [min, median, max]; [OFFSET(1)] grabs the median (arrays are 0-indexed).

   INSIGHT: min=1, max=730 (a host effectively delisting), median=28, mean=20.6.
   The typical listing requires a 28-night minimum — hosts engineering around
   Toronto's 28-day short-term-rental threshold to reclassify as medium-term
   rental. Implication: 28-night listings naturally show low review velocity
   (one monthly booking vs many short stays) — a caveat for the demand proxy.
   ---------------------------------------------------------------------------- */
SELECT
  MIN(minimum_nights) AS min_val,
  MAX(minimum_nights) AS max_val,
  APPROX_QUANTILES(minimum_nights, 2)[OFFSET(1)] AS median_val,
  ROUND(AVG(minimum_nights), 1) AS avg_val
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`;


/* ----------------------------------------------------------------------------
   STEP 2d — MULTI-LISTING HOSTS (quick check)
   ----------------------------------------------------------------------------
   INSIGHT: 7,385 of 15,704 listings (47.0%) belong to hosts running more than
   one listing. NOTE: this is the share of LISTINGS from multi-listing hosts,
   not the share of HOSTS that are professional. A minority of operators
   controls a large chunk of supply.
   ---------------------------------------------------------------------------- */
SELECT
  COUNTIF(calculated_host_listings_count > 1) AS multi_listing_entries,
  COUNT(*) AS total,
  ROUND(COUNTIF(calculated_host_listings_count > 1) * 100.0 / COUNT(*), 1) AS pct
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`;


/* ============================================================================
   Q1 — SUPPLY CONCENTRATION: Top 15 neighbourhoods by listing count
   ----------------------------------------------------------------------------
   The subquery in the percentage divisor counts the full table (15,704) so each
   neighbourhood's share of the city can be computed.

   INSIGHT: Supply is extremely top-heavy. Waterfront Communities-The Island =
   2,653 listings (16.9%) — more than the next FOUR neighbourhoods combined.
   Steep drop to Niagara at 583 (3.7%). The market lives and dies by the
   downtown core.
   ============================================================================ */
SELECT
  neighbourhood,
  COUNT(*) AS listing_count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`), 1) AS pct_of_total
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
GROUP BY neighbourhood
ORDER BY listing_count DESC
LIMIT 15;


/* ----------------------------------------------------------------------------
   Q1b — Top 15 neighbourhoods BROKEN DOWN BY room type
   ----------------------------------------------------------------------------
   GROUP BY two columns -> one row per neighbourhood + room-type combination.
   The WHERE ... IN (...) subquery restricts to just the top 15 neighbourhoods.
   This is the source data for the Tableau stacked-bar Supply Map.

   INSIGHT: The dominant neighbourhoods are dominated specifically by ENTIRE
   HOMES (the investor/professional segment). Exception: Kensington-Chinatown
   leads with PRIVATE ROOMS (242) over entire homes (183) — the only top
   neighbourhood that flips, hinting at a more residential character.
   ---------------------------------------------------------------------------- */
SELECT
  neighbourhood,
  room_type,
  COUNT(*) AS listing_count
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
WHERE neighbourhood IN (
  SELECT neighbourhood
  FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
  GROUP BY neighbourhood
  ORDER BY COUNT(*) DESC
  LIMIT 15
)
GROUP BY neighbourhood, room_type
ORDER BY listing_count DESC;


/* ============================================================================
   Q2 — DEMAND SIGNALS: strongest demand by neighbourhood (reviews as proxy)
   ----------------------------------------------------------------------------
   COALESCE(x, 0) substitutes 0 when x is missing. WHERE number_of_reviews > 0
   keeps only reviewed listings (excludes the 3,220 "dark" listings). HAVING
   COUNT(*) >= 10 drops tiny neighbourhoods whose averages are unreliable.
   (Note: with the WHERE > 0 filter, the COALESCE(...,0) is harmless but
   redundant — the nulls are already excluded.)

   INSIGHT: Ranking by AVERAGE review rate flatters tiny suburbs (Elms-Old
   Rexdale tops at 4.94 with only 10 listings). The true demand center is
   Waterfront Communities: avg only 2.1 but 2,204 listings and 111,675 total
   reviews — ~8x any other neighbourhood. "Strongest demand" depends on whether
   you mean intensity-per-listing or total volume — which is exactly why the
   Tableau scatter plots both at once.
   ============================================================================ */
SELECT
  neighbourhood,
  COUNT(*) AS listing_count,
  ROUND(AVG(COALESCE(SAFE_CAST(reviews_per_month AS FLOAT64), 0)), 2) AS avg_rpm,
  APPROX_QUANTILES(COALESCE(SAFE_CAST(reviews_per_month AS FLOAT64), 0), 2)[OFFSET(1)] AS median_rpm,
  SUM(SAFE_CAST(number_of_reviews AS INT64)) AS total_reviews
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
WHERE SAFE_CAST(number_of_reviews AS INT64) > 0
GROUP BY neighbourhood
HAVING COUNT(*) >= 10
ORDER BY avg_rpm DESC
LIMIT 15;


/* ============================================================================
   Q3 — COMPETITIVE LANDSCAPE: professional operators vs casual hosts
   ----------------------------------------------------------------------------
   CASE labels each listing Professional (host runs >1 listing) or Casual.
   Same review/availability proxies and filters as Q2.

   INSIGHT (reviewed listings: 6,933 casual + 5,551 professional = 12,484,
   matching the profiling prediction):
     - Casual hosts get nearly double the review rate per listing
       (avg 1.83 vs 1.11; median 1.37 vs 0.42).
     - Professionals keep units open longer (avg 223 vs 209 days/yr).
   Opposite models: casual hosts capture sharp occasional demand; professionals
   spread thinner demand across a larger, more-open portfolio.
   CAVEAT: lower review rate != worse performance — professionals may target
   longer stays / higher rates; reviews measure booking frequency, not revenue.
   ============================================================================ */
SELECT
  CASE
    WHEN calculated_host_listings_count > 1 THEN 'Professional'
    ELSE 'Casual'
  END AS host_type,
  COUNT(*) AS listing_count,
  ROUND(AVG(COALESCE(SAFE_CAST(reviews_per_month AS FLOAT64), 0)), 2) AS avg_rpm,
  APPROX_QUANTILES(COALESCE(SAFE_CAST(reviews_per_month AS FLOAT64), 0), 2)[OFFSET(1)] AS median_rpm,
  SUM(SAFE_CAST(number_of_reviews AS INT64)) AS total_reviews,
  ROUND(AVG(availability_365)) AS avg_availability
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
WHERE SAFE_CAST(number_of_reviews AS INT64) > 0
GROUP BY host_type
HAVING COUNT(*) >= 10
ORDER BY avg_rpm DESC;


/* ============================================================================
   Q4 — REGULATORY COMPLIANCE: overall licensing rate
   ----------------------------------------------------------------------------
   CASE flags a listing licensed/unlicensed by whether license IS NULL.
   NOTE: this uses NULL-only logic; the profiling query also excluded empty
   strings. Both returned 8,894, which proves there are NO empty-string
   licenses — missing licenses are all true NULLs.

   INSIGHT: 8,894 licensed (56.6%) vs 6,810 unlicensed (43.4%). Nearly 4 in 10
   listings operate without a license — both a regulatory risk and a
   competitive opening for a compliant operator.
   ============================================================================ */
SELECT
  CASE WHEN license IS NULL THEN 'No' ELSE 'Yes' END AS licensed_flag,
  COUNT(*) AS number_of_listings,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`), 1) AS pct_of_total
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
GROUP BY licensed_flag
ORDER BY number_of_listings DESC;


/* ----------------------------------------------------------------------------
   Q4b — Licensing rate BY neighbourhood
   ----------------------------------------------------------------------------
   COUNT(CASE WHEN ... THEN id ELSE NULL END) counts conditionally, because
   COUNT ignores NULLs. * 1.0 forces float division for the percentage.
   NOTE: ORDER BY licensed DESC sorts by RAW COUNT, not rate — so the top of
   the list is just the biggest neighbourhoods. Sort by licensed_pct if the
   story is about compliance rates. Source for the Tableau compliance table.

   INSIGHT: Non-compliance is broad and even — most neighbourhoods sit at
   0.45-0.65 licensed, clustered around the 56.6% city average. It's a
   structural, citywide pattern, not a few rogue areas. Laggards:
   York University Heights (0.35) and Kensington-Chinatown (0.41, most
   unlicensed in absolute terms at 260). Most compliant: Greenwood-Coxwell,
   Woodbine Corridor, Wychwood (~0.70-0.71).
   ---------------------------------------------------------------------------- */
SELECT
  neighbourhood,
  COUNT(CASE WHEN license IS NULL THEN id ELSE NULL END) AS unlicensed,
  COUNT(CASE WHEN license IS NOT NULL THEN id ELSE NULL END) AS licensed,
  ROUND(COUNT(CASE WHEN license IS NOT NULL THEN id ELSE NULL END) * 1.0 / COUNT(*), 2) AS licensed_pct
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`
GROUP BY neighbourhood
ORDER BY licensed DESC;


/* ============================================================================
   EXPORT — single cleaned granular table for Tableau
   ----------------------------------------------------------------------------
   SELECT * EXCEPT(...) drops the two unused all-NULL columns. Connect Tableau
   to this single source (not the pre-aggregated extracts) so cross-sheet
   filters work and all calculated fields compute on row-level data.
   ============================================================================ */
SELECT * EXCEPT(neighbourhood_group, price)
FROM `airbnbtoronto-498715.Airbnb_Toronto.Listings3`;
