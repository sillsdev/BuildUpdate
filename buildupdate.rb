#!/usr/bin/env ruby
require 'rubygems'
require 'rest_client'
require 'optparse'
require 'nori'

require 'awesome_print'

class String
  def to_bool
    return true if self == true || self =~ (/(true|t|yes|y|1)$/i)
    return false if self == false || self.blank? || self =~ (/(false|f|no|n|0)$/i)
    raise ArgumentError.new("invalid value for Boolean: \"#{self}\"")
  end

  def glob?
    return self.count("*?") > 0
  end
end

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

# In cases were there maybe one or more sub-elements of an element, this makes sure
# that it is consistent.
def ensure_array_of_objects(obj)
  obj.is_a?(Array) ? obj : [ obj ]
end

class ArtifactDependency
  attr_accessor :clean_destination_directory, :path_rules, :revision_name, :revision_value, :build_type

  def initialize(props)
    @clean_destination_directory = false
    @path_rules =  {}
    props.each do |p|
      name = p[:@name]
      value = p[:@value]
      case name
      when "cleanDestinationDirectory"
        @clean_destination_directory = value.to_bool
      when "pathRules"
        value.split("\n").each do |line|
          (src,dst) = line.split("=>")
          @path_rules[src] = dst
        end
      when "source_buildTypeId"
        @build_type = value
      else
        self.send("#{name.snakecase}=", value)
      end
    end
  end
end

class ArtifactDependencies
  attr_accessor :dependencies
  def initialize(xml)
    @dependencies = []
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    deps = ensure_array_of_objects( parser.parse(xml)[:artifact_dependencies][:artifact_dependency])
    deps.each do |d|
      props = d[:properties][:property]
      obj = ArtifactDependency.new(props)
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
    builds = ensure_array_of_objects(parser.parse(xml)[:build_types][:build_type])
    builds.each do |p|
      name = p[:@name]
      id = p[:@id]
      @ids[name] = id
      @names[id] = name
    end
  end
end

class BuildType
  attr_reader :project_name, :build_name, :url, :vcs_root_id
  def initialize(xml)
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    build = parser.parse(xml)[:build_type]
    @build_name = build[:@name]
    @url = build[:@web_url]
    @project_name = build[:project][:@name]
    begin
      @vcs_root_id = build[:vcs_root_entries][:vcs_root_entry][:@id]
    rescue
      verbose("No VCS Root defined for project=#{@project_name}, build_name=#{@build_name}")
    end
  end
end

class VCSRoot
  attr_reader :repository_path, :branch_name
  def initialize(xml)
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    props = parser.parse(xml)[:vcs_root][:properties][:property]
    props.each do |p|
      name = p[:@name]
      value = p[:@value]
      case name
      when "repositoryPath"
        @repository_path = value
      when "branchName"
        @branch_name = value
      end
    end
  end

end

class IvyArtifacts
  attr_reader :artifacts
  def initialize(xml)
    @artifacts = []
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    artifacts = ensure_array_of_objects(parser.parse(xml)[:ivy_module][:publications][:artifact])
    artifacts.each do |a|
      @artifacts.push("#{a[:@name]}.#{a[:@ext]}")
    end
  end
end

class BuildUpdateScript
  attr_accessor :header_lines, :options, :lines
  def initialize(path)
    @path = path
    @header_lines = []
    @options = {}
    @lines = []
    if File.exist?(path)
      re = /#\s*([^=]+)=(.*)$/
      File.open(@path, 'r').each do |l|
        break unless /^#/.match(l)
        @header_lines.push(l)
        m = re.match(l)
        unless m.nil? || m.length < 2
          @options[m[1].to_sym] = m[2]
        end
      end
    end
  end

  def update
    File.open(@path, 'w') do |f|
      f.puts(@header_lines)
      f.puts(@lines)
    end
  end

  def to_s
    header_lines.join + "\n" + lines.join("\n")
  end
end

def os
  @os ||= (
  host_os = RbConfig::CONFIG['host_os']
  case host_os
    when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      :windows
    when /darwin|mac os/
      :osx
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

$options = { :server => "build.palaso.org", :verbose => false}

def verbose(message)
  $stderr.puts message if $options[:verbose]
end

def debug(message)
  $stderr.puts "DEBUG: #{message}"
end

script = BuildUpdateScript.new("buildupdate.sh")
$options.merge!(script.options)

OptionParser.new do |opts|
  opts.banner = "Usage: buildupdate.rb [options]"
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    $options[:verbose] = v
  end

  opts.on("-s", "--server [SERVER]", "Specify the TeamCity Server Hostname") do |s|
    $options[:server] = s
  end

  # Really need to look up the build type based on environment
  opts.on("-b", "--build_type [BUILD_TYPE]", "Specify the BuildType in TeamCity") do |bt|
    abort("Invalid build_type: #{b}.  Should be bt[0-9]+") if b !~ /^bt[0-9]+/
    $options[:build_type] = bt
  end

  opts.on("-c", "--create", "Create a new buildupdate.sh file based on arguments")
end.parse!

verbose("Options: #{$options}")

server = $options[:server]
rest_url = "http://#{server}/guestAuth/app/rest/7.0"
rest_api = RestClient::Resource.new(rest_url) #, :headers => { :accept => "application/json"})
repo_url = "http://#{server}/guestAuth/repository"
repo_api = RestClient::Resource.new(repo_url)

if $options[:build_type].nil?
  # Lookup build_type based on project name and build name
  project_name = os_specific?(:project, $options)
  abort("You need to specify project in buildupdate.sh!") if project_name.nil?

  build_name = os_specific?(:build, $options)
  abort("You need to specify build or build.#{os} in buildupdate.sh!") if build_name.nil?

  projects_xml = rest_api["/projects"].get
  projects = TeamCityProjects.new(projects_xml)
  project_id = projects.ids[project_name]
  abort("Project '#{project_name}' not Found!\nPossible Names:\n  #{projects.names.values.join("\n  ")}") if project_id.nil?

  builds_xml = rest_api["/projects/id:#{project_id}/buildTypes"].get
  builds = TeamCityBuilds.new(builds_xml)
  build_type = builds.ids[build_name]
  abort("Build '#{build_name}' not Found!\nPossible Names:\n  #{builds.names.values.join("\n  ")}") if build_type.nil?
  verbose("Selected: project=#{project_name}, build_name=#{build_name} => build_type=#{build_type}")
else
  build_type = $options[:build_type]
  verbose("Config: build_type=#{build_type}")
end
abort("You need to specify project/build or build_type in buildupdate.sh!") if build_type.nil?


deps_xml = rest_api["/buildTypes/id:#{build_type}/artifact-dependencies"].get

abort("BuildType '#{build_type}' not Found!") if deps_xml.nil?

deps = ArtifactDependencies.new(deps_xml)
abort("Dependencies not found!") if deps.nil?

deps.dependencies.select { |dep| dep.clean_destination_directory }.each do |d|
  script.lines.push("# clean destination directories")
  d.path_rules.each do |src,dst|
    script.lines.push("rm -rf #{dst}")
  end
end

build_xml = rest_api["/buildTypes/id:#{build_type}"].get
build = BuildType.new(build_xml)

unless build.vcs_root_id.nil?
  vcs_xml = rest_api["/vcs-roots/id:#{build.vcs_root_id}"].get
  vcs = VCSRoot.new(vcs_xml)
end

script.lines.push("\n"\
    "#### Results ####\n"\
    "# build: #{build.build_name} (#{build_type})\n"\
    "# project: #{build.project_name}\n"\
    "# URL: #{build.url}\n")
unless vcs.nil?
  script.lines.push("# VCS: #{vcs.repository_path} [#{vcs.branch_name}]")
end
script.lines.push("# dependencies:")
deps.dependencies.each_with_index do |d, i|
  build_xml = rest_api["/buildTypes/id:#{d.build_type}"].get
  build = BuildType.new(build_xml)

  vcs_xml = rest_api["/vcs-roots/id:#{build.vcs_root_id}"].get
  vcs = VCSRoot.new(vcs_xml)

  script.lines.push(
  "# [#{i}] build: #{build.build_name} (#{d.build_type})\n"\
  "#     project: #{build.project_name}\n"\
  "#     URL: #{build.url}\n"\
  "#     VCS: #{vcs.repository_path} [#{vcs.branch_name}]\n"\
  "#     clean: #{d.clean_destination_directory}\n"\
  "#     revision: #{d.revision_value}\n"\
  "#     paths: #{d.path_rules}")
end


script.lines.push("\n# download artifact dependencies")
deps.dependencies.each do |d|
  d.path_rules.each do |src,dst|
    files = []
    if src.glob?
      ivy_xml = repo_api["/download/#{d.build_type}/#{d.revision_value}/teamcity-ivy.xml"].get
      ivy = IvyArtifacts.new(ivy_xml)
      matching_files = ivy.artifacts.select { |a| File.fnmatch(src, a, File::FNM_DOTMATCH)}
      files.concat(matching_files)
    else
      files.push(src)
    end


    curl = "curl -L"
    files.each do |f|

      if src.end_with?("/**")
              # e.g. f = foo/bar/baz.dll and src = foo/** => bar/baz.dll
        dst_file = File.join(dst,f.sub(src.sub("**",""),""))
        dst_dir = File.dirname(dst_file)
      elsif src.include?("**")
        abort("Can't handle recursive match that isn't at the end: #{src}")
      else
        dst_file = File.join(dst, f)
        dst_dir = dst
      end
      script.lines.push "mkdir -p #{dst_dir}"
      script.lines.push "#{curl} -o #{dst_file} #{repo_url}/download/#{d.build_type}/#{d.revision_value}/#{f}"
    end


    # For each src, create a REST call to download the artifact and then extract to destination
    #script.lines.push("#{curl} -o #{d.build_type}.zip ${repo_url}/downloadAll/bt228/#{d.revisionValue}")
    #script.lines.push("build_type=#{d.build_type}: src=#{src}, dst=#{dst}")
   #site[/]
  end
end

script.update
