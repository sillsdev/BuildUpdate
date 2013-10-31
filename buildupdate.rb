#!/usr/bin/env ruby
require 'rubygems'
require 'rest_client'
require 'optparse'
require 'nori'
require 'fuzz_ball'
require 'awesome_print'

class PropertiesObject
  def initialize(props)
    props.each do |p|
      name = p[:@name]
      value = p[:@value]
      self.singleton_class.send(:attr_accessor, name.to_sym)
      self.send("#{name}=", value)
    end
  end
end

class ArtifactDependencies
  attr_accessor :dependencies
  def initialize(xml)
    @dependencies = []
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    deps = parser.parse(xml)[:artifact_dependencies][:artifact_dependency]
    deps.each do |d|
      props = d[:properties][:property]
      obj = PropertiesObject.new(props)
      @dependencies.push(obj)
    end
  end
end

class TeamCityProjects
  attr_reader :ids, :names
  def initialize(xml)
    @ids = {}
    @names = {}
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    projects = parser.parse(xml)[:projects][:project]
    projects.each do |p|
      name = p[:@name]
      id = p[:@id]
      @ids[name] = id
      @names[id] = name
    end
  end
end

class TeamCityBuilds
  attr_reader :ids, :names
  def initialize(xml)
    @ids = {}
    @names = {}
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    builds = parser.parse(xml)[:build_types][:build_type]
    builds.each do |p|
      name = p[:@name]
      id = p[:@id]
      @ids[name] = id
      @names[id] = name
    end
  end
end


def os
  @os ||= (
  host_os = RbConfig::CONFIG['host_os']
  case host_os
    when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      :windows
    when /darwin|mac os/
      :macosx
    when /linux/
      :linux
    when /solaris|bsd/
      :unix
    else
      raise Error, "unknown os: #{host_os.inspect}"
  end
  )
end

def os_specific?(option, options)
  os_option = "#{option}.#{os}".to_sym
  unless options[os_option].nil?
    options[os_option]
  else
    options[option]
  end
end

options = { :server => "build.palaso.org" }

if File.exist?("buildupdate.sh")
  re = /#\s*([^=]+)=(.*)$/
  File.open("buildupdate.sh").each do |l|
    m = re.match(l)
    unless m.nil? || m.length < 2
      options[m[1].to_sym] = m[2]
    end
  end
end
puts options

OptionParser.new do |opts|
  opts.banner = "Usage: buildupdate.rb [options]"
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end

  opts.on("-s", "--server [SERVER]", "Specify the TeamCity Server Hostname") do |s|
    options[:server] = s
  end

  # Really need to look up the build type based on environment
  opts.on("-b", "--build_type [BUILD_TYPE]", "Specify the BuildType in TeamCity") do |bt|
    abort("Invalid build_type: #{b}.  Should be bt[0-9]+") if b !~ /^bt[0-9]+/
    options[:build_type] = bt
  end
end.parse!

v = options[:verbose]

server = options[:server]
site_url = "http://#{server}/guestAuth/app/rest"
site = RestClient::Resource.new(site_url) #, :headers => { :accept => "application/json"})

if options[:build_type].nil?
  # Lookup build_type based on project name and build name
  project_name = os_specific?(:project, options)
  abort("You need to specify project in buildupdate.sh!") if project_name.nil?
  build_name = os_specific?(:build, options)
  abort("You need to specify build or build.#{os} in buildupdate.sh!") if build_name.nil?

  projects_xml = site["/projects"].get
  projects = TeamCityProjects.new(projects_xml)
  project_id = projects.ids[project_name]
  abort("Project '#{project_name}' not Found!\nPossible Names:\n  #{projects.names.values.join("\n  ")}") if project_id.nil?

  builds_xml = site["/projects/id:#{project_id}/buildTypes"].get
  builds = TeamCityBuilds.new(builds_xml)
  build_type = builds.ids[build_name]
  abort("Build '#{build_name}' not Found!\nPossible Names:\n  #{builds.names.values.join("\n  ")}") if build_type.nil?
else
  build_type = options[:build_type]
end
abort("You need to specify project/build or build_type in buildupdate.sh!") if build_type.nil?

puts build_type
exit

deps_xml = site["/buildTypes/id:#{build_type}/artifact-dependencies"].get
deps = ArtifactDependencies.new(deps_xml)
deps.dependencies.each do |d|
  #TODO: fetch dependencies
end