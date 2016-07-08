require_relative 'item'

module CacheRedis
  class Cache
    attr_reader :redis

    def initialize(redis, options = {})
      @redis = redis
      @options = {
        # FIXME : change set options
        dogpile_prevention: options[:dogpile_prevention].nil? ? true : options[:dogpile_prevention],
        dogpile_prevention_factor: options[:dogpile_prevention_factor] || 2
      }
    end

    def read(id)
      item = read_item(id)
      item.nil? ? nil : item.value
    end

    def write(id, value, options = {})
      item = CacheRedis::Item.new
      item.value = value
      item.lifetime = options[:expire_in] unless options[:expire_in].nil?
      item.tags = write_tags(options[:tags]) unless options[:tags].nil?
      result = redis.setex(id, lifetime(item.lifetime), marshal(item))
      unlock(id)
      result == 'OK'
    end

    def fetch(id, options = {}, &_block)
      item = read_item(id)
      return item.value unless item.nil?
      if block_given?
        data = yield
        write(id, data, options)
      end
      data
    end

    def delete(id)
      redis.del(id)
    end

    def clean_by_tags(tags)
      write_tags(tags) if tags.is_a? Array
    end

    private

    def read_item(id)
      result = redis.get(id)
      result = unmarshal(result)
      return nil unless result.is_a?(CacheRedis::Item)
      if smell?(result) || invalid_tags?(result.tags)
        return nil if lock?(id, result.lifetime)
      end
      result
    end

    def write_tags(tags)
      time_now = Time.now.to_i
      tags.each_with_object({}) do |tag, hash|
        redis.set("#{tag}_tag", time_now)
        hash.store(tag, time_now)
      end
    end

    def invalid_tags?(tags)
      return false if tags.empty?
      keys = tags.keys.map { |k| "#{k}_tag" }
      return true unless tags.values == redis.mget(*keys).map(&:to_i)
      false
    end

    def smell?(data)
      Time.now.to_i > data.creation_time + data.lifetime
    end

    def lock?(id, lifetime)
      lock(id, lifetime) == 1
    end

    def lock(id, lifetime)
      redis.eval(
        lua_acquire_script,
        keys: [
          "#{id}_lock"
        ],
        argv: [
          Time.now.to_i,
          lifetime
        ]
      )
    end

    def unlock(id)
      redis.del("#{id}_lock")
    end

    # KEYS[1] - lock name
    # ARGV[1] - token
    # ARGV[2] - timeout in milliseconds
    # return 1 if lock was acquired, otherwise 0
    def lua_acquire_script
      <<-EOF
        if redis.call('setnx', KEYS[1], ARGV[1]) == 1 then
            if ARGV[2] ~= '' then
                redis.call('pexpire', KEYS[1], ARGV[2])
            end
            return 1
        end
        return 0
      EOF
    end

    def marshal(data)
      Marshal.dump(data)
    end

    def unmarshal(data)
      return nil if data.nil?
      Marshal.load(data)
    end

    def lifetime(time)
      @options[:dogpile_prevention] ? time * @options[:dogpile_prevention_factor] : time
    end
  end
end
