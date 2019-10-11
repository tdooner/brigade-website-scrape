require 'json'
require 'logger'
require 'net/http'
require 'optparse'
require 'vcr'

module BrigadeWebsiteScrape
  class CLI
    def initialize(argv)
      @options = {
        cache_dir: '~/.cache/brigade_website_scrape',
        reset: false,
      }

      OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"
        opts.on('-v', '--verbose', 'Display verbose logging') do |v|
          @options[:verbose] = true
        end
        opts.on('--reset', 'Reset Cache') do |v|
          @options[:reset] = true
        end
      end.parse!(argv)
    end

    def run!
      logger = Logger.new($stderr)
      logger.level = Logger::WARN unless @options[:verbose]
      scraper = Scraper.new(logger: logger)

      cache = Cache.new(@options[:cache_dir], logger: logger)
      cache.create_directories!(reset: @options[:reset])

      cache.with_vcr_cache('brigade_info') do
        BrigadeInfoDownloader.new.each_brigade do |brigade|
          next unless brigade['tags'] && brigade['tags'].include?('Code for America') &&
            brigade['tags'].include?('Official')

          if !brigade['website'] || brigade['website'].length == 0
            logger.warn "WARN: No website listed for #{brigade['name']}"
            next
          end

          url = URI(brigade['website'])

          begin
            scraper.add_brigade(brigade['name'], url)
          rescue Net::OpenTimeout
            cache.skip_url(url)
            logger.warn "Open Timeout hit loading #{url}"
          rescue SocketError
            cache.skip_url(url)
            logger.warn "Failed to open TCP socket for #{url}"
          rescue OpenSSL::SSL::SSLError => ex
            cache.skip_url(url)
            logger.warn "SSL error with #{url}: #{ex.message}"
          end
        end
      end

      scraper.add_text_rule('donate', 'donate')
      scraper.add_url_rule('donate', '*secure.codeforamerica.org*')
      # scraper.add_xpath_rule('rss', '//link[@type="application/rss+xml"]')
      # scraper.add_text_rule('facebook', 'facebook')
      # scraper.add_text_rule('github', 'github')
      # scraper.add_text_rule('newsletter', 'newsletter')
      # scraper.add_text_rule('slack', 'slack')
      # scraper.add_text_rule('twitter', 'twitter')
      scraper.scrape_all!(cache: cache)
    end
  end
end
