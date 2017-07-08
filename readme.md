# Summoner Name Database
This application is a command line tool to record and search change history of summoner name.

## Requirements
- Ruby
- SQLite

## Setup
- Get Riot API Key from https://developer.riotgames.com/
- Add `DATABASE_URL` to env vars (Optional)

## Usage
1. Add summoner info.
2. Update database regularly.
3. Find names.

### Commands
```
ruby snd.rb add <server> <summoner_name>
ruby snd.rb add_id <server> <summoner_id>
ruby snd.rb update <server>
ruby snd.rb find <server> <keyword>
ruby snd.rb find_id <server> <summoner_id>
ruby snd.rb list <server>
```

### Examples
```
ruby snd.rb add kr hideonbush
ruby snd.rb update kr
ruby snd.rb find kr bush
```
