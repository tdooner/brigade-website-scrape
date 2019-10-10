require 'json'
require 'logger'
require 'net/http'
require 'optparse'
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cache"
  config.hook_into :webmock
  config.allow_http_connections_when_no_cassette = true
end

module BrigadeWebsiteScrape
  class CLI
    def initialize(argv)
      @options = {}

      OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"
        opts.on('-v', '--verbose', 'Display verbose logging') do |v|
          @options[:verbose] = true
        end
      end.parse!(argv)
    end

    def run!
      logger = Logger.new($stderr)
      logger.level = Logger::WARN unless @options[:verbose]
      scraper = Scraper.new(logger: logger)

      BrigadeInfoDownloader.new.each_brigade do |brigade|
        next unless brigade['tags'] && brigade['tags'].include?('Code for America') &&
          brigade['tags'].include?('Official')

        if !brigade['website'] || brigade['website'].length == 0
          logger.warn "WARN: No website listed for #{brigade['name']}"
          next
        end

        url = URI(brigade['website'])

        scraper.add_brigade(brigade['name'], url) if url && !url.host.match(/meetup\.com/)
      end

      scraper.add_xpath_rule('rss', '//link[@type="application/rss+xml"]')
      scraper.add_text_rule('facebook', 'facebook')
      scraper.add_text_rule('github', 'github')
      scraper.add_text_rule('newsletter', 'newsletter')
      scraper.add_text_rule('slack', 'slack')
      scraper.add_text_rule('twitter', 'twitter')
      scraper.scrape_all!
    end
  end
end
