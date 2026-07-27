# =============================================================================
# Courtside — team identity stats (points in paint, fast break points, points
# conceded off turnovers, largest lead, lead changes, and an estimated
# possessions/game) for completed games, from ESPN's per-game summary feed.
# Writes data/csv/fact_team_advanced.csv:
#     game_id, team_id, home_away, pip, fbp, tov_pts, largest_lead, lead_changes, poss
#
# wehoop's bulk load_wnba_team_box() carries these fields too, but — like the
# scores in fetch_wnba.R — it lags mid-season and comes back empty for the
# current season. Same reason fetch_lines.R hits ESPN live for linescores
# instead of the bulk feed. Field names verified against a live game via a CI
# diagnostic dump, not guessed.
#
# `poss` is the standard estimate (FGA - OREB + TOV + 0.44*FTA) computed from
# real per-game inputs ESPN does report — not something ESPN gives directly,
# but a well-established formula, not a guess. `pace` (per-minute normalized)
# is deliberately NOT computed: that needs a normalization convention this
# codebase has no verified precedent for, and a subtly wrong "pace" is worse
# than no pace at all — CLAUDE.md: "a blank field beats a wrong one."
#
# FULLY DEFENSIVE: any single game's fetch failure is skipped, not fatal;
# build_data.py aggregates whatever rows exist to season averages and
# preserves the previous averages when this CSV is entirely absent.
#
# Run:  Rscript scripts/fetch_team_advanced.R
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(dplyr); library(readr) })

OUT <- "data/csv"
tb_path <- file.path(OUT, "fact_team_box.csv")
if (!file.exists(tb_path)) {
  message("  team-advanced: missing team-box csv — skipping"); quit(save = "no", status = 0)
}

tb <- suppressMessages(read_csv(tb_path, show_col_types = FALSE))
# A game is completed iff fact_team_box has both sides (CLAUDE.md).
completed <- tb |>
  group_by(game_id) |>
  summarise(sides = n_distinct(team_home_away), .groups = "drop") |>
  filter(sides >= 2)
game_ids <- unique(completed$game_id)
if (length(game_ids) == 0) { message("  team-advanced: no completed games — skipping"); quit(save = "no", status = 0) }
message("  team-advanced: fetching boxscore stats for ", length(game_ids), " completed games")

# Pull a named stat's numeric displayValue out of ESPN's team statistics list.
num_from <- function(stats, key) {
  hit <- Filter(function(s) identical(s$name, key), stats)
  if (length(hit) == 0) return(NA_real_)
  suppressWarnings(as.numeric(hit[[1]]$displayValue))
}
# "35-74" -> 74 (the attempted half of a made-attempted pair, e.g. FGA/FTA).
attempted_from <- function(stats, key) {
  hit <- Filter(function(s) identical(s$name, key), stats)
  if (length(hit) == 0) return(NA_real_)
  parts <- strsplit(hit[[1]]$displayValue, "-")[[1]]
  if (length(parts) != 2) return(NA_real_)
  suppressWarnings(as.numeric(parts[2]))
}

rows <- list()
for (gid in game_ids) {
  url <- paste0("https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/summary?event=", gid)
  sb <- tryCatch(fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
  teams <- tryCatch(sb$boxscore$teams, error = function(e) NULL)
  if (is.null(teams) || length(teams) < 2) next
  for (t in teams) {
    tid <- tryCatch(as.character(t$team$id), error = function(e) NA_character_)
    stats <- t$statistics
    if (is.na(tid) || is.null(stats)) next
    fga  <- attempted_from(stats, "fieldGoalsMade-fieldGoalsAttempted")
    fta  <- attempted_from(stats, "freeThrowsMade-freeThrowsAttempted")
    oreb <- num_from(stats, "offensiveRebounds")
    tov  <- num_from(stats, "turnovers")
    poss <- if (!anyNA(c(fga, oreb, tov, fta))) fga - oreb + tov + 0.44 * fta else NA_real_
    rows[[length(rows) + 1]] <- data.frame(
      game_id = as.character(gid), team_id = tid, home_away = t$homeAway,
      pip          = num_from(stats, "pointsInPaint"),
      fbp          = num_from(stats, "fastBreakPoints"),
      tov_pts      = num_from(stats, "turnoverPoints"),
      largest_lead = num_from(stats, "largestLead"),
      lead_changes = num_from(stats, "leadChanges"),
      poss         = poss,
      stringsAsFactors = FALSE
    )
  }
  Sys.sleep(0.12)  # be polite to the endpoint
}

if (length(rows) == 0) { message("  team-advanced: none extracted — leaving csv absent"); quit(save = "no", status = 0) }
df <- dplyr::distinct(do.call(rbind, rows), game_id, team_id, .keep_all = TRUE)
write_csv(df, file.path(OUT, "fact_team_advanced.csv"), na = "")
message("  fact_team_advanced ", nrow(df), " team-rows (", dplyr::n_distinct(df$game_id), " games)")
