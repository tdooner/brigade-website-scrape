require 'csv'

module BrigadeWebsiteScrape
  class Scraper
    IGNORE_URL_HOST_REGEX = %r{meetup\.com}

    def initialize(logger: Logger.new('/dev/null'))
      @sites = []
      @rules = []
      @logger = logger
    end

    def add_xpath_rule(name, xpath)
      @rules << { type: :xpath, name: name, xpath: xpath }
    end

    # exact = can that be the only text in the element (true) or wildcard (false)
    def add_text_rule(name, text, exact: true)
      @rules << { type: :text, name: name, text: text, exact: exact }
    end

    # Use wildcards as asterisks in the URL. You can only use them at the
    # beginning or end of the string.
    # e.g. url = "*github.com/foobar"
    def add_url_rule(name, url)
      @rules << { type: :url, name: name, url: url }
    end

    def add_brigade(name, url)
      @logger.info "Adding website for #{name}: #{url}"

      if (redirect = check_for_redirect(url))
        @logger.warn "Website for #{name} redirected: #{redirect[0]}  -->  #{redirect[1]}"
        url = redirect[1]
      end

      if url.host.match?(IGNORE_URL_HOST_REGEX)
        @logger.warn "Ignoring website for #{name} by regex: #{url}"
        return
      end

      @sites << [name, url]
    end

    def scrape_all!(cache: nil)
      csv = CSV.new($stdout, headers: ['rule', 'brigade', 'url', 'text', 'link'], write_headers: true)

      @sites.each_with_index do |(brigade_name, url), i|
        @logger.info "Beginning scrape of website (#{i + 1} / #{@sites.length}): #{url}"

        cache.with_vcr_cache(brigade_name) do
          SiteScraper
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
end
