#! ruby

require 'json'
require 'yaml'
require "net/http"
require "uri"

is_testing = ARGV[0] == '--testing'

# list of biogems not starting with bio- (bio dash)
ADD = %w{ bio ruby-ensembl-api genfrag eutils dna_sequence_aligner intermine intermine-bio scaffolder }

print "# Generated by #{__FILE__} #{Time.now}\n"
print "# Using Ruby ",RUBY_VERSION,"\n"

projects = Hash.new

$stderr.print "Querying gem list\n"
list = `gem list -r --no-versions bio-`.split(/\n/)
list += ADD
if is_testing
  list = ['bio-assembly']
end

def check_url url
  if url =~ /^http:\/\//
    $stderr.print "Checking #{url}..."
    begin
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      if response.code.to_i == 200 and response.body !~ /301 Moved/
        $stderr.print "pass!\n"
        return url
      end
    rescue
      $stderr.print $!
    end
    $stderr.print "failed!\n"
  end
  nil
end

def get_http_body url
  uri = URI.parse(url)
  $stderr.print "Fetching #{url}\n"
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  if response.code.to_i != 200
    raise Exception.new("page not found "+url)
  end
  response.body
end

def get_versions name
  url = "http://rubygems.org/api/v1/versions/#{name}.json"
  versions = JSON.parse(get_http_body(url))
  versions
end

def get_downloads90 name, versions
  version_numbers = versions.map { | ver | ver['number'] }
  total = 0
  version_numbers.each do | ver |
    url="http://rubygems.org/api/v1/versions/#{name}-#{ver}/downloads.yaml"
    text = get_http_body(url)
    dated_stats = YAML::load(text)
    stats = dated_stats.map { | i | i[1] }
    ver_total90 = stats.inject {|sum, n| sum + n } 
    total += ver_total90
  end
  total
end

def get_github_issues github_uri
  tokens = github_uri.split(/\//).reverse
  project = tokens[0]
  user = tokens[1]
  url = "http://github.com/api/v2/json/issues/list/#{user}/#{project}/open"
  $stderr.print url
  issues = JSON.parse(get_http_body(url))
  $stderr.print issues['issues'].size, "\n"
  issues['issues']
end

list.each do | name |
  $stderr.print name,"\n"
  info = Hash.new
  fetch = `gem specification -r #{name.strip}`
  spec = YAML::load(fetch)
  # print fetch
  ivars = spec.ivars
  info[:authors] = ivars["authors"]
  info[:summary] = ivars["summary"]
  ver = ivars["version"].ivars['version']
  info[:version] = ver
  info[:release_date] = ivars["date"]
  # set homepage
  info[:homepage] = ivars["homepage"]
  info[:licenses] = ivars["licenses"]
  info[:description] = ivars["description"]
  # Now query rubygems.org directly
  uri = URI.parse("http://rubygems.org/api/v1/gems/#{name}.yaml")
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  if response.code.to_i==200
    # print response.body       
    biogems = YAML::load(response.body)
    info[:downloads] = biogems["downloads"]
    info[:version_downloads] = biogems["version_downloads"]
    info[:gem_uri] = biogems["gem_uri"]
    info[:homepage_uri] = check_url(biogems["homepage_uri"])
    info[:project_uri] = check_url(biogems["project_uri"])
    info[:source_code_uri] = biogems["sourcecode_uri"]
    info[:docs_uri] = check_url(biogems["documentation_uri"])
    info[:dependencies] = biogems["dependencies"]
    # query for recent downloads
  else
    raise Exception.new("Response code for #{name} is "+response.code)
  end
  info[:docs_uri] = "http://rubydoc.info/gems/#{name}/#{ver}/frames" if not info[:docs_uri]
  versions = get_versions(name)
  info[:downloads90] = get_downloads90(name, versions)
  # if a gem is less than one month old, mark it as new
  if versions.size <= 5
    is_new = true
    versions.each do | ver |
      date = ver['built_at']
      date.to_s =~ /^(\d\d\d\d)\-(\d\d)\-(\d\d)/
      t = Time.new($1.to_i,$2.to_i,$3.to_i)
      if Time.now - t > 30*24*3600
        is_new = false
        break
      end
    end
    info[:status] = 'new' if is_new
  end
  # Now parse etc/biogems/name.yaml
  fn = "./etc/biogems/#{name}.yaml"
  if File.exist?(fn)
    added = YAML::load(File.new(fn).read)
    info = info.merge(added)
  end
  # Replace http with https
  for uri in [:source_code_uri, :homepage, :homepage_uri, :project_uri] do
    if info[uri] =~ /^http:\/\/github/
      info[uri] = info[uri].sub(/^http:\/\/github\.com/,"https://github.com")
    end
  end

  # Check github issues
  # print info
  for uri in [:source_code_uri, :homepage, :homepage_uri, :project_uri] do
    if info[uri] =~ /^https:\/\/github\.com/
      info[:num_issues] = get_github_issues(info[uri]).size
      break if info[:num_issues] > 0
    end
  end

  projects[name] = info
end
print projects.to_yaml
