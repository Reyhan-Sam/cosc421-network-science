# RQ2 – Highway closures, emergency response and evacuation (Anita Nambuuza)

**Question:** During wildfire-related closures of Highways 97 and 97C around Peachland and West Kelowna, which alternative roads receive rerouted emergency-response routes, how do closures change modelled response times, and where do responders and evacuees compete for the same roads?

## How to run
1. In R: `install.packages(c("igraph", "dplyr", "readr", "ggplot2"))` (first time only).
2. Set the working directory to either the repo root or this `rq2/` folder, then source `rq2/q2_highway_closures.R`.
3. It reads the shared `nodes.csv`, `edges.csv` and `stations.csv` from the repo root and writes everything into `rq2/results/` and `rq2/figures/`. The shared files are never modified.

## Method in brief
- Shared undirected road network (2,545 nodes, 2,964 edges, average degree 2.33), weighted by modelled travel time from assumed speeds per road class (base, slow and fast sets).
- Seven scenarios: intact network; Hwy 97 through Peachland; Hwy 97 through West Kelowna; Hwy 97 across the whole window; Hwy 97C only; Drought Hill 2025 (Hwy 97 + 97C); McDougall Creek 2023 (Hwy 97 Westbank to the Bennett Bridge + Westside Rd north).
- Response: Dijkstra from a super-source joined to the 5 fire stations to the 1,687 destinations.
- Evacuation: Dijkstra from each destination to the nearest of 5 exits (E1 Hwy 97 east, E2 Hwy 97 south, E3 Hwy 97C west, E4 Westside Rd north, E5 Princeton Ave west).
- Route load = number of distinct shortest routes using each street, compared with standard edge betweenness.

## Outputs
| File | Contents |
| --- | --- |
| `results/rq2_summary.csv` | Response times by scenario and speed set (mean, median, max, cut off, >1 min, max increase) |
| `results/rq2_evacuation_summary.csv` | Evacuation times, destinations with no exit, >2 min increases, exits used |
| `results/rq2_reroute_<scenario>.csv` | Responder routes per street, before and after each closure |
| `results/rq2_shared_roads_<scenario>.csv` | Streets used by both evacuation and responder routes (conflict = product) |
| `results/rq2_eb_vs_reroute.csv` | Streets gaining the most routes vs. their edge betweenness rank |
| `figures/fig1_network.png` | Study network with stations and exits |
| `figures/fig2_peachland_added_time.png` | Added response time, Hwy 97 closed through Peachland |
| `figures/fig3_shared_roads_wk.png` | Roads shared by evacuees and responders, Hwy 97 closed through West Kelowna |

## Assumptions
Speeds are assumed (the road atlas has none). Roads are treated as two-way. Closed segments are impassable. Destinations are equally weighted road points (group baseline). Evacuation is free-flow, with no queuing.
