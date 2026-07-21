# =============================================================================
# WNBA Courtside — historical backfill, 2020–2026
#
# Extends the existing single-season pipeline to multi-season. Three things
# change beyond "more rows":
#   1. fact_player_season regrains to athlete_id + season (currently implicitly
#      2026, keyed athlete_id + team_id only)
#   2. dim_teams becomes dim_team_season — the current 15-team snapshot is wrong
#      for any season before 2025 (GS joined 2025; TOR/POR are 2026 expansion)
#   3. dim_season carries derived game counts + an anomaly flag, so the app can
#      mark seasons that aren't comparable rather than silently mixing them
# =============================================================================

library(wehoop)
library(dplyr)
library(tidyr)
library(readr)

SEASONS <- 2020:2026
OUT     <- "data/csv"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# --- validation gate (project convention: check key ID columns, not just nrow) --
validate_materialised <- function(df, name, key_cols) {
  stopifnot(is.data.frame(df))
  if (nrow(df) == 0) stop(name, ": zero rows")
  for (k in key_cols) {
    if (!k %in% names(df)) stop(name, ": missing key column '", k, "'")
    if (all(is.na(df[[k]]))) stop(name, ": key column '", k, "' is entirely NA ",
                                  "(Arrow-backed RDS silently returns zero-length vectors — ",
                                  "pull the .parquet sibling instead)")
  }
  message(sprintf("  %-22s %7s rows  x %2d cols  [ok]", name, format(nrow(df), big.mark = ","), ncol(df)))
  invisible(df)
}

message("Pulling ", min(SEASONS), "-", max(SEASONS), " ...")

player_box <- load_wnba_player_box(seasons = SEASONS) |>
  validate_materialised("player_box", c("game_id", "athlete_id", "season"))

team_box <- load_wnba_team_box(seasons = SEASONS) |>
  validate_materialised("team_box", c("game_id", "team_id", "season"))

sched <- load_wnba_schedule(seasons = SEASONS) |>
  validate_materialised("schedule", c("game_id", "season"))

# =============================================================================
# dim_season — derived, not asserted. Season length is computed from the data
# so nobody has to remember that 2020 was 22 games and 2023 was 40.
# =============================================================================
dim_season <- team_box |>
  filter(season_type == 2) |>                       # regular season only
  group_by(season) |>
  summarise(
    teams          = n_distinct(team_id),
    games          = n_distinct(game_id),
    games_per_team = round(n() / n_distinct(team_id), 1),
    first_game     = min(game_date, na.rm = TRUE),
    last_game      = max(game_date, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    # 2020 was played at IMG Academy in Bradenton: no travel, no home courts,
    # no crowds, ~22 games. Flag it rather than let it sit unmarked next to a
    # 44-game season in an all-time leaderboard.
    is_anomalous = season == 2020,
    note = if_else(season == 2020,
                   "Bubble season at Bradenton — no travel or home courts",
                   NA_character_)
  )

validate_materialised(dim_season, "dim_season", "season")
print(dim_season, n = Inf)

# =============================================================================
# dim_team_season — which clubs actually existed in each season.
# Derived from the box scores; never from the current dim_teams snapshot.
# =============================================================================
dim_team_season <- team_box |>
  filter(season_type == 2) |>
  distinct(season, team_id, team_display_name, team_abbreviation,
           team_color, team_alternate_color) |>
  arrange(season, team_display_name)

validate_materialised(dim_team_season, "dim_team_season", c("season", "team_id"))

dim_team_season |> count(season, name = "clubs") |> print(n = Inf)

# =============================================================================
# fact_player_season — regrained to athlete_id + season.
#
# Trades: a player traded mid-season has rows under two team_ids. Totals sum
# across the whole season; primary_team_id is whoever they played the most
# games for. Keep stint detail separately if the app ever needs "with DAL /
# after trade" splits — don't bake that decision into this grain.
# =============================================================================
played <- player_box |>
  filter(season_type == 2, did_not_play == FALSE)   # NOT active == TRUE — active
                                                    # is unreliable as a "played" flag

primary_team <- played |>
  count(athlete_id, season, team_id, name = "gp_with_team") |>
  group_by(athlete_id, season) |>
  slice_max(gp_with_team, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(athlete_id, season, primary_team_id = team_id)

fact_player_season <- played |>
  group_by(athlete_id, season) |>
  summarise(
    athlete_display_name = last(athlete_display_name),
    position             = last(athlete_position_abbreviation),
    teams_played_for     = n_distinct(team_id),
    games_played         = n(),
    minutes_total        = sum(minutes, na.rm = TRUE),
    points_total         = sum(points, na.rm = TRUE),
    rebounds_total       = sum(rebounds, na.rm = TRUE),
    assists_total        = sum(assists, na.rm = TRUE),
    steals_total         = sum(steals, na.rm = TRUE),
    blocks_total         = sum(blocks, na.rm = TRUE),
    turnovers_total      = sum(turnovers, na.rm = TRUE),
    fgm = sum(field_goals_made, na.rm = TRUE),
    fga = sum(field_goals_attempted, na.rm = TRUE),
    tpm = sum(three_point_field_goals_made, na.rm = TRUE),
    tpa = sum(three_point_field_goals_attempted, na.rm = TRUE),
    ftm = sum(free_throws_made, na.rm = TRUE),
    fta = sum(free_throws_attempted, na.rm = TRUE),
    .groups = "drop"
  ) |>
  left_join(primary_team, by = c("athlete_id", "season")) |>
  mutate(
    mpg     = round(minutes_total / games_played, 1),
    ppg     = round(points_total  / games_played, 1),
    rpg     = round(rebounds_total / games_played, 1),
    apg     = round(assists_total / games_played, 1),
    fg_pct  = round(fgm / fga, 3),
    tp_pct  = round(tpm / tpa, 3),
    ft_pct  = round(ftm / fta, 3),
    ts_pct  = round(points_total / (2 * (fga + 0.44 * fta)), 3),
    efg_pct = round((fgm + 0.5 * tpm) / fga, 3)
  )

validate_materialised(fact_player_season, "fact_player_season", c("athlete_id", "season"))

# --- career arc: the reason any of this is worth doing ------------------------
# One row per player per season is exactly what a career sparkline needs.
career_check <- fact_player_season |>
  filter(games_played >= 10) |>
  count(athlete_id, name = "seasons") |>
  filter(seasons >= 5)
message("Players with 5+ qualifying seasons in range: ", nrow(career_check))

# --- sanity: rate stats should be comparable, totals should NOT --------------
fact_player_season |>
  filter(games_played >= 10) |>
  group_by(season) |>
  summarise(
    lg_ppg      = round(mean(ppg), 1),
    top_ppg     = round(max(ppg), 1),
    top_pts_tot = max(points_total),      # expect 2020 to look low — short season
    .groups = "drop"
  ) |>
  left_join(select(dim_season, season, games_per_team, is_anomalous), by = "season") |>
  print(n = Inf)

# =============================================================================
# fact_team_season — regular-season record per team per season (W-L, PF, PA).
# From team_box (reliable for COMPLETED seasons; the current season is owned by
# the daily pipeline and dropped downstream, so a lagging team_box can't hurt).
# =============================================================================
# Read a column by the first matching candidate name from THIS frame (ESPN's
# team_box column names drift between seasons).
getcol <- function(df, cands, default = NA) {
  for (n in cands) if (n %in% names(df)) return(df[[n]])
  rep(default, nrow(df))
}
reg <- team_box |> filter(season_type == 2)
tb2 <- tibble(
  season  = reg$season,
  team_id = as.character(reg$team_id),
  ts = suppressWarnings(as.numeric(getcol(reg, "team_score"))),
  os = suppressWarnings(as.numeric(getcol(reg, c("opponent_team_score", "opp_team_score"))))
) |> filter(!is.na(ts), !is.na(os))

fact_team_season <- tb2 |>
  group_by(season, team_id) |>
  summarise(
    wins        = sum(ts > os),
    losses      = sum(ts < os),
    ppg_for     = round(mean(ts), 1),
    ppg_against = round(mean(os), 1),
    .groups = "drop"
  ) |>
  mutate(win_pct = round(wins / pmax(wins + losses, 1), 3)) |>
  select(season, team_id, wins, losses, win_pct, ppg_for, ppg_against)

validate_materialised(fact_team_season, "fact_team_season", c("season", "team_id"))

# =============================================================================
# fact_team_playoff — a finish label per team per season, derived from playoff
# games (season_type == 3). Rounds are inferred from SERIES WON: a team that
# wins N playoff series has reached round N+1. In the modern 3-round bracket that
# maps 0/1/2 series won -> First round / Semifinals / Finals; the winner of the
# season's final game is the Champion. Coarser but reliable years still yield a
# correct champion/runner-up. Everything is logged so the derivation can be
# eyeballed in CI; teams with no playoff games simply get no row (app shows "—").
# =============================================================================
fact_team_playoff <- tryCatch({
  pos <- team_box |> filter(season_type == 3)
  if (nrow(pos) == 0) stop("no playoff games in range")
  po <- tibble(
    season = pos$season,
    tid = as.character(pos$team_id),
    oid = as.character(getcol(pos, c("opponent_team_id", "opp_team_id"))),
    ts  = suppressWarnings(as.numeric(getcol(pos, "team_score"))),
    os  = suppressWarnings(as.numeric(getcol(pos, c("opponent_team_score", "opp_team_score")))),
    gd  = as.character(getcol(pos, "game_date"))
  ) |> filter(!is.na(ts), !is.na(os))

  # series won: majority of games vs a given opponent within a season
  series <- po |>
    group_by(season, tid, oid) |>
    summarise(w = sum(ts > os), g = n(), .groups = "drop") |>
    mutate(won_series = w > (g - w))
  swon <- series |> group_by(season, tid) |>
    summarise(series_won = sum(won_series), .groups = "drop")

  # Champion & runner-up = winner & loser of each season's LAST playoff game.
  # Taking the finalists straight from the final game is reliable every year
  # (unlike series-won, which undercounts in bye years like 2020/2021). Series
  # won then splits the rest: 1 series won -> Semifinals, 0 -> First round
  # (exact for the modern no-bye bracket; a bye-year team that got a first-round
  # bye and lost its opener can under-label, but the champion/finalist are right).
  last_games <- po |> group_by(season) |> filter(gd == max(gd)) |> ungroup()
  champ  <- last_games |> filter(ts > os) |> group_by(season) |> slice_head(n = 1) |>
    ungroup() |> transmute(season, champ_tid = tid)
  runner <- last_games |> filter(os > ts) |> group_by(season) |> slice_head(n = 1) |>
    ungroup() |> transmute(season, runner_tid = tid)

  # Semifinalists (beaten in the round before the final): among non-finalist
  # playoff teams, the two whose LAST game is latest. Rounds are chronologically
  # separated, so this is robust across the differing 2020/2021 vs 2022+ formats
  # and immune to byes (series-won undercounts a team that got a first-round bye).
  last_dates <- po |> group_by(season, tid) |> summarise(last_gd = max(gd), .groups = "drop")
  finalists  <- dplyr::bind_rows(dplyr::rename(champ, tid = champ_tid),
                                 dplyr::rename(runner, tid = runner_tid))
  semis <- last_dates |>
    dplyr::anti_join(finalists, by = c("season", "tid")) |>
    group_by(season) |> slice_max(last_gd, n = 2, with_ties = FALSE) |> ungroup() |>
    transmute(season, tid, is_semi = TRUE)

  swon |>
    left_join(champ,  by = "season") |>
    left_join(runner, by = "season") |>
    left_join(semis,  by = c("season", "tid")) |>
    mutate(result = dplyr::case_when(
      tid == champ_tid  ~ "Champions",
      tid == runner_tid ~ "Finals",
      !is.na(is_semi)   ~ "Semifinals",
      TRUE              ~ "First round"
    )) |>
    transmute(season, team_id = tid, result)
}, error = function(e) {
  message("  playoff finishes skipped: ", conditionMessage(e))
  tibble(season = integer(), team_id = character(), result = character())
})

message("Playoff finishes by season:")
if (nrow(fact_team_playoff) > 0) {
  abbr_lookup <- dim_team_season |>
    transmute(season, team_id = as.character(team_id), team_abbreviation) |>
    distinct()
  fact_team_playoff |>
    left_join(abbr_lookup, by = c("season", "team_id")) |>
    arrange(season, result) |> print(n = Inf)
}

# =============================================================================
# History-specific filenames so the one-off backfill NEVER clobbers the daily
# single-season CSVs (fetch_wnba.R owns fact_player_season.csv; build_data.py
# reads *_hist.csv for the multi-season history and preserves it between runs).
write_csv(dim_season,          file.path(OUT, "dim_season.csv"))
write_csv(dim_team_season,     file.path(OUT, "dim_team_season.csv"))
write_csv(fact_player_season,  file.path(OUT, "fact_player_season_hist.csv"))
write_csv(fact_team_season,    file.path(OUT, "fact_team_season.csv"))
write_csv(fact_team_playoff,   file.path(OUT, "fact_team_playoff.csv"))

message("\nDone. History written to *_hist.csv / fact_team_season.csv / ",
        "fact_team_playoff.csv. dim_teams (current snapshot) stays valid only ",
        "for the latest season — historical views use dim_team_season.")
