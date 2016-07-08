Gem::Specification.new do |s|
  s.name        = 'cache-redis'
  s.version     = File.read('VERSION')
  s.platform    = Gem::Platform::RUBY
  s.date        = '2016-03-15'
  s.summary     = 'Cache Redis'
  s.description = 'Cache Redis library'
  s.authors     = ['Anton Kosolapov']
  s.email       = 'anvkos@ya.ru'

  s.homepage    = 'https://anvkos@bitbucket.org/anvkos/cache-redis-rb.git'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 2.2.1'

  s.files       = [
    'lib/cache_redis/item.rb',
    'lib/cache_redis/cache.rb',
    'lib/cache-redis.rb'
  ]
  s.test_files  = ['spec/cache_redis_spec.rb']
  s.extra_rdoc_files = ['README.md']
  s.require_path = 'lib'

  s.add_runtime_dependency 'redis', '~> 3.2'

  s.add_development_dependency 'rspec', '~> 3.4'
  s.add_development_dependency 'simplecov', '~> 0.11'
end
