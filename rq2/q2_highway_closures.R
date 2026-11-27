library(igraph)
library(dplyr)
library(readr)
library(ggplot2)

root    <- if (file.exists("nodes.csv")) "." else ".."
out_dir <- file.path(root, "rq2")
res_dir <- file.path(out_dir, "results")
fig_dir <- file.path(out_dir, "figures")
dir.create(res_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

nodes    <- read_csv(file.path(root, "nodes.csv"),    col_types = cols(id = "c", .default = "?"))
edges    <- read_csv(file.path(root, "edges.csv"),    col_types = cols(from = "c", to = "c", id = "c", .default = "?"))
stations <- read_csv(file.path(root, "stations.csv"), col_types = cols(road_id = "c", from = "c", to = "c", .default = "?"))

targets <- nodes$id[nodes$is_target]
town    <- setNames(ifelse(is.na(nodes$town), "Outside", nodes$town), nodes$id)

speeds <- list(
  base = c(freeway = 100, highway = 90, arterial = 60, collector = 50, ramp = 50,
           local = 40, service = 30, lane = 20, yield = 30),
  slow = c(freeway = 80,  highway = 70, arterial = 50, collector = 40, ramp = 40,
           local = 30, service = 20, lane = 15, yield = 20),
  fast = c(freeway = 110, highway = 100, arterial = 70, collector = 60, ramp = 60,
           local = 50, service = 40, lane = 30, yield = 40)
)

seg_town <- ifelse(town[edges$from] != "Outside", town[edges$from],
            ifelse(town[edges$to]   != "Outside", town[edges$to], "Between"))
is97  <- !is.na(edges$street) & edges$street == "Hwy 97"
is97C <- !is.na(edges$street) & edges$street == "Hwy 97C"

scenarios <- list(
  baseline        = character(0),
  H97_Peachland   = edges$id[is97 & seg_town == "Peachland"],
  H97_WestKelowna = edges$id[is97 & seg_town == "West Kelowna"],
  H97_full        = edges$id[is97],
  H97C            = edges$id[is97C],
  H97_and_H97C    = edges$id[is97 | is97C],    # Drought Hill, 30 Jul 2025
  McDougall_2023  = edges$id[(is97 & pmin(nodes$lon[match(edges$from, nodes$id)],
                                          nodes$lon[match(edges$to, nodes$id)]) > -119.60) |
                             (!is.na(edges$street) & edges$street == "Westside Rd" &
                              (town[edges$from] != "West Kelowna" | town[edges$to] != "West Kelowna"))]
)

exits <- c(E1_Hwy97_east  = "-119.51898219,49.87806229",
           E2_Hwy97_south = "-119.76773700,49.73620647",
           E3_Hwy97C_west = "-119.80887592,49.83105759",
           E4_Westside_N  = "-119.52191231,49.92307098",
           E5_Princeton_W = "-119.80870747,49.75685461")

build_graph <- function(spd, closed) {
  ed <- edges %>% filter(!id %in% closed) %>%
    mutate(t = m / 1000 / spd[class] * 60)                   # minutes
  # keep the fastest of any parallel segments
  ed <- ed %>% mutate(a = pmin(from, to), b = pmax(from, to)) %>%
    group_by(a, b) %>% slice_min(t, n = 1, with_ties = FALSE) %>% ungroup() %>%
    select(from, to, id, street, class, m, t)

  # station links: split the station's segment at `fraction`
  st_links <- bind_rows(lapply(seq_len(nrow(stations)), function(i) {
    s   <- stations[i, ]
    seg <- edges[edges$id == s$road_id, ][1, ]
    v   <- spd[seg$class]
    tibble(from = s$station, to = c(s$from, s$to), id = paste0("stn_", s$station),
           street = "(station link)", class = "station",
           m = seg$m * c(s$fraction, 1 - s$fraction),
           t = seg$m * c(s$fraction, 1 - s$fraction) / 1000 / v * 60)
  }))
  # super-source so each destination is served by its nearest station
  src <- tibble(from = "SRC", to = stations$station, id = "src", street = "",
                class = "src", m = 0, t = 0)
  graph_from_data_frame(bind_rows(ed, st_links, src), directed = FALSE)
}

route_flows <- function(spd, closed, mode = c("resp", "evac")) {
  mode <- match.arg(mode)
  g    <- build_graph(spd, closed)
  if (mode == "evac") {
    g <- delete_vertices(g, "SRC")
    ex <- intersect(exits, V(g)$name)
    g <- add_vertices(g, 1, name = "SINK")
    g <- add_edges(g, as.vector(rbind("SINK", ex)), attr = list(t = 0, m = 0, street = "", id = "sink"))
    src_node <- "SINK"
  } else src_node <- "SRC"
  tgt  <- intersect(targets, V(g)$name)
  d    <- distances(g, v = src_node, to = tgt, weights = E(g)$t)[1, ]
  time <- setNames(rep(Inf, length(targets)), targets); time[tgt] <- d
  reach <- tgt[is.finite(d)]
  sp <- shortest_paths(g, from = src_node, to = reach, weights = E(g)$t, output = "both")
  first <- setNames(sapply(sp$vpath, function(p) names(p)[2]), reach)
  used <- unlist(lapply(sp$epath, function(p) unique(E(g)$street[p])))   # distinct routes per street
  used <- used[!used %in% c("", "(station link)")]
  load <- as.data.frame(table(street = used), stringsAsFactors = FALSE)
  list(time = time, load = load, first = first)
}
run_scenario <- function(spd, closed) route_flows(spd, closed, "resp")

summary_rows <- list()
for (sname in names(speeds)) {
  base <- run_scenario(speeds[[sname]], character(0))
  for (sc in names(scenarios)) {
    r   <- if (sc == "baseline") base else run_scenario(speeds[[sname]], scenarios[[sc]])
    fin <- is.finite(r$time)
    inc <- r$time - base$time
    summary_rows[[length(summary_rows) + 1]] <- tibble(
      speed = sname, scenario = sc, closed_segments = length(scenarios[[sc]]),
      mean_min = mean(r$time[fin]), median_min = median(r$time[fin]),
      max_min = max(r$time[fin]), disconnected = sum(!fin),
      n_increase_gt1min = sum(inc[fin] > 1), max_increase_min = max(inc[fin]),
      switched_station = sum(r$first[names(base$first)] != base$first, na.rm = TRUE),
      mean_Peachland   = mean(r$time[fin & town[targets] == "Peachland"]),
      mean_WestKelowna = mean(r$time[fin & town[targets] == "West Kelowna"]))

    if (sname == "base" && sc != "baseline") {
      rr <- full_join(base$load, r$load, by = "street", suffix = c("_base", "_closed")) %>%
        mutate(across(starts_with("Freq"), ~ coalesce(.x, 0L)),
               change = Freq_closed - Freq_base) %>%
        arrange(desc(change))
      write_csv(rr, file.path(res_dir, sprintf("rq2_reroute_%s.csv", sc)))
    }
  }
}
summary_tbl <- bind_rows(summary_rows)

evac_rows <- list()
eb <- route_flows(speeds$base, character(0), "evac")
for (sc in names(scenarios)) {
  ev  <- route_flows(speeds$base, scenarios[[sc]], "evac")
  rs  <- route_flows(speeds$base, scenarios[[sc]], "resp")
  fin <- is.finite(ev$time)
  evac_rows[[sc]] <- tibble(scenario = sc, mean_evac_min = mean(ev$time[fin]),
    max_evac_min = max(ev$time[fin]), no_exit = sum(!fin),
    n_increase_gt2min = sum((ev$time - eb$time)[fin] > 2),
    exits_used = { tb <- table(names(exits)[match(ev$first, exits)]); paste(names(tb), tb, collapse = "; ") })
  shared <- inner_join(ev$load, rs$load, by = "street", suffix = c("_evac", "_resp")) %>%
    filter(!grepl("^Hwy", street)) %>%
    mutate(conflict = Freq_evac * Freq_resp) %>% arrange(desc(conflict))
  write_csv(shared, file.path(res_dir, sprintf("rq2_shared_roads_%s.csv", sc)))
}
evac_tbl <- bind_rows(evac_rows)
write_csv(evac_tbl, file.path(res_dir, "rq2_evacuation_summary.csv"))
print(evac_tbl, width = Inf)
write_csv(summary_tbl, file.path(res_dir, "rq2_summary.csv"))
print(summary_tbl, n = Inf, width = Inf)

g0 <- build_graph(speeds$base, character(0))
g0_roads <- delete_vertices(g0, c("SRC", stations$station))
cat("Nodes:", vcount(g0_roads), " Edges:", ecount(g0_roads),
    " Average degree:", round(mean(degree(g0_roads)), 2), "\n")

eb <- edge_betweenness(g0_roads, weights = E(g0_roads)$t, directed = FALSE)
eb_street <- tibble(street = E(g0_roads)$street, eb = eb) %>%
  group_by(street) %>% summarise(eb = max(eb)) %>%
  arrange(desc(eb)) %>% mutate(eb_rank = row_number())

reroute_full <- read_csv(file.path(res_dir, "rq2_reroute_H97_full.csv"), show_col_types = FALSE)
cmp <- reroute_full %>% filter(change > 0) %>% slice_head(n = 10) %>%
  left_join(eb_street, by = "street")
write_csv(cmp, file.path(res_dir, "rq2_eb_vs_reroute.csv"))
print(cmp)

base <- run_scenario(speeds$base, character(0))
pch  <- run_scenario(speeds$base, scenarios$H97_Peachland)
plot_df <- nodes %>% filter(is_target) %>%
  mutate(increase = pch$time[id] - base$time[id],
         status = ifelse(is.infinite(increase), "Cut off", "Reachable"))
ggplot(plot_df, aes(lon, lat)) +
  geom_point(data = filter(plot_df, status == "Reachable"),
             aes(colour = pmin(increase, 5)), size = 0.8) +
  geom_point(data = filter(plot_df, status == "Cut off"), colour = "black", shape = 4) +
  scale_colour_viridis_c(name = "Added time (min)") +
  coord_quickmap(xlim = c(-119.80, -119.66), ylim = c(49.74, 49.82)) + theme_minimal() +
  labs(title = "Fig. 2  Hwy 97 closure through Peachland: added response time",
       subtitle = "Destinations (road points); x = no route from any station",
       x = "Longitude", y = "Latitude")
ggsave(file.path(fig_dir, "fig2_peachland_added_time.png"), width = 7, height = 6, dpi = 200)

seg_df <- function(ids = NULL) {
  ed <- if (is.null(ids)) edges else edges[edges$id %in% ids, ]
  ed %>% mutate(x = nodes$lon[match(from, nodes$id)], y = nodes$lat[match(from, nodes$id)],
                xend = nodes$lon[match(to, nodes$id)], yend = nodes$lat[match(to, nodes$id)])
}
all_seg <- seg_df()
exit_df <- nodes %>% filter(id %in% exits) %>% mutate(exit = names(exits)[match(id, exits)])

ggplot() +
  geom_segment(data = all_seg, aes(x, y, xend = xend, yend = yend), colour = "grey80", linewidth = 0.3) +
  geom_segment(data = filter(all_seg, street %in% c("Hwy 97", "Hwy 97C")),
               aes(x, y, xend = xend, yend = yend, colour = street), linewidth = 1.2) +
  geom_point(data = stations, aes(lon, lat), shape = 17, size = 3) +
  geom_text(data = stations, aes(lon, lat, label = station), nudge_x = 0.009, nudge_y = 0.003, size = 3) +
  geom_point(data = exit_df, aes(lon, lat), shape = 15, size = 3, colour = "forestgreen") +
  geom_text(data = exit_df, aes(lon, lat, label = substr(exit, 1, 2)), nudge_y = -0.005,
            size = 3, colour = "forestgreen") +
  scale_colour_manual(values = c("Hwy 97" = "#d62728", "Hwy 97C" = "#ff7f0e"), name = NULL) +
  coord_quickmap() + theme_minimal() +
  labs(title = "Fig. 1  Peachland–West Kelowna road network",
       subtitle = "Triangles = fire stations; squares = evacuation exits", x = "Longitude", y = "Latitude")
ggsave(file.path(fig_dir, "fig1_network.png"), width = 7, height = 6, dpi = 200)

wk_ev <- route_flows(speeds$base, scenarios$H97_WestKelowna, "evac")
wk_rs <- route_flows(speeds$base, scenarios$H97_WestKelowna, "resp")
top_shared <- inner_join(wk_ev$load, wk_rs$load, by = "street", suffix = c("_evac", "_resp")) %>%
  filter(!grepl("^Hwy", street)) %>% mutate(conflict = Freq_evac * Freq_resp) %>%
  arrange(desc(conflict)) %>% slice_head(n = 6) %>%
  mutate(label = sprintf("%s: %s evac / %d resp", street, formatC(Freq_evac, big.mark = ",", format = "d"), Freq_resp))
shared_seg <- all_seg %>% inner_join(top_shared, by = "street")
ggplot() +
  geom_segment(data = all_seg, aes(x, y, xend = xend, yend = yend), colour = "grey80", linewidth = 0.3) +
  geom_segment(data = seg_df(scenarios$H97_WestKelowna), aes(x, y, xend = xend, yend = yend),
               colour = "black", linetype = "dashed", linewidth = 1) +
  geom_segment(data = shared_seg, aes(x, y, xend = xend, yend = yend,
               colour = factor(label, levels = top_shared$label)), linewidth = 1.4) +
  scale_colour_brewer(palette = "Dark2", name = NULL) +
  coord_quickmap(xlim = c(-119.70, -119.51), ylim = c(49.80, 49.935)) + theme_minimal() +
  theme(legend.position = "bottom", legend.direction = "vertical") +
  labs(title = "Fig. 3  Roads shared by evacuees and responders",
       subtitle = "Hwy 97 closed through West Kelowna (dashed)", x = "Longitude", y = "Latitude")
ggsave(file.path(fig_dir, "fig3_shared_roads_wk.png"), width = 7, height = 8, dpi = 200)
