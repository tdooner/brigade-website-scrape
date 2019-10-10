module BrigadeWebsiteScrape
  class BrigadeInfoDownloader
    JSON_URL = URI('https://raw.githubusercontent.com/codeforamerica/brigade-information/master/organizations.json')

    def each_brigade(&block)
      response = Net::HTTP.get(JSON_URL)
      JSON.parse(response).each(&block)
    end
  end
end
