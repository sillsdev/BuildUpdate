#!/usr/bin/env ruby
require 'rubygems'
require 'rest_client'
require 'optparse'
require 'nokogiri'
require 'nori'
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

options = {:server => "build.palaso.org", :bt => "bt232"}

OptionParser.new do |opts|
  opts.banner = "Usage: buildupdate.rb [options]"
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end

  opts.on("-s", "--server [SERVER]", "Specify the TeamCity Server Hostname") do |s|
    options[:server] = s
  end

  # Really need to look up the build type based on environment
  opts.on("-b", "--build_type [BUILD_TYPE]", "Specify the BuildType in TeamCity") do |b|
    abort("Invalid build_type: #{b}.  Should be bt[0-9]+") if b !~ /^bt[0-9]+/
    options[:bt] = b
  end
end.parse!

server = options[:server]
bt = options[:bt]

site_url = "http://#{server}/guestAuth/app/rest"
site = RestClient::Resource.new(site_url) #, :headers => { :accept => "application/json"})

deps_xml = site["/buildTypes/id:#{bt}/artifact-dependencies"].get

deps = ArtifactDependencies.new(deps_xml)
deps.dependencies.each do |d|
  #TODO: fetch dependencies
end