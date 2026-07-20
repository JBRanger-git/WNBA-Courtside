# =============================================================================
# Courtside — WNBA news fetch (ESPN). Writes data/csv/dim_news.csv with a real
# story URL per headline so the app's "Wire" links out to the full article.
#
# FULLY DEFENSIVE: any failure (network, schema drift, empty feed) logs and
# writes NOTHING, so build_data.py falls back to PRESERVING the previous news
# rather than blanking the Wire. "A blank field beats a wrong one" (CLAUDE.md).
# The script always exits 0 so it can never fail the daily data refresh.
#
# Columns written: headline, byline, published_date, team_id, link
#   team_id is ESPN's team id (same id space as player_box team_id); build_data.py
#   maps it to an abbreviation. Blank when the story isn't tagged to one team.
#
# Run:  Rscript scripts/fetch_news.R
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(readr) })

OUT <- "data/csv"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
URL <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/news?limit=50"

# First non-null scalar, else default. Guards the ragged ESPN schema.
g <- function(x, default = "")
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x[[1]]))) default else as.character(x[[1]])

# The ESPN team id of the first team-tagged category, if any.
first_team_id <- function(cats) {
  if (is.null(cats)) return("")
  for (c in cats) {
    if (!is.null(c$type) && identical(c$type, "team")) {
      if (!is.null(c$teamId))                        return(as.character(c$teamId))
      if (!is.null(c$team) && !is.null(c$team$id))   return(as.character(c$team$id))
    }
  }
  ""
}

res <- tryCatch(
  jsonlite::fromJSON(URL, simplifyVector = FALSE),
  error = function(e) { message("  news fetch failed: ", conditionMessage(e)); NULL }
)

arts <- if (!is.null(res)) res$articles else NULL
if (is.null(arts) || length(arts) == 0) {
  message("  no news returned — leaving dim_news.csv absent (build_data.py preserves prior news)")
  quit(save = "no", status = 0)
}

rows <- lapply(arts, function(a) tryCatch(
  data.frame(
    headline       = g(a$headline),
    byline         = g(a$byline),
    published_date = g(a$published),
    team_id        = first_team_id(a$categories),
    link           = g(a$links$web$href),
    stringsAsFactors = FALSE
  ),
  error = function(e) NULL
))
df <- do.call(rbind, Filter(Negate(is.null), rows))

if (is.null(df) || nrow(df) == 0) {
  message("  no parseable stories — leaving dim_news.csv absent")
  quit(save = "no", status = 0)
}

# Keep only real, linkable stories; newest first; cap the file (build_data takes 5).
df <- df[nzchar(df$headline) & nzchar(df$link), , drop = FALSE]
df <- df[order(df$published_date, decreasing = TRUE), , drop = FALSE]
df <- head(df, 25)

if (nrow(df) == 0) {
  message("  no linkable stories — leaving dim_news.csv absent")
  quit(save = "no", status = 0)
}

write_csv(df, file.path(OUT, "dim_news.csv"), na = "")
message("  dim_news           ", nrow(df), " stories (", sum(nzchar(df$team_id)), " team-tagged)")
