# =============================================================================
# Courtside — per-quarter scores (linescores) for completed games, from ESPN's
# scoreboard feed. Writes data/csv/fact_game_line.csv:
#     game_id, home_away, line     (line = pipe-joined period points, "24|18|20|21")
#
# FULLY DEFENSIVE: any failure (network, schema drift) is logged and skipped, and
# the script always exits 0 — a game we can't fetch simply shows no quarter
# breakdown. build_data.py also PRESERVES previously-fetched lines and drops any
# whose quarters don't sum to the final score, so a transient miss never drops a
# game and a bad linescore never renders. "A blank field beats a wrong one."
#
# Run:  Rscript scripts/fetch_lines.R
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(dplyr); library(readr) })

OUT <- "data/csv"
tb_path <- file.path(OUT, "fact_team_box.csv")
dg_path <- file.path(OUT, "dim_games.csv")
if (!file.exists(tb_path) || !file.exists(dg_path)) {
  message("  lines: missing team-box/games csv — skipping"); quit(save = "no", status = 0)
}

tb <- suppressMessages(read_csv(tb_path, show_col_types = FALSE))
dg <- suppressMessages(read_csv(dg_path, show_col_types = FALSE))

# A game is completed iff fact_team_box has both sides (CLAUDE.md).
completed <- tb |>
  group_by(game_id) |>
  summarise(sides = n_distinct(team_home_away), .groups = "drop") |>
  filter(sides >= 2)
games <- dg |> filter(game_id %in% completed$game_id)
if (nrow(games) == 0) { message("  lines: no completed games — skipping"); quit(save = "no", status = 0) }

dates <- sort(unique(gsub("-", "", substr(as.character(games$game_date), 1, 10))))
message("  lines: fetching linescores for ", nrow(games), " completed games over ", length(dates), " date(s)")

# Period points for one competitor as a pipe-joined string, or NA if none.
get_line <- function(comp) {
  ls <- comp$linescores
  if (is.null(ls) || length(ls) == 0) return(NA_character_)
  vals <- vapply(ls, function(x) {
    v <- if (!is.null(x$value)) x$value else if (!is.null(x$displayValue)) x$displayValue else NA
    suppressWarnings(as.integer(round(as.numeric(v))))
  }, integer(1))
  if (all(is.na(vals))) return(NA_character_)
  paste(vals, collapse = "|")
}

rows <- list()
for (d in dates) {
  url <- paste0("https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/scoreboard?dates=", d, "&limit=100")
  sb <- tryCatch(jsonlite::fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
  ev <- if (!is.null(sb)) sb$events else NULL
  if (is.null(ev)) next
  for (e in ev) {
    gid   <- as.character(e$id)
    comps <- tryCatch(e$competitions[[1]]$competitors, error = function(err) NULL)
    if (is.null(comps)) next
    for (c in comps) {
      line <- get_line(c)
      if (!is.na(line) && !is.null(c$homeAway))
        rows[[length(rows) + 1]] <- data.frame(game_id = gid, home_away = c$homeAway,
                                               line = line, stringsAsFactors = FALSE)
    }
  }
  Sys.sleep(0.15)  # be polite to the endpoint
}

if (length(rows) == 0) { message("  lines: none extracted — leaving csv absent"); quit(save = "no", status = 0) }
df <- do.call(rbind, rows)
df <- df[df$game_id %in% games$game_id, , drop = FALSE]
df <- dplyr::distinct(df, game_id, home_away, .keep_all = TRUE)
write_csv(df, file.path(OUT, "fact_game_line.csv"), na = "")
message("  fact_game_line     ", nrow(df), " team-rows (", dplyr::n_distinct(df$game_id), " games)")
