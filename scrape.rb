require 'net/http'
require 'json'

class BrigadeInfoDownloader
  JSON_URL = URI('https://raw.githubusercontent.com/codeforamerica/brigade-information/master/organizations.json')

  def each_brigade(&block)
    response = Net::HTTP.get(JSON_URL)
    JSON.parse(response).each(&block)
  end
end

class BrigadeWebsiteScraper
  def initialize(url)
    @url = URI(url)
  end

  def scrape
    if (redirect = check_for_redirect)
      $stderr.puts "WARN: Website redirected: #{redirect[0]}  -->  #{redirect[1]}"
    end
  rescue Net::OpenTimeout
    $stderr.puts "WARN: Open Timeout hit loading #{@url}"
  rescue SocketError
    $stderr.puts "WARN: Failed to open TCP socket for #{@url}"
  rescue OpenSSL::SSL::SSLError => ex
    $stderr.puts "WARN: SSL error with #{@url}: #{ex.message}"
  end

  private

  def check_for_redirect
    original_url = @url

    loop do
      response = Net::HTTP.start(@url.host, @url.port, use_ssl: @url.scheme == 'https', open_timeout: 5) do |http|
        http.request(Net::HTTP::Get.new(@url.request_uri))
      end

      break if response.code.to_i < 300
      @url = URI(response['Location'])
    end

    if original_url != @url
      [original_url, @url]
    end
  end
end

BrigadeInfoDownloader.new.each_brigade do |brigade|
  next unless brigade['tags'] && brigade['tags'].include?('Code for America') &&
    brigade['tags'].include?('Official')

  if !brigade['website'] || brigade['website'].length == 0
    $stderr.puts "WARN: No website listed for #{brigade['name']}"
    next
  end

  BrigadeWebsiteScraper.new(brigade['website']).scrape
end
