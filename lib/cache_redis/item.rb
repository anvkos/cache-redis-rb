module CacheRedis
  class Item
    attr_accessor :value, :lifetime, :tags
    attr_reader :creation_time

    DEFAULT_LIFETIME = 300

    def initialize(options = {})
      @creation_time = Time.now.to_i
      @value = options[:value]
      @lifetime = options[:lifetime] || DEFAULT_LIFETIME
      @tags = options[:tags] || {}
    end
  end
end
