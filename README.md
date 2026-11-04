# COSC 421 — shared wildfire road-network data

Shared starting data for the Peachland–West Kelowna case study. Snapshot: 4 November 2026. This repository currently contains data and this guide; individual research-question scripts, rankings, maps and reports remain local.

## Start here

Use the four CSV files together:

| File | Contents |
| --- | --- |
| nodes.csv | 2,545 road nodes: coordinate-string `id`, longitude, latitude, municipality (`town`), and destination flag `is_target`. Nodes include intersections and road-segment breaks. |
| edges.csv | 2,986 road segments: endpoint IDs `from` and `to`, DRA segment `id`, `street`, road `class`, and length `m` in metres. |
| stations.csv | Five fire stations, matched addresses, geocoder scores, coordinates, and links to their road segments. |
| baseline_access.csv | 1,687 local-road destination IDs and shortest distance from the nearest of the five stations, in kilometres (`nearest_station_baseline_km`). This is a derived baseline, not observed emergency-response data. |

Read node IDs and segment IDs as character strings and preserve their full precision. Join edges to nodes using `from`/`to` and `id`. Coordinates use EPSG:4326. The road network is undirected (two-way) and uses length weights, not travel-time weights.

For each station, `road_id` identifies its road segment, `from` and `to` are its endpoint nodes, and `fraction` is the position along that segment measured from `from`. Connect a station origin to `from` at `fraction * m` and to `to` at `(1 - fraction) * m`. Origin links should allow departures without creating shortcuts through the station. `offset_m` records the perpendicular station-to-road offset; it is not included in baseline distances. The geocoder `score` is an address-match score, not a road-access rating.

## Original inputs and sources

`original-source-data.zip` contains a `raw/` folder with the downloaded roads and municipal polygons, the road schema, and five cached BC address-geocoder responses. Attribution: Province of British Columbia; City of West Kelowna; District of Peachland. Source data retain their original terms.

- [BC Digital Road Atlas — Master Partially-Attributed Roads](https://catalogue.data.gov.bc.ca/dataset/digital-road-atlas-dra-master-partially-attributed-roads)
- [BC municipal boundaries](https://catalogue.data.gov.bc.ca/dataset/municipalities-legally-defined-administrative-areas-of-bc)
- [BC address geocoder](https://geocoder.api.gov.bc.ca/addresses.json)
- [West Kelowna fire-hall addresses](https://www.westkelownacity.ca/city-hall/contact-us/)
- [Updated station 32 address](https://www.westkelownacity.ca/news/posts/new-fire-station-32-community-hall-and-park-improvements-officially-opened/)
- [Peachland community handbook](https://www.peachland.ca/sites/default/files/2026-02/2026%20Peachland%20Community%20Handbook%20for%20web.pdf)

Downloaded 4 November 2026 via `https://openmaps.gov.bc.ca/geo/pub/ows`, WFS 1.0.0 GetFeature, JSON, EPSG:4326; bbox `-119.81,49.73,-119.515,49.93`. Layers: `pub:WHSE_BASEMAPPING.DRA_DGTL_ROAD_ATLAS_MPAR_SP` (maxFeatures 30000) and `pub:WHSE_LEGAL_ADMIN_BOUNDARIES.ABMS_MUNICIPALITIES_SP`. Road properties requested: DIGITAL_ROAD_ATLAS_LINE_ID, ROAD_NAME_FULL, ROAD_CLASS, FEATURE_TYPE, FEATURE_LENGTH_M, HIGHWAY_ROUTE_NUMBER, GEOMETRY.

## Preparation and limits

The raw road response contains 5,992 features. The shared graph retains Road/Bridge features in local, collector, arterial, highway, freeway, ramp, lane, yield and service classes, with both endpoints inside the study window. Strata, resource, driveway and unclassified roads are excluded. Exact matching endpoints form connections; visually crossing lines are not automatically joined. The largest connected component is retained, excluding 152 other vertices. Connecting roads outside the municipal boundaries are retained within the window.

Destinations are municipal nodes touching a local-class road. They represent road points, not households, populations or complete neighbourhoods, and are equally weighted. Any of the five stations is assumed able to serve any destination. The boundary can exclude longer detours, and mapped connections need verification before interpreting a neighbourhood as inaccessible.

**Not included or verified:** one-way restrictions, legal turning movements, speeds, traffic counts, congestion, actual highway-closure records, wildfire perimeters, census populations, dispatch times or staffing. Teammates will need additional inputs or explicit assumptions for those questions. Distance outputs must not be described as travel times.

Use this same baseline across questions. Agree on any changes to nodes, roads, station connections or destinations before combining results. The RQ1 preparation and analysis script is currently held locally by Reyhan and can be added later if the group needs to rebuild the data.
