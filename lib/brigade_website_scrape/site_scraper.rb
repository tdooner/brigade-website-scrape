require 'spidr'
require 'logger'

module BrigadeWebsiteScrape
  class SiteScraper
    SKIP_EXTENSIONS = %w[.css .js .json .png .jpg .xml]
    SKIP_CONTENT_TYPES = %w[text/xml application/rss+xml]
    MAX_PAGES_PER_SITE = 20

    attr_reader :results

    def initialize(url, rules, logger: Logger.new('/dev/null'))
      @url = url
      @rules = rules
      @logger = logger
      @results = []
    end

    def scrape
      last_page_processed = nil

      Spidr::Agent.new(max_depth: 3) do |spider|
        spider.every_link do |url, next_url|
          raise Spidr::Agent::Actions::SkipLink if next_url.host != url.host
          raise Spidr::Agent::Actions::SkipLink if SKIP_EXTENSIONS.any? { |ext| next_url.path.end_with?(ext) }
          raise Spidr::Agent::Actions::SkipLink if next_url.scheme == 'mailto:'
        end

        spider.every_page do |page|
          last_page_processed = page.url
          content_type = page.headers.find { |k, v| k.match(/Content-Type/i) }
          next if content_type && SKIP_CONTENT_TYPES.any? { |t| content_type.last[0].include?(t) }

          @logger.info "Processing page (#{spider.visited_urls.length} / #{spider.visited_urls.length + spider.queue.length - 1}): #{page.url}"

          @rules.each do |rule|
            case rule[:type]
            when :xpath
              page.search(rule[:xpath]).each do |el|
                text, link = result_title_href(el)
                add_result(rule: rule[:name], url: page.url, text: text, link: link)
              end
            when :text
              page.search(xpath_case_insensitive(rule[:text], exact: rule[:exact])).each do |el|
                text, link = result_title_href(el)
                add_result(rule: rule[:name], url: page.url, text: text, link: link)
              end
            when :url
              page.search(url_to_xpath(rule[:url])).each do |el|
                text, link = result_title_href(el)
                add_result(rule: rule[:name], url: page.url, text: text, link: link)
              end
            end
          end

          if spider.visited_urls.length == (MAX_PAGES_PER_SITE - 1)
            @logger.info "Reached #{MAX_PAGES_PER_SITE} page maximum. Skipping remainder of pages."
            return self
          end
        end
      end.start_at(@url)

      self
    rescue => ex
      @logger.error "Exception processing #{last_page_processed}: #{ex.message}"
      return self
    end

    def add_result(result)
      return unless result[:text] || result[:link]
      @results << result
    end

    def xpath_case_insensitive(str, exact: true)
      if exact
        "//body/*[" \
          "translate(normalize-space(text()), \"ABCDEFGHIJKLMNOPQRSTUVWXYZ\", \"abcdefghijklmnopqrstuvwxyz\")=\"#{str.downcase}\"" \
          "or translate(@href, \"ABCDEFGHIJKLMNOPQRSTUVWXYZ\", \"abcdefghijklmnopqrstuvwxyz\")=\"#{str.downcase}\"" \
          "]"
      else
        "//body/*[" \
          "contains(translate(normalize-space(text()), \"ABCDEFGHIJKLMNOPQRSTUVWXYZ\", \"abcdefghijklmnopqrstuvwxyz\"), \"#{str.downcase}\")" \
          "or contains(translate(@href, \"ABCDEFGHIJKLMNOPQRSTUVWXYZ\", \"abcdefghijklmnopqrstuvwxyz\"), \"#{str.downcase}\")" \
          "]"
      end
    end

    def result_title_href(el)
      case el.name
      when "script", "style"
        []
      when "a", "link"
        [el.text.strip, el['href']]
      else
        [el.text.strip]
      end
    end

    def url_to_xpath(url)
      if url.end_with?('*') && url.start_with?('*')
        "//*[contains(@href, '#{url[1..-2]}')]"
      elsif url.end_with('*')
        "//*[starts-with(@href, '#{url[0..-2]}')]"
      elsif url.start_with('*')
        "//*[ends-with(@href, '#{url[1..-1]}')]"
      else
        "//*[@href]"
      end
    end
  end
end
