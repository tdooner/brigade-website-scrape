require 'fileutils'
require 'vcr'
require 'yaml'

module BrigadeWebsiteScrape
  class Cache
    DEFAULT_STATE = { version: 1, skip_urls: [] }

    def initialize(cache_directory, logger: Logger.new('/dev/null'))
      @logger = logger
      @cache_directory = File.expand_path(cache_directory)
      @vcr_directory = File.join(@cache_directory, 'vcr')
      @state_file = File.join(@cache_directory, 'state.yml')
      @state = YAML.load_file(@state_file) rescue DEFAULT_STATE
    end

    def create_directories!(reset: false)
      FileUtils.rm_rf(@cache_directory) if reset
      FileUtils.mkdir_p(@cache_directory)
      FileUtils.mkdir_p(@vcr_directory)
    end

    def with_vcr_cache(cassette, &block)
      VCR.configure do |config|
        config.cassette_library_dir = @vcr_directory
        config.hook_into :webmock
        config.allow_http_connections_when_no_cassette = true
      end

      VCR.use_cassette(cassette, record: :new_episodes, &block)
    end

    def skip_url(url)
      @logger.info "Cache will skip caching for URL: #{url}"

      unless @state[:skip_urls].include?(url.to_s)
        @state[:skip_urls].push(url.to_s)
      end

      File.open(@state_file, 'w') do |f|
        YAML.dump(@state, f)
      end
    end
  end
end
