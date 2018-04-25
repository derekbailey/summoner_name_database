require 'bundle/inline'
require 'open-uri'
require 'logger'
require 'json'
require 'cgi'
require 'pp'

gemfile(true) do
    source 'https://rubygems.org'
    gem 'data_mapper', '1.2.0'
    gem 'dm-sqlite-adapter', '1.2.0', require: false
    gem 'colorize', '0.8.1'
    gem 'thor', '0.20.0'
end

class Summoner
  include DataMapper::Resource

  property :id,  Serial
  property :uid, Text, required: true, unique: true

  has n, :names
  has n, :ranks
end

class Name
  include DataMapper::Resource

  property :id,          Serial
  property :summoner_id, Integer,  required: true
  property :ign,         Text,     required: true
  property :date,        DateTime, required: true

  belongs_to :summoner
end

class Rank
  include DataMapper::Resource

  property :id,          Serial
  property :summoner_id, Integer, required: true
  property :peak,        Text
  property :date,        DateTime

  belongs_to :summoner

  def self.define
    hash = {}
    hash['CHALLENGER I'] = 0
    hash['MASTER I'] = 1
    index = 2
    %w(DIAMOND PLATINUM GOLD SILVER BRONZE).each do |tier|
      %w(I II III IV V).each do |div|
        hash["#{tier} #{div}"] = index
        index = index.next
      end
    end
    hash['UNRANKED'] = index
    hash
  end

  # return true if x is higher than y, false if not.
  def self.compare_by_rank(x, y)
    reg = /(?<tier>[a-zA-Z]+\s?[IV]+)?(\s)?(?<lp>-?[0-9]+)?(LP)?/
    ranks = define
    x = x.match(reg)
    y = y.match(reg)
    if x[:tier] != y[:tier]
      if 1 == ((ranks[x[:tier]] || 9999) <=> (ranks[y[:tier]] || 9999))
        false
      else
        true
      end
    else
      if 1 == (y[:lp].to_i <=> x[:lp].to_i) || 0 == (y[:lp].to_i <=> x[:lp].to_i)
        false
      else
        true
      end
    end
  end
end

module SND
  NAME = 'Summoner Name Database'
  DBNAME = 'snd_'
  DBEXT = '.sqlite3'

  class RiotAPI
    ENDPOINTS = {
      br: 'br1.api.riotgames.com',
      eune: 'eun1.api.riotgames.com',
      euw: 'euw1.api.riotgames.com',
      jp: 'jp1.api.riotgames.com',
      kr: 'kr.api.riotgames.com',
      lan: 'la1.api.riotgames.com',
      las: 'la2.api.riotgames.com',
      na: 'na1.api.riotgames.com',
      oce: 'oc1.api.riotgames.com',
      tr: 'tr1.api.riotgames.com',
      ru: 'ru.api.riotgames.com',
      pbe: 'pbe1.api.riotgames.com'
    }

    def initialize(server)
      abort 'Error: Unknown server' unless ENDPOINTS.keys.map(&:to_s).index(server)

      path = File.expand_path('../api_key.txt', __FILE__)
      abort 'You need to create api_key.txt' unless File.exist?(path)

      @api_key ||= File.read(path)
      # @interval = 1.4 # for dev key: 20req/1sec, 100req/2min
      @interval = 0.08 # for production key: 50req/1sec
      @server = server
    end

    def _request(path)
      host = "https://#{ENDPOINTS[@server.to_sym]}"
      url = host + path + "?api_key=#{@api_key}"
      result = JSON.parse(open(url).read)
      sleep @interval
      result
    end

    def _validate(name)
      CGI.escape(name.encode('UTF-8').downcase.gsub(/\s/, ''))
    end

    def find_id_by_name(summoner_name)
      summoner_name = _validate(summoner_name)
      res = _request("/lol/summoner/v3/summoners/by-name/#{summoner_name}")
      res['id'].to_s
    end

    def find_name_by_id(summoner_id)
      summoner_id = summoner_id.to_s
      res = _request("/lol/summoner/v3/summoners/#{summoner_id}")
      res['name'].to_s
    end

    def find_rank_by_id(summoner_id)
      summoner_id = summoner_id.to_s
      leagues = _request("/lol/league/v3/positions/by-summoner/#{summoner_id}")
      leagues.each do |league|
        if league['queueType'] == 'RANKED_SOLO_5x5'
          return "#{league['tier']} #{league['rank']} #{league['leaguePoints']}LP"
        end
      end
      'UNRANKED'
    rescue
      'UNRANKED'
    end
  end

  class App
    def initialize(server)
      DataMapper.setup(:default, db_path(server))
      DataMapper.finalize
      DataMapper.auto_upgrade!

      logger = Logger.new(
        STDOUT,
        formatter: proc {|severity, datetime, progname, msg|
          "#{datetime} [#{severity}] #{msg}\n"
        }
      )

      @client = RiotAPI.new(server)
      @server = server
      @logger = logger
    end

    def db_path(server)
      file_name = "#{DBNAME}#{server}#{DBEXT}"
      if ENV['DATABASE_DIR']
        'sqlite3:' + File.join(ENV['DATABASE_DIR'], file_name)
      else
        'sqlite3:' + File.expand_path(File.join(File.dirname(__FILE__), file_name))
      end
    end

    def add(summoner_name)
      sum_id = @client.find_id_by_name(summoner_name)
      add_id(sum_id)
    rescue => e
      @logger.error "#{summoner_name} -> #{e.message}"
    end

    def add_id(summoner_id)
      sum_name = @client.find_name_by_id(summoner_id)
      sum_rank = @client.find_rank_by_id(summoner_id)
      sum = Summoner.create(uid: summoner_id)
      if sum.id
        sum.names.create(ign: sum_name, date: Time.now)
        sum.ranks.create(peak: sum_rank, date: Time.now)
        @logger.info "Success: #{summoner_id} -> #{sum_name.colorize(:blue)}"
      end
    rescue => e
      @logger.error "#{summoner_id} -> #{e.message}"
    end

    def update
      @logger.info "Run @#{NAME.colorize(:green)} -> #{@server.upcase}"
      Summoner.all.each do |summoner|
        update_summoner(summoner)
      end
    end

    def update_summoner(summoner)
      new_name = @client.find_name_by_id(summoner.uid)
      old_name = summoner.names.last.ign || nil

      new_rank = @client.find_rank_by_id(summoner.uid)
      old_rank = summoner.ranks.last.peak rescue 'UNRANKED'

      if new_name != old_name || old_name.nil?
        summoner.names.create(ign: new_name, date: Time.now)
        @logger.info "Update: #{old_name.colorize(:blue)} -> #{new_name.colorize(:blue)}"
      end

      if Rank.compare_by_rank(new_rank, old_rank)
        summoner.ranks.create(peak: new_rank)
        @logger.info "Update: #{new_name.colorize(:blue)} -> #{new_rank.colorize(:orange)}"
      end
    rescue => e
      @logger.error "#{summoner.names.last.ign} -> #{e.message}"
    end

    def list
      puts Summoner.all.map {|s| s.names.last.ign }.sort.join("\n")
    end

    def find(summoner_name)
      names = Name.all.select {|n| n.ign.match(/#{summoner_name}/i) }
      abort 'Summoner not found.' if names.size == 0

      names.uniq!(&:summoner_id)

      names.each do |name|
        names = Summoner.all(id: name.summoner_id).names
        if names.last.summoner.ranks.size > 0
          puts "---History: #{names.last.ign} [#{names.last.summoner.uid}] (Peak rank: #{names.last.summoner.ranks.last.peak})"
        end
        names.reverse_each do |n|
          puts "#{n.date.to_s.split('T').first} #{n.ign.colorize(:blue)}"
        end
        puts "\n"
      end
    end

    def find_id(summoner_id)
      sums = Summoner.all(uid: summoner_id)
      abort 'Summoner not found.' if sums.size == 0

      names = sums.names
      puts "History: #{names.last.summoner.uid}"
      names.reverse_each do |n|
        puts "#{n.date.to_s.split('T').first} #{n.ign.colorize(:blue)}"
      end
      puts "\n"
    end

    def id2name(summoner_id)
      puts @client.find_name_by_id(summoner_id)
    end

    def name2id(summoner_name)
      puts @client.find_id_by_name(summoner_name)
    end
  end

  class Ladder
    def self.get(server, num = 50)
      num = num.to_i
      num = 50 if num < 50
      server = 'www' if server == 'kr'

      list = []
      (num / 50).times do |i|
        url = "http://#{server}.op.gg/ranking/ajax2/ladders/start=#{i*50}"
        open(url).readlines.each do |line|
          if line.match(/op\.gg\/summoner\/userName=(.*?)"/)
            list << CGI.unescape($1)
          end
        end
      end
      list.uniq
    end
  end
end

class SNDCommand < Thor
  desc 'add <server> <summoner_name>', 'Add account by summoner name'
  def add(server, *argv)
    snd = SND::App.new(server)
    argv.map {|name| snd.add(name) }
  end

  desc 'add_id <server> <summoner_id>', 'Add account by summoner id'
  def add_id(server, *argv)
    snd = SND::App.new(server)
    argv.map {|id| snd.add_id(id) }
  end

  desc 'update <server>', 'Update database'
  def update(server)
    SND::App.new(server).update
  end

  desc 'list <server>', 'Show list of current summoner names'
  def list(server)
    SND::App.new(server).list
  end

  desc 'find <server> <keyword>', 'Find account by keyword'
  def find(server, keyword)
    SND::App.new(server).find(keyword)
  end

  desc 'find_id <server> <summoner_id>', 'Find account by summoner id'
  def find_id(server, summoner_id)
    SND::App.new(server).find_id(summoner_id)
  end

  desc 'ladder <server> <size>', 'Add summoner from ladder'
  def ladder(server, size)
    snd = SND::App.new(server)
    list = SND::Ladder.get(server, size)
    list.map {|name| snd.add(name) }
  end

  desc 'id2name <server> <id>', 'Convert summoner name from summoner id'
  def id2name(server, id)
    SND::App.new(server).id2name(id)
  end

  desc 'name2id <server> <name>', 'Convert summoner id from summoner name'
  def name2id(server, id)
    SND::App.new(server).name2id(id)
  end
end

if __FILE__ == $PROGRAM_NAME
  args = ARGV.map {|s| s.encode('utf-8', Encoding.default_external) }
  SNDCommand.start(args)
end
