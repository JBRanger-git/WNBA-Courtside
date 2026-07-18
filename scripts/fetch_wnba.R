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
# Standings and per-player season stats are computed straight from the box
# scores rather than trusting a separate feed, so they can't disagree with the
# scores the app shows. usage_pct uses the standard usage-rate formula.
#
# Run:  Rscript scripts/fetch_wnba.R      (WNBA_SEASON env overrides the year)
# =============================================================================
suppressPackageStartupMessages({
  library(wehoop); library(dplyr); library(tidyr); library(readr)
})
options(dplyr.summarise.inform = FALSE)

SEASON <- as.integer(Sys.getenv("WNBA_SEASON", unset = format(Sys.Date(), "%Y")))
OUT <- "data/csv"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
message("Fetching WNBA season ", SEASON, " ...")

# first existing column name from a list of candidates; else a constant column
col <- function(df, cands, default = NA) {
  hit <- cands[cands %in% names(df)]
  if (length(hit)) df[[hit[1]]] else rep(default, nrow(df))
}
regular <- function(df) if ("season_type" %in% names(df)) filter(df, season_type == 2) else df

team_box   <- load_wnba_team_box(seasons = SEASON)   |> regular()
player_box <- load_wnba_player_box(seasons = SEASON) |> regular()
sched      <- load_wnba_schedule(seasons = SEASON)   |> regular()

# Column names vary across wehoop versions; log them so mismatches are obvious.
message("team_box cols: ",   paste(names(team_box), collapse = ", "))
message("schedule cols: ",   paste(names(sched), collapse = ", "))
message("player_box cols: ", paste(names(player_box), collapse = ", "))
stopifnot(nrow(team_box) > 0, nrow(player_box) > 0, nrow(sched) > 0)

# --- dim_teams: current-season snapshot ------------------------------------
dim_teams <- team_box |>
  transmute(team_id,
            abbreviation      = col(team_box, "team_abbreviation"),
            team_display_name = col(team_box, "team_display_name"),
            team_short_name   = col(team_box, c("team_name", "team_short_display_name", "team_location")),
            color             = col(team_box, c("team_color", "team_alternate_color"))) |>
  distinct(team_id, .keep_all = TRUE) |>
  arrange(team_display_name)
write_csv(dim_teams, file.path(OUT, "dim_teams.csv"), na = "")
message("  dim_teams          ", nrow(dim_teams))

# --- fact_team_box: the source of truth for scores & completion ------------
fact_team_box <- team_box |>
  transmute(game_id,
            team_home_away = col(team_box, "team_home_away"),
            team_score     = col(team_box, c("team_score", "team_winner_score")))
write_csv(fact_team_box, file.path(OUT, "fact_team_box.csv"), na = "")
message("  fact_team_box      ", nrow(fact_team_box))

# --- dim_games: from the schedule feed -------------------------------------
dim_games <- tibble(
  game_id            = sched$game_id,
  game_date          = as.character(col(sched, c("game_date", "date"))),
  home_team_id       = col(sched, c("home_id", "home_team_id")),
  away_team_id       = col(sched, c("away_id", "away_team_id")),
  home_display_name  = col(sched, "home_display_name"),
  away_display_name  = col(sched, "away_display_name"),
  broadcast_name     = col(sched, c("broadcast_name", "broadcast"), ""),
  venue_address_city = col(sched, "venue_address_city", ""),
  neutral_site       = col(sched, "neutral_site", FALSE),
  venue_full_name    = col(sched, "venue_full_name", ""),
  attendance         = col(sched, "attendance", NA)
)
write_csv(dim_games, file.path(OUT, "dim_games.csv"), na = "")
message("  dim_games          ", nrow(dim_games))

# --- fact_standings: computed from the box scores --------------------------
# Opponent score via a self-join (robust to whether opponent_team_score exists).
ha  <- team_box |> transmute(game_id,
                             team_home_away = col(team_box, "team_home_away"),
                             team_id,
                             team_score = col(team_box, "team_score"),
                             game_date  = col(team_box, "game_date"))
opp <- ha |> transmute(game_id,
                       team_home_away = if_else(team_home_away == "home", "away", "home"),
                       opp_score = team_score)
g <- ha |>
  left_join(opp, by = c("game_id", "team_home_away")) |>
  filter(!is.na(opp_score)) |>
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
safe <- function(n, d) if_else(d > 0, n / d, 0)
player_box$dnp      <- col(player_box, "did_not_play", FALSE)
player_box$pos_abbr <- col(player_box, "athlete_position_abbreviation", "")
played <- filter(player_box, dnp == FALSE)

primary <- played |>
  count(athlete_id, team_id, name = "gp") |>
  group_by(athlete_id) |> slice_max(gp, n = 1, with_ties = FALSE) |> ungroup() |>
  select(athlete_id, team_id)

team_tot <- played |>
  group_by(team_id) |>
  summarise(tm_min = sum(minutes, na.rm = TRUE),
            tm_fga = sum(field_goals_attempted, na.rm = TRUE),
            tm_fta = sum(free_throws_attempted, na.rm = TRUE),
            tm_tov = sum(turnovers, na.rm = TRUE), .groups = "drop")

fact_player_season <- played |>
  group_by(athlete_id) |>
  summarise(
    athlete_display_name = last(athlete_display_name),
    athlete_position_abbreviation = last(pos_abbr),
    games_played    = n(),
    min_tot = sum(minutes, na.rm = TRUE),
    pts_tot = sum(points, na.rm = TRUE),
    reb_tot = sum(rebounds, na.rm = TRUE),
    ast_tot = sum(assists, na.rm = TRUE),
    steals_total    = sum(steals, na.rm = TRUE),
    blocks_total    = sum(blocks, na.rm = TRUE),
    turnovers_total = sum(turnovers, na.rm = TRUE),
    fgm = sum(field_goals_made, na.rm = TRUE),
    fga = sum(field_goals_attempted, na.rm = TRUE),
    tpm = sum(three_point_field_goals_made, na.rm = TRUE),
    tpa = sum(three_point_field_goals_attempted, na.rm = TRUE),
    ftm = sum(free_throws_made, na.rm = TRUE),
    fta = sum(free_throws_attempted, na.rm = TRUE),
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
