# =============================================================================
# Courtside — weekly shot-chart fetch. Play-by-play -> the two CSVs the shot
# fingerprint needs:
#     fact_pbp.csv        (shooting_play, shot_zone, athlete_id_1, shot_result, type_text)
#     fact_player_box.csv (field_goals_attempted — build_data's reconciliation gate)
#
# The 5 shot zones are NOT in the raw feed; the original pipeline derived them
# from coordinates. We reconstruct that here, but the coordinate system wehoop
# returns isn't documented, so instead of hardcoding it we AUTO-CALIBRATE:
#   - hoop location  = where layups/dunks cluster
#   - court scale    = solved so the median 3-pointer sits ~23.75 ft out
# 3-pointers are detected from the play text ("three point"), which is reliable
# regardless of geometry. Everything is logged so a miscalibration is obvious,
# and build_data's FGA reconciliation + the zone-sanity smoke checks block a bad
# commit. See CLAUDE.md ("Shot chart") and the known-good league FG% by zone:
#   Restricted 62.4 · Paint 40.4 · Mid 37.3 · Corner3 34.8 · AboveBreak3 32.6
#
# Run:  Rscript scripts/fetch_shots.R      (WNBA_SEASON env overrides the year)
# =============================================================================
suppressPackageStartupMessages({
  library(wehoop); library(dplyr); library(readr); library(bit64)
})
options(dplyr.summarise.inform = FALSE)

SEASON <- as.integer(Sys.getenv("WNBA_SEASON", unset = format(Sys.Date(), "%Y")))
OUT <- "data/csv"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
num <- function(x) suppressWarnings(as.numeric(x))
regular <- function(df) {
  if (!"season_type" %in% names(df)) return(df)
  r <- dplyr::filter(df, season_type == 2)
  if (nrow(r) > 0) r else df
}
chr <- function(x) as.character(x)

message("Fetching WNBA play-by-play, season ", SEASON, " ...")
pbp <- regular(load_wnba_pbp(seasons = SEASON))
message("pbp rows: ", nrow(pbp))
message("pbp cols: ", paste(names(pbp), collapse = ", "))
stopifnot(nrow(pbp) > 0)

txt   <- function(nm) if (nm %in% names(pbp)) as.character(pbp[[nm]]) else rep("", nrow(pbp))
pbp$.text      <- txt("text")
pbp$.type      <- txt("type_text")
pbp$.x         <- num(if ("coordinate_x" %in% names(pbp)) pbp$coordinate_x else NA)
pbp$.y         <- num(if ("coordinate_y" %in% names(pbp)) pbp$coordinate_y else NA)
pbp$.made      <- if ("scoring_play" %in% names(pbp)) as.logical(pbp$scoring_play) else grepl("makes", pbp$.text, ignore.case = TRUE)
pbp$.shooter   <- chr(if ("athlete_id_1" %in% names(pbp)) pbp$athlete_id_1 else NA)

sh <- pbp |> filter(shooting_play == TRUE)
message("shooting plays: ", nrow(sh))

is_ft <- grepl("free throw", sh$.text, ignore.case = TRUE) | grepl("free throw", sh$.type, ignore.case = TRUE)
is_3  <- grepl("three", sh$.text, ignore.case = TRUE) | grepl("three", sh$.type, ignore.case = TRUE)
is_layup <- grepl("layup|dunk|tip shot|putback|alley", sh$.type, ignore.case = TRUE) |
            grepl("layup|dunk|tip shot|putback|alley", sh$.text, ignore.case = TRUE)

fga <- sh[!is_ft, ]                          # field-goal attempts only
f3  <- is_3[!is_ft]; flay <- is_layup[!is_ft]
x <- fga$.x; y <- fga$.y

# --- auto-calibration ------------------------------------------------------
CX <- median(x, na.rm = TRUE)                # hoop x = centre of the shot cloud
HY <- median(y[flay], na.rm = TRUE)          # hoop y = where layups happen
if (!is.finite(HY)) HY <- min(y, na.rm = TRUE)
rawd <- sqrt((x - CX)^2 + (y - HY)^2)        # distance in raw coordinate units
raw3 <- median(rawd[f3], na.rm = TRUE)       # median 3-pointer, raw units
UNIT <- if (is.finite(raw3) && raw3 > 0) 23.75 / raw3 else 1
dist <- rawd * UNIT                          # distance in feet
sideft <- abs(x - CX) * UNIT                 # horizontal offset in feet
baseft <- (y - HY) * UNIT                    # distance up-court in feet

message(sprintf("calibration — CX=%.1f HY=%.1f raw3=%.1f UNIT=%.4f  (layup med dist=%.1fft)",
                CX, HY, raw3, UNIT, median(dist[flay], na.rm = TRUE)))
message(sprintf("coordinate_x [%.1f, %.1f]  coordinate_y [%.1f, %.1f]  NA-coord FGA=%d",
                min(x, na.rm = TRUE), max(x, na.rm = TRUE),
                min(y, na.rm = TRUE), max(y, na.rm = TRUE), sum(is.na(x))))

# --- classify every FGA into exactly one of the five zones -----------------
zone <- character(nrow(fga))
for (i in seq_len(nrow(fga))) {
  if (f3[i]) {
    zone[i] <- if (!is.na(sideft[i]) && sideft[i] >= 18 &&
                   (is.na(baseft[i]) || baseft[i] <= 9)) "Corner 3" else "Above the Break 3"
  } else if (is.na(dist[i])) {
    zone[i] <- if (flay[i]) "Restricted Area" else "Mid-Range"   # coord-less fallback
  } else if (dist[i] <= 4) {
    zone[i] <- "Restricted Area"
  } else if (sideft[i] <= 8 && dist[i] <= 19) {
    zone[i] <- "In the Paint"
  } else {
    zone[i] <- "Mid-Range"
  }
}

fact_pbp <- tibble(
  shooting_play = "TRUE",
  shot_zone     = zone,
  athlete_id_1  = fga$.shooter,
  shot_result   = ifelse(fga$.made, "Made", "Missed"),
  type_text     = fga$.type
)
write_csv(fact_pbp, file.path(OUT, "fact_pbp.csv"), na = "")
message("  fact_pbp.csv       ", nrow(fact_pbp), " FG attempts")

# league FG% by zone — eyeball against the known-good numbers above
ZONES <- c("Restricted Area", "In the Paint", "Mid-Range", "Corner 3", "Above the Break 3")
zf <- fact_pbp |>
  group_by(shot_zone) |>
  summarise(n = n(), fg = round(100 * mean(shot_result == "Made"), 1), .groups = "drop")
for (z in ZONES) {
  r <- zf[zf$shot_zone == z, ]
  message(sprintf("    %-18s n=%-5d FG%%=%s", z, if (nrow(r)) r$n else 0,
                  if (nrow(r)) r$fg else "-"))
}

# --- fact_player_box.csv: FGA totals for build_data's reconciliation gate --
player_box <- load_wnba_player_box(seasons = SEASON)
pbx <- regular(player_box)
fact_player_box <- tibble(
  athlete_id             = chr(pbx$athlete_id),
  game_id                = chr(pbx$game_id),
  field_goals_attempted  = num(pbx$field_goals_attempted)
)
write_csv(fact_player_box, file.path(OUT, "fact_player_box.csv"), na = "")
message("  fact_player_box.csv  ", nrow(fact_player_box), " rows  (box FGA=",
        sum(fact_player_box$field_goals_attempted, na.rm = TRUE), ")")

message("\nDone. build_data.py rebuilds the shot fingerprint from fact_pbp.csv ",
        "and reconciles the count against box-score FGA.")
