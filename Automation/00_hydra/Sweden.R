rm(list=ls())
library(tidyverse)
library(readxl)
library(googlesheets4)
library(googledrive)
library(lubridate)
library(httr)

# Drive credentials
drive_auth(email = "kikepaila@gmail.com")
gs4_auth(email = "kikepaila@gmail.com")

print(paste0("Starting data retrieval for Sweden..."))

############################
# When using it daily
############################

url <- "https://www.arcgis.com/sharing/rest/content/items/b5e7488e117749c19881cce45db13f7e/data"
httr::GET(url, write_disk(tf <- tempfile(fileext = ".xlsx")))

# date from the data directly, last reported date in the sheet 'Antal per dag region'

date_f <- read_xlsx(tf, sheet = "Antal per dag region") %>% 
  pull(Statistikdatum) %>% 
  max() %>% 
  ymd()

# reading data from Montreal and last date entered 
db_drive <- read_sheet("https://docs.google.com/spreadsheets/d/1w-ynPuKT_5xZf7emTuUFp_n-PdStCyrylY6gZVQj_do/edit#gid=1079196673",
                       sheet = "database")

last_date_drive <- db_drive %>% 
  mutate(date_f = dmy(Date)) %>% 
  pull(date_f) %>% 
  max()

# process data and upload it only if the reported date is more recent than the date in Drive

if (date_f > last_date_drive){
  
  date <- paste(sprintf("%02d", day(date_f)),
                sprintf("%02d", month(date_f)),
                year(date_f), sep = ".")
  
  db_sex <- read_xlsx(tf, sheet = "Totalt antal per k�n")
  db_age <- read_xlsx(tf, sheet = "Totalt antal per �ldersgrupp")
  
  # Get data by sex
  
  db_s2 <- db_sex %>% 
    # rename(Sex = K�n,
    rename(
      Sex = starts_with("K"),
      Cases = Totalt_antal_fall,
      Deaths = Totalt_antal_avlidna
    ) %>% 
    mutate(
      Sex = case_when(Sex == "Man" ~ "m",
                      Sex == "Kvinna" ~ "f",
                      Sex == "Uppgift saknas" ~ "UNK"),
      Age = "TOT"
    ) %>% 
    select(Sex, Age, Cases, Deaths)
  
  # Get data by age
  
  db_a2 <- db_age %>% 
    rename(
      Cases = Totalt_antal_fall,
      Deaths = Totalt_antal_avlidna
      , Age = ends_with("ldersgrupp")
    ) %>% 
    # mutate(Age = str_sub(�ldersgrupp, 7, 8),
    mutate(
      Age = str_sub(Age, 7, 8),
      Age = case_when(Age == "0_" ~ "0",
                      Age == "t " ~ "UNK",
                      TRUE ~ Age),
      Sex = "b"
    ) %>% 
    select(Sex, Age, Cases, Deaths)
  
  db_all <- 
    bind_rows(db_s2, db_a2) %>% 
    gather(Cases, Deaths, key = Measure, value = Value) %>% 
    mutate(Country = "Sweden",
           Region = "All",
           Code = paste0("SE", date),
           Date = date,
           AgeInt = case_when(
             Age == "TOT" | Age == "UNK" ~ ""
             , Age == "90" ~ "15"
             , TRUE ~ "10"
           ), Metric = "Count"
    ) %>% 
    select(Country, Region, Code, Date, Sex, Age, AgeInt, Metric, Measure, Value) 
  
  ############################################
  #### uploading database to Google Drive ####
  ############################################
  sheet_append(db_all,
               ss = "https://docs.google.com/spreadsheets/d/1w-ynPuKT_5xZf7emTuUFp_n-PdStCyrylY6gZVQj_do/edit#gid=1079196673",
               sheet = "database")
  
  ############################################
  #### uploading metadata to Google Drive ####
  ############################################
  sheet_name <- paste0("SE", date, "cases&deaths")
  
  meta <- drive_create(sheet_name,
                       path = "https://drive.google.com/drive/folders/1194c1EJL1PEYJr8VBpbcoWJ5Bq7LZ-Va?usp=sharing", 
                       type = "spreadsheet",
                       overwrite = T)
  
  write_sheet(db_age, 
              ss = meta$id,
              sheet = "cases&deaths_age")
  
  write_sheet(db_sex, 
              ss = meta$id,
              sheet = "cases&deaths_sex")
  
  sheet_delete(meta$id, "Sheet1")
  
  # uploading the whole excel file for INED
  file_name <- paste0("SE", date, "cases&deaths.xlsx")
  drive_upload(
    tf,
    path = "https://drive.google.com/drive/folders/1JS5pzekf-dmuYs6-K3rPsBv3pbtXdRA2?usp=sharing",
    name = file_name,
    overwrite = T)
  
  
} else {
  cat(paste0("no new updates so far, last date: ", date_f))
}

