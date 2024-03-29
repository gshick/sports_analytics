
# Objective: Scrape the indivdual game results for the top 5 leaders 
# in career points in the NBA
#########################################################################

library(rvest)
library(dplyr)
library(ggplot2)
library(data.table)
library(scales)
library(plotly)
library(ggimage)

# Create tibbles for each player
#########################################################################
kareem <- tibble(
  player_name = 'Kareem Abdul-Jabbar',
  player_id = 'abdulka01',
  initial = 'a',
  year = 1970:1989)

malone <- tibble(
  player_name = 'Karl Malone',
  player_id = 'malonka01',
  initial = 'm',
  year = 1986:2004)

lebron <- tibble(
  player_name = 'LeBron James',
  player_id = 'jamesle01',
  initial = 'j',
  year = 2004:2021)

kobe <- tibble(
  player_name = 'Kobe Bryant',
  player_id = 'bryanko01',
  initial = 'b',
  year = 1997:2016)

jordan <- tibble(
  player_name = 'Michael Jordan',
  player_id = 'jordami01',
  initial = 'j',
  year = 1985:2003)

# Create df & URLs of players to be scraped
#########################################################################

players = bind_rows(kareem, malone, lebron, kobe, jordan)

urls <- sprintf("https://www.basketball-reference.com/players/%s/%s/gamelog/%s", 
                players$initial, players$player_id, players$year)

# Stack player data in data frame
#########################################################################
output <- data_frame()

purrr::map_df(urls, ~{
  .x %>%  
    read_html() %>%
    html_nodes("#pgl_basic") %>% 
    html_table() -> tmp
    
  if(length(tmp)) {
    tmp <- tmp[[1]]
    setNames(tmp, paste0('col', seq_along(tmp))) %>%
      mutate(across(.fns = as.character)) 
  }
  else NULL
}, .id = 'playername') %>% 
  mutate(playername = players$player_name[as.numeric(playername)]) -> output

# Found a problem with Kareem's data, the column for game points changes over his career 
# as new metrics are added.  Probably a more elegant way to parse this but I took the brute 
# force approach

checks_dates = output %>% 
  filter(playername == 'Kareem Abdul-Jabbar') %>% 
  select(playername, col3,col20,col24,col25,col28) %>% 
  group_by(year(as.Date(col3))) %>% 
  summarise(min_dt=min(col3), max_dt=max(col3), col20=sum(as.numeric(col20)), 
            col24=sum(as.numeric(col24)), col25=sum(as.numeric(col25)), 
            col28=sum(as.numeric(col28)))

kareem <- output %>%
  filter(playername == 'Kareem Abdul-Jabbar') %>%
  subset(col3 != "Date") %>%
  mutate(pts = dplyr::case_when((col3 >= as.Date("1969-10-01") & col3 <= as.Date("1973-04-30")) ~ col20,
                                (col3 >= as.Date("1973-10-01") & col3 <= as.Date("1977-04-30")) ~ col24,
                                (col3 >= as.Date("1977-10-01") & col3 <= as.Date("1979-04-30")) ~ col25,
                                (col3 >= as.Date("1979-10-01") & col3 <= as.Date("1989-04-30")) ~ col28)) %>% 
  rename(date = col3) %>%
  select(playername,date,pts) %>% 
  mutate(actv = ifelse(pts=='Inactive',0,1), pts = ifelse(pts=='Inactive',0,pts)) %>% 
  mutate(g_pts = as.numeric(pts))

# Clean out header values generated by scraping multiple pages
# Only keep columns of interest
# Fix games with no points or character values
#########################################################################
all_others <- output %>%
  filter(playername != 'Kareem Abdul-Jabbar') %>%
  subset(col3 != "Date") %>%
  rename(date = col3) %>%
  mutate(actv = ifelse(col28=='Inactive',0,1), pts = as.numeric(as.character(col28))) %>%
  select(playername,date,pts,actv) %>% 
  mutate(g_pts = if_else(is.na(pts),0,pts))
  
clean = rbind(kareem, all_others)

# Add cumulative career points & games
#########################################################################
career_pts <- data.table(clean, key = "playername")
career_pts[, c_pts := cumsum(g_pts), by = key(career_pts)]
career_pts[, c_gm := cumsum(actv), by = key(career_pts)]

# Convert game date to date format
career_pts$g_date = as.Date(career_pts$date)
career_pts$image = "https://www.basketball-reference.com/req/202105076/images/players/bryanko01.jpg"

# Add images for the last data point
image = career_pts %>% 
  group_by(playername) %>% 
  summarise(g_date = max(g_date)) %>% 
  mutate(image = "https://www.basketball-reference.com/req/202105076/images/players/bryanko01.jpg")

career_pts = merge(x = career_pts, y = image, by.x = c("playername", "g_date"),
                                                       by.y = c("playername", "g_date"),all.x = TRUE)

           # case_when(playername == "Kobe Bryant" ~ "" ))

# Check Stats
#########################################################################
check = career_pts %>% 
  group_by(playername) %>% 
  summarise(c_pts = max(c_pts), c_games = max(c_gm), l_game = max(g_date))

# Export data for later use
write.csv(career_pts,"C:\\Users\\gregs\\Hugo\\bin\\greg_shick\\content\\post\\NBA_1\\nba_data.csv", row.names = FALSE)

# Import data 
career_pts = read.csv("C:\\Users\\gregs\\Hugo\\bin\\greg_shick\\content\\post\\NBA_1\\nba_data.csv")

# Create plot
#########################################################################
p = ggplot(career_pts, aes(x=c_gm, y=c_pts, color=playername)) +
    geom_line() +
    geom_image(aes(image=career_pts$image),size=0.05) +
    scale_size_identity() +
    #geom_point(size=1) +
    scale_x_continuous(expand = c(0, 0), label=scales::number_format(big.mark=','), breaks=scales::breaks_pretty(n=10)) +
    scale_y_continuous(expand = c(0, 0), label=scales::number_format(big.mark=','), breaks=scales::breaks_pretty(n=10)) +
    theme_classic() +
    labs(x = "Game #", y = "Career Points") +
    theme(legend.title = element_blank())

ggplotly(p)

# Checks
#########################################################################
# career_pts %>%group_by(playername) %>% summarise(max=max(csum))
# 
# career_pts %>% 
#   filter(playername == 'LeBron James') %>% 
#   group_by(playername, year(g_date)) %>% 
#   summarise(games=n_distinct(g_date), pts=sum(game_pts))

