require 'csv'
require 'spidr'
require 'logger'

class BrigadeSiteScraper
  SKIP_EXTENSIONS = %w[.css .js .json .png .jpg .xml]
  MAX_PAGES_PER_SITE = 20

  attr_reader :results

  def initialize(url, rules, logger: Logger.new('/dev/null'))
    @url = url
    @rules = rules
    @logger = logger
    @results = []
  end

  def scrape
    Spidr::Agent.new(max_depth: 3) do |spider|
      spider.every_link do |url, next_url|
        raise Spidr::Agent::Actions::SkipLink if next_url.host != url.host
        raise Spidr::Agent::Actions::SkipLink if SKIP_EXTENSIONS.any? { |ext| next_url.path.end_with?(ext) }
      end

      spider.every_page do |page|
        @logger.info "Processing page (#{spider.visited_urls.length} / #{spider.visited_urls.length + spider.queue.length - 1}): #{page.url}"

        @rules.each do |rule|
          case rule[:type]
          when :xpath
            page.search(rule[:xpath]).each do |el|
              text, link = result_title_href(el)
              add_result(rule: rule[:name], url: page.url, text: text, link: link)
            end
          when :text
            page.search(xpath_case_insensitive(rule[:text])).each do |el|
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
  end

  def add_result(result)
    return if @results.any? { |r| r[:rule] == result[:rule] && r[:text] == result[:text] && r[:link] == result[:link] }
    @results << result
  end

  def xpath_case_insensitive(str)
    "//*[" \
      "contains(translate(text(), \"ABCDEFGHIJKLMNOPQRSTUVWXYZ\", \"abcdefghijklmnopqrstuvwxyz\"), \"#{str}\")" \
      "or contains(translate(@href, \"ABCDEFGHIJKLMNOPQRSTUVWXYZ\", \"abcdefghijklmnopqrstuvwxyz\"), \"#{str}\")" \
      "]"
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
end


if ARGV[0]
  scrape_sites([ARGV[0]])
end
