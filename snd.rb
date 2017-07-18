require 'data_mapper'
require 'colorize'
require 'json'
require 'thor'

require 'open-uri'
require 'logger'
require 'cgi'
require 'pp'

class Summoner
  include DataMapper::Resource

  property :id,  Serial
  property :uid, Text, required: true, unique: true

  has n, :names
end

class Name
  include DataMapper::Resource

  property :id,          Serial
  property :summoner_id, Integer,  required: true
  property :ign,         Text,     required: true
  property :date,        DateTime, required: true

  belongs_to :summoner
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
      abort 'You need to create api_key.txt' unless File.exist?('./api_key.txt')

      @api_key = File.read('./api_key.txt')
      @interval = 1.2
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

    def find_by_name(summoner_name)
      summoner_name = _validate(summoner_name)
      res = _request("/lol/summoner/v3/summoners/by-name/#{summoner_name}")
      res['id'].to_s
    end

    def find_by_id(summoner_id)
      summoner_id = summoner_id.to_s
      res = _request("/lol/summoner/v3/summoners/#{summoner_id}")
      res['name'].to_s
    end
  end

  class App
    def initialize(server)
      DataMapper.setup(:default, db_path(server))
      DataMapper.finalize
      DataMapper.auto_upgrade!

      logger = Logger.new(STDOUT)
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
      end

      @client = RiotAPI.new(server)
      @server = server
      @logger = logger
    end

    def db_path(server)
      file_name = "#{DBNAME}#{server}#{DBEXT}"
      if ENV['DATABASE_URL']
        'sqlite3:' + File.join(ENV['DATABASE_URL'], file_name)
      else
        'sqlite3:' + File.expand_path(File.join(File.dirname(__FILE__), file_name))
      end
    end

    def add(summoner_name)
      sum_id = @client.find_by_name(summoner_name)
      add_id(sum_id)
    end

    def add_id(summoner_id)
      sum_name = @client.find_by_id(summoner_id)
      sum = Summoner.create(uid: summoner_id)
      if sum.id
        sum.names.create(ign: sum_name, date: Time.now)
        @logger.info "Success: #{sum_name.colorize(:blue)}"
      end
    rescue => e
      @logger.error "Error: #{summoner_id} -> #{e.message}"
    end

    def update
      @logger.info "Run @#{NAME.colorize(:green)} -> #{@server.upcase}"
      Summoner.all.each do |summoner|
        update_summoner(summoner)
      end
    end

    def update_summoner(summoner)
      new_name = @client.find_by_id(summoner.uid)
      old_name = summoner.names.last.ign || nil

      if new_name != old_name || old_name.nil?
        summoner.names.create(ign: new_name, date: Time.now)
        @logger.info "Update: #{old_name.colorize(:blue)} -> #{new_name.colorize(:blue)}"
      end
    rescue => e
      @logger.error "Error: #{summoner.names.last.ign} -> #{e.message}"
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
        puts "---History: #{names.last.ign} [#{names.last.summoner.uid}]"
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
end

if __FILE__ == $PROGRAM_NAME
  args = ARGV.map {|s| s.encode('utf-8', Encoding.find('locale').to_s) }
  regions = 'na kr jp br tr euw eue oce las lan ru'.split(' ').join('|')

  if args[1]
    abort 'Error: incorrect args.' unless args[1].match(/#{regions}/)
  end

  SNDCommand.start(args)
end
