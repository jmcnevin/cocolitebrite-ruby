require "rubygems"
require "bundler/setup"
require 'cocaine'
require 'httparty'
require 'uri'
require 'tempfile'
require 'chunky_png'
require 'wordnik'
require 'artii'

LEASE_POLL_SECONDS = 15
ROWS               = 12
COLS               = 80
THROTTLE_SECS      = 0.2
BASE_URL           = 'http://10.1.3.251/litebrite/peggy'
APP_NAME           = 'cocolitebrite-ruby 0.1'

module CocoLiteBrite
  class Lease
    attr_reader :code, :expiry
    def initialize(code = nil, minutes = 1)
      if code
        @code = code
        return
      end
      response = Request.new("#{BASE_URL}/get_lease/#{minutes}").get
      @code = response['lease_code']
      @expiry = response['lease_expiry']
    rescue Request::FailureResponse
      puts "Could not get lease.  Retrying in #{LEASE_POLL_SECONDS} seconds."
      sleep LEASE_POLL_SECONDS
      retry
    end
  end

  class Request
    attr_reader :url
    def initialize(url)
      @url = url
      puts @url if ENV['DEBUG']
    end

    def get
      sleep THROTTLE_SECS
      response = HTTParty.get(@url, :headers => {
        'User-Agent' => APP_NAME,
      })
      puts response.inspect if ENV['DEBUG']
      response = response.parsed_response
      if response['result'] == 'failure'
        raise FailureResponse
      end
      response
    end

    class FailureResponse < StandardError; end
  end

  class Writer
    attr_accessor :lease
    def initialize
      @lease = Lease.new
    end

    def write(row=0, col=0, message)
      message = wrap_lines(message)
      message.each_line do |x|
        x = URI::escape(translate(x))
        Request.new("#{BASE_URL}/write/#{@lease.code}/#{row}/#{col}/#{x}").get
        row += 1
      end
    end

    def wrap_lines(message, col = COLS)
      new_message = []
      message.each_line do |x|
        new_message << x.gsub(/(.{1,#{col}})( +|$\n?)|(.{1,#{col}})/, "\\1\\3\n")
      end
      new_message.join('')
    end

    def translate(message)
      message = message.to_s.
      encode("US-ASCII", :invalid => :replace, :undef => :replace).
      rstrip[0, COLS].
      ljust(COLS, ' ').
      tr("`_","'-").
      gsub(/[^\w\s\@\!\(\)\$\-\=\'\,\:\-\.\/]/,'*')
      message
    end

    def clear
      0.upto(ROWS-1) do |x|
        write(x, 0, (' ' * COLS))
      end
    end
  end
end

def ny_times
  items = ["NY TIMES FRONT PAGE - #{Time.now}", ("=" * COLS)]
  news = CocoLiteBrite::Request.new("http://pipes.yahoo.com/pipes/pipe.run?_id=Llu8dRh23BGG6N4ZxQnzeQ&_render=json").get
  available_rows = ((ROWS - 2) - items.size)
  news["value"]["items"][0, available_rows].each do |i|
    items << i["title"]
  end
  items << "*** Go nuts: github.com-jmcnevin-cocolitebrite-ruby ***"
  items.join("\n")
end

def hacker_news
  items = ["news.ycombinator.com - #{Time.now}", ("=" * COLS)]
  news = CocoLiteBrite::Request.new("http://api.ihackernews.com/page").get
  available_rows = ((ROWS - 1) - items.size)
  news["items"][0, available_rows].each do |i|
    items << i["title"]
  end
  items.join("\n")
end

def word_of_the_day
  Wordnik.configure do |config|
    config.api_key = 'GET YOUR OWN'
  end
  resp = Wordnik.words.get_word_of_the_day
  message = ["WORD OF THE DAY"]
  message << '=' * message.first.length
  message << resp["word"]
  resp["definitions"].each do |d|
    message << d["text"]
  end
  message.join("\n")
end

def clock(font = 'doh')
  Artii::Base.new(Time.now.strftime("%l:%M"), '-f', font).output
end

def text(text, font)
  Artii::Base.new(text, '-f', font).output
end

def image(filename)
  tempfile = Tempfile.new(['convert','.png'])
  line = Cocaine::CommandLine.new("convert",
                                  ":input -resize \"#{COLS}x#{ROWS}\" -monochrome :output",
                                  :output => tempfile.path,
                                  :input => filename)
  output = line.run

  image = ChunkyPNG::Image.from_file(tempfile.path)

  message = ''

  0.upto(image.height-1) do |row|
    0.upto(image.width-1) do |col|
      val = image[col,row]
      message += case val
      when 255
        ' '
      else
        '*'
      end
    end
    message += "\n"
  end

  message
ensure
  tempfile.close
  tempfile.unlink
end

def display(message)
  if ENV['FINAL']
    writer = CocoLiteBrite::Writer.new
    writer.clear
    writer.write(message)
  else
    puts message
  end
end

# display clock('univers')
display text(":-)", 'banner3')