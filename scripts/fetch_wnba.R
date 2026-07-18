# =============================================================================
# Courtside — daily data fetch (current season) via wehoop / ESPN.
#
# Writes only the FAST-MOVING CSVs that build_data.py consumes:
#     dim_teams.csv  dim_games.csv  fact_team_box.csv
#     fact_standings.csv  fact_player_season.csv
#
# It deliberately does NOT write dim_players.csv (bios), dim_news.csv, or
# fact_pbp.csv — build_data.py preserves those slow/hard datasets (player bio,
# news, the shot fingerprint) from the previous app-data.json. See CLAUDE.md:
# "a blank field beats a wrong one".
#
# player_box is the spine: it carries team identity, final scores and home/away
# on every row, so teams / team-box / standings are all derived from it. We do
# NOT depend on load_wnba_team_box — its bulk data release lags for the current
# season and comes back empty mid-season. Standings and per-player season stats
# are computed straight from the box scores so they can't disagree with the
# scores the app shows. usage_pct uses the standard usage-rate formula.
#
# Column names below are the exact ones wehoop returns (verified from a CI run).
#
# Run:  Rscript scripts/fetch_wnba.R      (WNBA_SEASON env overrides the year)
# =============================================================================
suppressPackageStartupMessages({
  library(wehoop); library(dplyr); library(readr); library(bit64)
})
options(dplyr.summarise.inform = FALSE)

# wehoop's ID columns are integer64. Coerce every ID to character right after
# load so joins/distinct/CSV writing are free of integer64 quirks, and so a
# failed (all-NA) read is caught by the guard below rather than silently
# collapsing every table to one row.
chr_ids <- function(df) {
  ids <- c("team_id", "athlete_id", "game_id", "home_id", "away_id",
           "home_team_id", "away_team_id", "opponent_team_id")
  for (nm in intersect(ids, names(df))) df[[nm]] <- as.character(df[[nm]])
  df
}

SEASON <- as.integer(Sys.getenv("WNBA_SEASON", unset = format(Sys.Date(), "%Y")))
OUT <- "data/csv"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
message("Fetching WNBA season ", SEASON, " ...")

num <- function(x) suppressWarnings(as.numeric(x))
# regular season only, but never let the filter empty the frame
regular <- function(df) {
  if (!"season_type" %in% names(df)) return(df)
  r <- dplyr::filter(df, season_type == 2)
  if (nrow(r) > 0) r else df
}
# pick a column by name if present, else a constant vector of the right length
pick <- function(df, name, default = NA) if (name %in% names(df)) df[[name]] else rep(default, nrow(df))

player_box <- chr_ids(load_wnba_player_box(seasons = SEASON))
sched      <- chr_ids(load_wnba_schedule(seasons = SEASON))
message("loaded rows — player_box: ", nrow(player_box), "  schedule: ", nrow(sched))
stopifnot(nrow(player_box) > 0, nrow(sched) > 0)

pb <- regular(player_box)
sc <- regular(sched)
message("regular-season rows — player_box: ", nrow(pb), "  schedule: ", nrow(sc),
        "  distinct teams: ", dplyr::n_distinct(pb$team_id))
# Guard: if the integer64 IDs failed to materialise they come back all-NA and
# every derived table collapses to one garbage row. Fail loudly instead.
if (dplyr::n_distinct(pb$team_id) < 2 || all(is.na(pb$team_id)))
  stop("team_id is degenerate (all NA?) — wehoop's integer64 IDs did not ",
       "materialise. The 'arrow' package must be installed so the parquet ",
       "sibling is read. See CLAUDE.md / backfill_history.R.")

# --- one row per team per game (scores, home/away) from player_box ---------
tg <- pb |>
  mutate(team_score = num(team_score), opp_score = num(opponent_team_score)) |>
  group_by(game_id, team_id) |>
  summarise(team_home_away = dplyr::first(home_away),
            team_score     = dplyr::first(team_score),
            opp_score      = dplyr::first(opp_score),
            game_date      = dplyr::first(game_date),
            .groups = "drop") |>
  filter(!is.na(team_score), !is.na(opp_score))

# --- dim_teams: current-season snapshot ------------------------------------
dim_teams <- pb |>
  distinct(team_id, team_abbreviation, team_display_name, team_name, team_color) |>
  transmute(team_id,
            abbreviation      = team_abbreviation,
            team_display_name,
            team_short_name   = team_name,
            color             = team_color) |>
  distinct(team_id, .keep_all = TRUE) |>
  arrange(team_display_name)
write_csv(dim_teams, file.path(OUT, "dim_teams.csv"), na = "")
message("  dim_teams          ", nrow(dim_teams))

# --- fact_team_box: the source of truth for scores & completion ------------
fact_team_box <- tg |> transmute(game_id, team_home_away, team_score)
write_csv(fact_team_box, file.path(OUT, "fact_team_box.csv"), na = "")
message("  fact_team_box      ", nrow(fact_team_box))

# --- dim_games: from the schedule feed -------------------------------------
dim_games <- tibble(
  game_id            = sc$game_id,
  game_date          = as.character(pick(sc, "game_date")),
  home_team_id       = pick(sc, "home_id"),
  away_team_id       = pick(sc, "away_id"),
  home_display_name  = pick(sc, "home_display_name"),
  away_display_name  = pick(sc, "away_display_name"),
  broadcast_name     = pick(sc, "broadcast_name", ""),
  venue_address_city = pick(sc, "venue_address_city", ""),
  neutral_site       = pick(sc, "neutral_site", FALSE),
  venue_full_name    = pick(sc, "venue_full_name", ""),
  attendance         = pick(sc, "attendance", NA)
) |> distinct(game_id, .keep_all = TRUE)
write_csv(dim_games, file.path(OUT, "dim_games.csv"), na = "")
message("  dim_games          ", nrow(dim_games))

# --- fact_standings: computed from the box scores --------------------------
g <- tg |>
  mutate(win = team_score > opp_score, home = team_home_away == "home") |>
  arrange(team_id, game_date)
fact_standings <- g |>
  group_by(team_id) |>
  summarise(
    wins               = sum(win),
    losses             = sum(!win),
    ppg_for            = round(mean(team_score), 1),
    ppg_against        = round(mean(opp_score), 1),
    point_differential = sum(team_score - opp_score),
    streak      = { r <- rle(rev(win)); paste0(if_else(r$values[1], "W", "L"), r$lengths[1]) },
    last_ten    = { l <- tail(win, 10); paste0(sum(l), "-", length(l) - sum(l)) },
    home_record = { h <- win[home];  paste0(sum(h), "-", length(h) - sum(h)) },
    road_record = { a <- win[!home]; paste0(sum(a), "-", length(a) - sum(a)) },
    .groups = "drop"
  ) |>
  mutate(win_pct = round(wins / pmax(wins + losses, 1), 3)) |>
  select(team_id, wins, losses, win_pct, ppg_for, ppg_against,
         point_differential, streak, last_ten, home_record, road_record)
write_csv(fact_standings, file.path(OUT, "fact_standings.csv"), na = "")
message("  fact_standings     ", nrow(fact_standings))

# --- fact_player_season: aggregated from player box scores -----------------
# did_not_play == FALSE is the reliable "played" flag (NOT active == TRUE).
safe   <- function(n, d) if_else(d > 0, n / d, 0)
ssum   <- function(x) sum(num(x), na.rm = TRUE)
played <- pb |>
  mutate(mins = num(minutes)) |>
  mutate(mins = if_else(is.na(mins), 0, mins)) |>
  filter(did_not_play == FALSE)

primary <- played |>
  count(athlete_id, team_id, name = "gp") |>
  group_by(athlete_id) |> slice_max(gp, n = 1, with_ties = FALSE) |> ungroup() |>
  select(athlete_id, team_id)

team_tot <- played |>
  group_by(team_id) |>
  summarise(tm_min = sum(mins),
            tm_fga = ssum(field_goals_attempted),
            tm_fta = ssum(free_throws_attempted),
            tm_tov = ssum(turnovers), .groups = "drop")

fact_player_season <- played |>
  group_by(athlete_id) |>
  summarise(
    athlete_display_name          = dplyr::last(athlete_display_name),
    athlete_position_abbreviation = dplyr::last(athlete_position_abbreviation),
    games_played    = n(),
    min_tot = sum(mins),
    pts_tot = ssum(points),
    reb_tot = ssum(rebounds),
    ast_tot = ssum(assists),
    steals_total    = ssum(steals),
    blocks_total    = ssum(blocks),
    turnovers_total = ssum(turnovers),
    fgm = ssum(field_goals_made),                fga = ssum(field_goals_attempted),
    tpm = ssum(three_point_field_goals_made),    tpa = ssum(three_point_field_goals_attempted),
    ftm = ssum(free_throws_made),                fta = ssum(free_throws_attempted),
    .groups = "drop"
  ) |>
  left_join(primary,  by = "athlete_id") |>
  left_join(team_tot, by = "team_id") |>
  mutate(
    mpg          = round(safe(min_tot, games_played), 1),
    ppg          = round(safe(pts_tot, games_played), 1),
    rpg          = round(safe(reb_tot, games_played), 1),
    apg          = round(safe(ast_tot, games_played), 1),
    tpa_per_game = round(safe(tpa, games_played), 1),
    fg_pct       = round(safe(fgm, fga), 3),
    three_pct    = round(safe(tpm, tpa), 3),
    ft_pct       = round(safe(ftm, fta), 3),
    ts_pct       = round(safe(pts_tot, 2 * (fga + 0.44 * fta)), 3),
    usage_pct    = round(safe((fga + 0.44 * fta + turnovers_total) * (tm_min / 5),
                              min_tot * (tm_fga + 0.44 * tm_fta + tm_tov)), 3)
  ) |>
  select(athlete_id, athlete_display_name, team_id, athlete_position_abbreviation,
         games_played, mpg, ppg, rpg, apg, steals_total, blocks_total, turnovers_total,
         fg_pct, three_pct, ft_pct, ts_pct, usage_pct, tpa_per_game)
write_csv(fact_player_season, file.path(OUT, "fact_player_season.csv"), na = "")
message("  fact_player_season ", nrow(fact_player_season))

message("\nDone. build_data.py preserves bios, news and the shot fingerprint from ",
        "the previous snapshot.")
