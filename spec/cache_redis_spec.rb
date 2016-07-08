require './spec/spec_helper'
require './lib/cache-redis'

RSpec.describe CacheRedis::Cache do
  before do
    @redis = instance_double('Redis')
  end

  context '#read' do
    let(:cache) { CacheRedis::Cache.new(@redis) }

    it 'returns unmarshal value' do
      id = rand(1..1000)
      value = ['string', 789]
      item = CacheRedis::Item.new(value: value)
      expect(@redis).to receive(:get).with(id).and_return(Marshal.dump(item))
      data = cache.read(id)
      expect(data).to eq value
    end

    it 'returns nil' do
      id = rand(1..1000)
      value = nil
      expect(@redis).to receive(:get).with(id).and_return(value)
      expect(cache.read(id)).to be_nil
    end

    it 'returns nil when tags is not valid' do
      id = rand(1..1000)
      time = Time.now.to_i
      tags = { 'tag_1' => time, 'tag_2' => time }
      item = CacheRedis::Item.new(value: ['string', 789], tags: tags)
      expect(@redis).to receive(:get).with(id).and_return(Marshal.dump(item))
      keys = tags.keys.map { |k| "#{k}_tag" }
      expect(@redis).to receive(:mget).with(*keys).and_return([time])
      expect(@redis).to receive(:eval).and_return(1)
      expect(cache.read(id)).to be_nil
    end

    it 'returns data when tags is valid' do
      id = rand(1..1000)
      value = ['string', 789]
      time = Time.now.to_i
      tags = { 'tag_1' => time, 'tag_2' => time }
      item = CacheRedis::Item.new(value: ['string', 789], tags: tags)
      expect(@redis).to receive(:get).with(id).and_return(Marshal.dump(item))
      keys = tags.keys.map { |k| "#{k}_tag" }
      expect(@redis).to receive(:mget).with(*keys).and_return([time, time])
      data = cache.read(id)
      expect(data).to eq value
    end
  end

  context '#write' do
    let(:cache) { CacheRedis::Cache.new(@redis) }
    let(:id) { rand(1..100) }
    let(:value) { ['string', 789] }
    let(:item) { CacheRedis::Item.new }

    it 'lifetime twice as much' do
      item.value = value
      fact_lifetime = CacheRedis::Item::DEFAULT_LIFETIME * 2
      data = Marshal.dump(item)
      expect(@redis).to receive(:setex).with(id, fact_lifetime, data).and_return('OK')
      expect(@redis).to receive(:del).with("#{id}_lock")
      expect(cache.write(id, value)).to eq true
    end

    it 'lifetime = 2 * expire_in' do
      item.value = value
      expire_in = 3600
      item.lifetime = expire_in
      fact_lifetime = expire_in * 2
      data = Marshal.dump(item)
      expect(@redis).to receive(:setex).with(id, fact_lifetime, data).and_return('OK')
      expect(@redis).to receive(:del).with("#{id}_lock")
      expect(cache.write(id, value, expire_in: expire_in)).to eq true
    end

    it 'lifetime = expire_in' do
      cache_dogpile = CacheRedis::Cache.new(@redis, dogpile_prevention: false)
      expire_in = 3600
      item.value = value
      item.lifetime = expire_in
      data = Marshal.dump(item)
      expect(@redis).to receive(:setex).with(id, expire_in, data).and_return('OK')
      expect(@redis).to receive(:del).with("#{id}_lock")
      expect(cache_dogpile.write(id, value, expire_in: expire_in)).to eq true
    end

    it 'with tags' do
      tags = %w(tagone tagtwo)
      time = Time.now.to_i
      expire_in = 10
      value = rand(1..1000)
      item = CacheRedis::Item.new(
        value: value,
        tags: { tags[0] => time, tags[1] => time },
        lifetime: expire_in)
      expect(@redis).to receive(:set).with("#{tags[0]}_tag", time)
      expect(@redis).to receive(:set).with("#{tags[1]}_tag", time)
      expect(@redis).to receive(:setex).with(id, expire_in * 2, Marshal.dump(item)).and_return('OK')
      expect(@redis).to receive(:del).with("#{id}_lock")
      expect(cache.write(id, value, tags: tags, expire_in: expire_in)).to eq true
    end
  end

  context '#fetch' do
    let(:cache) { CacheRedis::Cache.new(@redis) }
    let(:id) { rand(1..1000) }

    it 'returns data' do
      data = rand(10..100)
      item = CacheRedis::Item.new(value: data)
      expect(@redis).to receive(:get).with(id).and_return(Marshal.dump(item))
      expect(cache.fetch(id)).to eq data
    end

    it 'returns output of the block without cached data' do
      value_block = rand(100..1000)
      block_generate_data = -> { value_block }
      expect(@redis).to receive(:get).with(id).and_return(nil)
      expect(@redis).to receive(:setex).and_return('OK')
      expect(@redis).to receive(:del).with("#{id}_lock")
      expect(cache.fetch(id, {}, &block_generate_data)).to eq value_block
    end

    it 'returns output of the block and cached data' do
      value_block = rand(100..1000)
      block_generate_data = -> { value_block }
      lock_key = "#{id}_lock"
      item = CacheRedis::Item.new
      item.value = value_block
      fact_lifetime = CacheRedis::Item::DEFAULT_LIFETIME * 2
      data = Marshal.dump(item)
      expect(@redis).to receive(:get).with(id).and_return(nil)
      expect(@redis).to receive(:setex).with(id, fact_lifetime, data).and_return('OK')
      expect(@redis).to receive(:del).with(lock_key)
      expect(cache.fetch(id, {}, &block_generate_data)).to eq value_block
    end

    it 'replace data in cache' do
      old_item = CacheRedis::Item.new(
        value: rand(1..100),
        lifetime: -30
      )
      value_block = rand(100..1000)
      block_generate_data = -> { value_block }
      lock_key = "#{id}_lock"
      item = CacheRedis::Item.new
      item.value = value_block
      fact_lifetime = CacheRedis::Item::DEFAULT_LIFETIME * 2
      expect(@redis).to receive(:get).with(id).and_return(Marshal.dump(old_item))
      expect(@redis).to receive(:eval).and_return(1)
      expect(@redis).to receive(:setex).with(id, fact_lifetime, Marshal.dump(item)).and_return('OK')
      expect(@redis).to receive(:del).with(lock_key)
      expect(cache.fetch(id, {}, &block_generate_data)).to eq value_block
    end
  end

  context '#clean_by_tags' do
    let(:cache) { CacheRedis::Cache.new(@redis) }

    it 'update time tags' do
      time = Time.now.to_i
      tags = %w(tag_1 tag_2)
      expected_hash = { tags.first => time }
      expect(@redis).to receive(:set).with("#{tags.first}_tag", time)
      expect(cache.clean_by_tags([tags.first])).to eq expected_hash
    end
  end

  context '#delete' do
    let(:cache) { CacheRedis::Cache.new(@redis) }

    it 'delete id' do
      id = rand(1...1000)
      expect(@redis).to receive(:del).with(id).and_return(1)
      expect(cache.delete(id)).to eq 1
    end
  end
end
