# =============================================================================
# Courtside — WNBA injury status (ESPN, via wehoop). Writes
# data/csv/dim_injuries.csv: one row per player currently on an injury report
# (Out / Day-To-Day / Injured Reserve / etc.), so the team roster and player
# page can show it.
#
# Same standing as fetch_news.R / fetch_lines.R: espn_wnba_injuries() is a
# documented wehoop wrapper over the same site.api.espn.com family those
# scripts already call directly, run once in this same daily batch — not a
# new class of request, just one more field in the existing daily pull.
#
# FULLY DEFENSIVE: any failure (network, schema drift, empty feed, wehoop
# quirk) logs and writes NOTHING, so build_data.py falls back to PRESERVING
# whatever injury list it last had (or blank if none yet) rather than
# guessing. "A blank field beats a wrong one" (CLAUDE.md). Always exits 0 —
# this can never fail the daily refresh.
#
# Run:  Rscript scripts/fetch_injuries.R      (WNBA_SEASON env overrides the year)
# =============================================================================
suppressPackageStartupMessages({ library(wehoop); library(readr) })

OUT <- "data/csv"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SEASON <- as.integer(Sys.getenv("WNBA_SEASON", unset = format(Sys.Date(), "%Y")))

# Pick the first present column among candidate names — ESPN's injury payload
# field names aren't pinned down by the wehoop docs, so don't bet on one guess.
pick_any <- function(df, cands, default = NA) {
  for (n in cands) if (n %in% names(df)) return(df[[n]])
  rep(default, nrow(df))
}
chr <- function(x) if (is.null(x)) character(0) else as.character(x)

inj <- tryCatch(espn_wnba_injuries(season = SEASON), error = function(e) {
  message("  injuries fetch failed: ", conditionMessage(e)); NULL
})

if (is.null(inj) || !is.data.frame(inj) || nrow(inj) == 0) {
  message("  no injuries returned — leaving dim_injuries.csv absent ",
          "(build_data.py preserves the prior list)")
  quit(save = "no", status = 0)
}

df <- tryCatch({
  data.frame(
    athlete_id   = chr(pick_any(inj, c("athlete_id", "id"))),
    athlete_name = chr(pick_any(inj, c("athlete_display_name", "full_name", "display_name", "athlete_name"), "")),
    team_id      = chr(pick_any(inj, c("team_id"))),
    status       = chr(pick_any(inj, c("status", "type", "injury_status"), "")),
    note         = chr(pick_any(inj, c("short_comment", "long_comment", "comment", "details"), "")),
    updated      = chr(pick_any(inj, c("date", "updated_date"), "")),
    stringsAsFactors = FALSE
  )
}, error = function(e) { message("  injuries: unexpected shape — ", conditionMessage(e)); NULL })

if (is.null(df)) { quit(save = "no", status = 0) }

# Keep only rows we can actually attach to a player and a status label.
df <- df[nzchar(df$athlete_id) & !is.na(df$athlete_id) & nzchar(df$status), , drop = FALSE]
df <- df[!duplicated(df$athlete_id), , drop = FALSE]

if (nrow(df) == 0) {
  message("  no usable injury rows — leaving dim_injuries.csv absent")
  quit(save = "no", status = 0)
}

write_csv(df, file.path(OUT, "dim_injuries.csv"), na = "")
message("  dim_injuries       ", nrow(df), " player(s) on the report")
