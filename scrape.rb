require 'net/http'
require 'json'
require 'logger'
require 'vcr'
require_relative './scrape_page.rb'

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cache"
  config.hook_into :webmock
  config.allow_http_connections_when_no_cassette = true
end

class BrigadeInfoDownloader
  JSON_URL = URI('https://raw.githubusercontent.com/codeforamerica/brigade-information/master/organizations.json')

  def each_brigade(&block)
    response = Net::HTTP.get(JSON_URL)
    JSON.parse(response).each(&block)
  end
end

class BrigadeWebsiteScraper
  def initialize(logger: Logger.new('/dev/null'))
    @sites = []
    @rules = []
    @logger = logger
  end

  def add_xpath_rule(name, xpath)
    @rules << { type: :xpath, name: name, xpath: xpath }
  end

  def add_text_rule(name, text)
    @rules << { type: :text, name: name, text: text }
  end

  def add_brigade(name, url)
    @logger.info "Adding website for #{name}: #{url}"

    if (redirect = check_for_redirect(url))
      @logger.warn "Website for #{name} redirected: #{redirect[0]}  -->  #{redirect[1]}"
      @sites << [name, redirect[1]]
    else
      @sites << [name, url]
    end
  rescue Net::OpenTimeout
    @logger.warn "Open Timeout hit loading #{url}"
  rescue SocketError
    @logger.warn "Failed to open TCP socket for #{url}"
  rescue OpenSSL::SSL::SSLError => ex
    @logger.warn "SSL error with #{url}: #{ex.message}"
  end

  def scrape_all!
    csv = CSV.new($stdout, headers: ['rule', 'brigade', 'url', 'text', 'link'], write_headers: true)

    @sites.each_with_index do |(brigade_name, url), i|
      @logger.info "Beginning scrape of website (#{i + 1} / #{@sites.length}): #{url}"

      VCR.use_cassette(brigade_name) do
        BrigadeSiteScraper
          .new(url, @rules, logger: @logger)
          .scrape
          .results
          .each do |match|
          csv << [match[:rule], brigade_name, match[:url], match[:text], match[:link]]
        end
      end

      @logger.info "Finished scrape of #{url}"
    end
  end

  private

  def check_for_redirect(url)
    original_url = url

    loop do
      response = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == 'https', open_timeout: 5) do |http|
        http.request(Net::HTTP::Get.new(url.request_uri))
      end

      break if response.code.to_i < 300
      url = URI(response['Location'])
    end

    if original_url != url
      [original_url, url]
    end
  end
end

logger = Logger.new($stderr)
scraper = BrigadeWebsiteScraper.new(logger: logger)

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
