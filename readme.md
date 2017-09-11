# Summoner Name Database
This application is a command line tool to record and search change history of summoner name.

[GitHub](https://github.com/derekbailey/summoner_name_database)

## Requirements
- Ruby (2.4)
- SQLite

## Setup
- Download this script.
- Get Riot API Key from https://developer.riotgames.com/ and write it to `api_key.txt` in same dir with this script.
- Add `DATABASE_URL` to env vars. (Optional)
- Install gems, `bundle install --path vendor/bundle`

## Usage
1. Add summoner info.
2. Update database regularly.
3. Find names.

### Commands

    bundle exec ruby snd.rb add <server> <summoner_name>
    bundle exec ruby snd.rb add_id <server> <summoner_id>
    bundle exec ruby snd.rb update <server>
    bundle exec ruby snd.rb find <server> <keyword>
    bundle exec ruby snd.rb find_id <server> <summoner_id>
    bundle exec ruby snd.rb list <server>

### Examples

    bundle exec ruby snd.rb add kr hideonbush
    bundle exec ruby snd.rb update kr
    bundle exec ruby snd.rb find kr bush

## Disclaimer
Summoner Name Database isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing League of Legends. League of Legends and Riot Games are trademarks or registered trademarks of Riot Games, Inc. League of Legends © Riot Games, Inc.
