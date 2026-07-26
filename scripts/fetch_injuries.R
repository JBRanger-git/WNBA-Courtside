# =============================================================================
# Courtside — WNBA injury status (ESPN). Writes data/csv/dim_injuries.csv: one
# row per player currently on an injury report (Out / Day-To-Day / Injured
# Reserve / etc.), so the team roster and player page can show it.
#
# CORRECTION (see git history — took two rounds of CI diagnostics, not more
# guessing, to nail down): wehoop's espn_wnba_injuries() doesn't exist in the
# installed package. This calls ESPN's JSON API directly instead — the same
# technique fetch_news.R/fetch_lines.R already use for their own endpoints
# (site.api.espn.com), not a new class of request. The real response shape
# (confirmed from a live CI dump of the first player entry):
#   res$injuries = [ {id, displayName, injuries: [ {id, longComment,
#     shortComment, status, date, athlete: {firstName, lastName, displayName,
#     links: [...], ...}, source, type, details} , ... ] }, ... ]
# Two gotchas that guessing got wrong the first time:
#   - the team's own id/name are directly on the entry (team_entry$id), NOT
#     nested under a `team` sub-object.
#   - there is no numeric athlete id field at all — the ESPN athlete id only
#     exists embedded in the player-card URL under athlete$links (e.g.
#     ".../id/5105740/indya-nivar"), so it has to be regex-extracted.
#   - `status` (top-level, e.g. "Out") IS already a plain string — don't
#     confuse it with `details$type` (a reason category like "Coach's
#     Decision") or `type$name` (an internal code like "INJURY_STATUS_OUT").
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

# The numeric ESPN athlete id isn't a field on `athlete` — pull it out of the
# first link whose href contains "/id/<digits>/" (the player-card URL always
# has this form).
athlete_id_from_links <- function(links) {
  if (is.null(links) || length(links) == 0) return("")
  for (l in links) {
    href <- l$href
    if (is.null(href)) next
    m <- regmatches(href, regexpr("/id/([0-9]+)/", href))
    if (length(m) && nzchar(m)) return(gsub("[^0-9]", "", m))
  }
  ""
}

res <- tryCatch(
  jsonlite::fromJSON(URL, simplifyVector = FALSE),
  error = function(e) { message("  injuries fetch failed: ", conditionMessage(e)); NULL }
)

if (is.null(res)) { quit(save = "no", status = 0) }

teams <- res$injuries
if (is.null(teams) || length(teams) == 0) {
  # DIAGNOSTIC: the endpoint responded but not with the shape expected — log
  # the top-level keys so a schema change can be read off one CI log instead
  # of guessing blind.
  message("  no `injuries` array in response — top-level keys: ",
          paste(names(res), collapse = ", "))
  quit(save = "no", status = 0)
}

rows <- list()
for (team_entry in teams) {
  tid <- g(team_entry$id)   # flat on the entry, not team_entry$team$id
  plist <- team_entry$injuries
  if (is.null(plist) || length(plist) == 0) next
  for (p in plist) {
    rows[[length(rows) + 1]] <- data.frame(
      athlete_id   = athlete_id_from_links(p$athlete$links),
      athlete_name = g(p$athlete$displayName),
      team_id      = tid,
      status       = g(p$status),   # plain string, e.g. "Out"
      note         = g(if (nzchar(g(p$shortComment))) p$shortComment else p$longComment),
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
