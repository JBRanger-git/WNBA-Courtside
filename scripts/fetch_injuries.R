# =============================================================================
# Courtside — WNBA injury status (ESPN). Writes data/csv/dim_injuries.csv: one
# row per player currently on an injury report (Out / Day-To-Day / Injured
# Reserve / etc.), so the team roster and player page can show it.
#
# CORRECTION (see git history): this originally called wehoop's
# espn_wnba_injuries(), which turned out not to exist in the installed
# package — confirmed via a CI diagnostic (ls("package:wehoop") had zero
# "injur" matches), not by more guessing. This version calls ESPN's JSON API
# directly instead, the same technique fetch_news.R and fetch_lines.R already
# use for their own endpoints (site.api.espn.com) — same standing, not a new
# class of request. The exact injuries endpoint/shape for WNBA specifically
# isn't confirmed yet either, so this is written defensively with a diagnostic
# dump on any parse failure — the daily refresh can never break on this, and a
# wrong guess degrades to "no injuries" instead of silently misreading data.
#
# FULLY DEFENSIVE: any failure (network, 404, schema drift, empty feed) logs
# and writes NOTHING, so build_data.py falls back to PRESERVING whatever
# injury list it last had. "A blank field beats a wrong one" (CLAUDE.md).
# Always exits 0 — this can never fail the daily refresh.
#
# Run:  Rscript scripts/fetch_injuries.R
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(readr) })

OUT <- "data/csv"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
URL <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/injuries"

g <- function(x, default = "")
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x[[1]]))) default else as.character(x[[1]])

res <- tryCatch(
  jsonlite::fromJSON(URL, simplifyVector = FALSE),
  error = function(e) { message("  injuries fetch failed: ", conditionMessage(e)); NULL }
)

if (is.null(res)) { quit(save = "no", status = 0) }

teams <- res$injuries   # expected shape: [{team:{id,...}, injuries:[{athlete:{id,displayName},status,details:{type,returnDate},...}]}]
if (is.null(teams) || length(teams) == 0) {
  # DIAGNOSTIC: the endpoint responded but not with the shape we expected —
  # log the top-level keys so a wrong guess can be fixed from one CI log
  # instead of another round of blind guessing.
  message("  no `injuries` array in response — top-level keys: ",
          paste(names(res), collapse = ", "))
  quit(save = "no", status = 0)
}

rows <- list()
for (team_entry in teams) {
  tid <- g(team_entry$team$id)
  plist <- team_entry$injuries
  if (is.null(plist) || length(plist) == 0) next
  for (p in plist) {
    rows[[length(rows) + 1]] <- data.frame(
      athlete_id   = g(p$athlete$id),
      athlete_name = g(p$athlete$displayName),
      team_id      = tid,
      status       = g(p$status),
      note         = g(if (!is.null(p$details)) p$details$type else p$longComment),
      updated      = g(p$date),
      stringsAsFactors = FALSE
    )
  }
}

if (length(rows) == 0) {
  message("  0 player rows inside the injuries payload (", length(teams), " team entries) — ",
          "leaving dim_injuries.csv absent")
  quit(save = "no", status = 0)
}

df <- do.call(rbind, rows)
df <- df[nzchar(df$athlete_id) & nzchar(df$status), , drop = FALSE]
df <- df[!duplicated(df$athlete_id), , drop = FALSE]

if (nrow(df) == 0) {
  message("  no usable injury rows — leaving dim_injuries.csv absent")
  quit(save = "no", status = 0)
}

write_csv(df, file.path(OUT, "dim_injuries.csv"), na = "")
message("  dim_injuries       ", nrow(df), " player(s) on the report across ", length(teams), " team(s)")
