suppressPackageStartupMessages({ library(jsonlite) })
gid <- "401857086"
url <- paste0("https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/summary?event=", gid)
sb <- fromJSON(url, simplifyVector = FALSE)
bx <- sb$boxscore
message("boxscore top-level names: ", paste(names(bx), collapse = ", "))
teams <- bx$teams
message("num teams: ", length(teams))
t1 <- teams[[1]]
message("team[1] names: ", paste(names(t1), collapse = ", "))
message("team[1]$team$displayName: ", t1$team$displayName)
stats <- t1$statistics
message("num stat entries: ", length(stats))
for (s in stats) {
  message("  name=", s$name, " | label=", s$label, " | displayValue=", s$displayValue)
}
# Also check competition-level fields (leadChanges etc often live here, not per-team)
comp <- sb$header$competitions[[1]]
message("header competition names: ", paste(names(comp), collapse = ", "))
