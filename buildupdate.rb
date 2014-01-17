#!/usr/bin/env ruby
require 'rubygems'
require 'rest_client'
require 'optparse'
require 'nori'
require 'set'

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
  attr_reader :project_name, :build_name, :url, :vcs_root_id, :parameters
  def initialize(xml)
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    build = parser.parse(xml)[:build_type]
    @build_name = build[:@name]
    @url = build[:@web_url]
    @project_name = build[:project][:@name]
    @parameters = {}

    begin
      parameters = build[:parameters][:property]
      parameters.each do |p|
        name = p[:@name]
        value = p[:@value]
        @parameters[name] = value
      end
    rescue
    end
    begin
      @vcs_root_id = build[:vcs_root_entries][:vcs_root_entry][:@id]
    rescue
      verbose("Note: No VCS Root defined for project=#{@project_name}, build_name=#{@build_name}")
    end
  end
  def resolve(str)
    if str =~ /%[^%]+%/
      key = str.gsub(/%/,"")
      str = @parameters[key]
    end
    str
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
      when "url"
        @repository_path = value
      when "branch"
        @branch_name = value
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

class ScriptActions
  attr_accessor :download_app
  @download_app = "auto"
  @@subclasses = {}
  def self.create type
    c = @@subclasses[type.to_sym]
    if c
      c.new
    else
      raise "Bad script file type: #{type}"
    end
  end

  def self.register_script name
    @@subclasses[name] = self
  end

  def file_header
    ""
  end

  def begin_lines
    ""
  end

  def end_lines
    comment("End of script")
  end

  def comment_prefix
    raise "Not Implemented!"
  end

  def comment(str)
     comment_prefix + " " + str
  end

  def mkdir(dir)
    raise "Not Implemented!"
  end

  def rmdir(dir)
    raise "Not Implemented!"
  end

  def variable(var, value)
    comment_prefix + " #{var}=#{value}"
  end

  def parse_variable(line)
    m = /#{comment_prefix}([^=]+)=(.*)$/.match(line)
    unless m.nil? || m.length < 2
      { m[1].strip.to_sym => m[2].strip}
    end
  end

  def curl_update(src, dst)
    "curl -# -L -z #{dst} -o #{dst} #{src}"
  end

  def curl_replace(src, dst)
    "curl -# -L -o #{dst} #{src}"
  end

  def wget_update(src, dst)
    "wget -q -L -N #{src}"
  end

end

class BashScriptActions < ScriptActions
  def file_header
    "#!/bin/bash"
  end

  def begin_lines
    "\n" + comment("*** Functions ***\n") + 
    functions
  end

  def functions
    <<-eos
copy_auto() {
	where_curl=$(type -P curl)
	where_wget=$(type -P wget)
	if [ "$where_curl" != "" ]
	then
		copy_curl $1 $2
	elif [ "$where_wget" != "" ]
	then
		copy_wget $1 $2
	else
		echo "Missing curl or wget"
		exit 1
	fi
}

copy_curl() {
	echo "curl: $2 <= $1"
	if [ -e "$2" ]
	then
		#{curl_update('$1', '$2')}
	else
		#{curl_replace('$1', '$2')}
	fi
}

copy_wget() {
	echo "wget: $2 <= $1"
	f=$(basename $2)
	d=$(dirname $2)
	cd $d
	#{wget_update('$1', '$f')}
	cd -
}
    eos
  end

  def comment_prefix
    "#"
  end

  def unix_path(dir)
    dir.gsub!('\\','/')
    unless dir[/\s+/].nil?
      dir = "\"#{dir}\""
    end

    return dir
  end

  def mkdir(dir)
    "mkdir -p #{unix_path(dir)}"
  end

  def rmdir(dir)
    "rm -rf #{unix_path(dir)}"
  end

  def download(src,dst)
    "copy_#{@download_app} #{src} #{unix_path(dst)}"
  end

  register_script :sh
end

class CmdScriptActions < ScriptActions
  def file_header
    "@echo off"
  end

  def end_lines
    "goto:eof\n\n" + functions + comment("End of Script")
  end

  def functions
    <<-eos
:copy_curl
echo. %~2 
echo. %~1
if exist %~2 (
#{curl_update('%~1', '%~2')}
) else (
#{curl_replace('%~1', '%~2')}
)
goto:eof

:copy_wget
echo. %~2 
echo. %~1
pushd %~2\\..\\
#{wget_update('%~1', '%~2')}
popd
goto:eof
    eos
  end

  def comment_prefix
    "REM"
  end

  def windows_path(dir)
    dir.gsub!('/', '\\')
    unless dir[/\s+/].nil?
      dir = "\"#{dir}\""
    end

    return dir
  end

  def mkdir(dir)
    win_dir = windows_path(dir)
    "if not exist #{win_dir}\\nul mkdir #{win_dir}"
  end

  def rmdir(dir)
    win_dir = windows_path(dir)
    "del /f/s/q #{win_dir}"
    "rmdir #{win_dir}"
  end

  def download(src,dst)
    "call:copy_#{@download_app} #{src} #{windows_path(dst)}"
  end

  register_script :bat
end

class BuildUpdateScript
  attr_accessor :header_lines, :options, :lines, :path, :root, :actions
  def initialize(path)
    type = path.split('.')[-1]
    @actions = ScriptActions.create(type)
    @path = path
    @header_lines = []
    @options = {}
    @lines = []
    @root = ""
    if File.exist?(path)
      f = File.open(@path, 'r')
      line = f.gets.chomp
      raise "Invalid Header: #{line}\nShould be: #{@actions.file_header}" unless line == @actions.file_header
      while (line = f.gets)
        variable = @actions.parse_variable(line)
        break if variable.nil?
        @header_lines.push(line)
        @options.merge!(variable)
      end
    end
  end

  def set_header(server, project, build, build_type, root_dir)
    @header_lines = [
        @actions.file_header,
        @actions.variable("server", server)
    ]
    if project.nil? && build.nil?
      @header_lines.push(@actions.variable("build_type",build_type))
    else
      @header_lines.push(@actions.variable("project",project))
      @header_lines.push(@actions.variable("build", build))
    end
    @header_lines.push(@actions.variable("root_dir", root_dir)) unless root_dir.nil?
  end

  def update
    File.open(@path, 'w') do |f|
      f.puts(@header_lines)
      f.puts(@actions.begin_lines)
      f.puts(@lines)
      f.puts(@actions.end_lines)
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

$options = { :server => "build.palaso.org", :verbose => false, :file => "buildupdate.sh", :root_dir => ".", :download_app => "auto"}

def verbose(message)
  $stderr.puts message if $options[:verbose]
end

def debug(message)
  $stderr.puts "DEBUG: #{message}"
end


cmd_options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: buildupdate.rb [options]"
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    cmd_options[:verbose] = v
  end

  opts.on("-d", "--download_app APP", "Specify the app to use to download the content") do |d|
    abort("Invalid app: #{d}.  Should be curl or wget") if d !~ /^(curl|wget)$/
    cmd_options[:download_app] = d
  end

  opts.on("-s", "--server SERVER", "Specify the TeamCity Server Hostname") do |s|
    cmd_options[:server] = s
  end

  opts.on("-p", "--project PROJECT", "Specify the Project in TeamCity") do |p|
    cmd_options[:project] = p
  end

  opts.on("-b", "--build BUILD", "Specify the Build within a Project in TeamCity") do |b|
    cmd_options[:build] = b
  end

  opts.on("-r", "--root_dir ROOT", "Specify the root dir to execute shell commands") do |r|
    cmd_options[:root_dir] = r
  end

  # Really need to look up the build type based on environment
  opts.on("-t", "--build_type BUILD_TYPE", "Specify the BuildType in TeamCity") do |t|
    abort("Invalid build_type: #{t}.  Should be bt[0-9]+") if t !~ /^bt[0-9]+/
    cmd_options[:build_type] = t
  end

  opts.on("-f", "--file SHELL_FILE", "Specify the shell file to update (default: buildupdate.sh") do |f|
    # This is a special one.  We want to override where other options are read from...
    $options[:file] = f
  end
end.parse!


$script = BuildUpdateScript.new($options[:file])
def comment(str)
  $script.actions.comment(str)
end
$options.merge!($script.options)
$options.merge!(cmd_options)

$script.actions.download_app = $options[:download_app]
root_dir = $options[:root_dir]

verbose("Options: #{$options}")

server = $options[:server]
rest_url = "http://#{server}/guestAuth/app/rest/7.0"
rest_api = RestClient::Resource.new(rest_url) #, :headers => { :accept => "application/json"})
repo_url = "http://#{server}/guestAuth/repository"
repo_api = RestClient::Resource.new(repo_url)

if $options[:build_type].nil?
  projects_xml = rest_api["/projects"].get
  projects = TeamCityProjects.new(projects_xml)

  # Lookup build_type based on project name and build name
  project_name = os_specific?(:project, $options)
  abort("You need to specify project!\nPossible Names:\n  #{projects.names.values.join("\n  ")}") if project_name.nil?

  project_id = projects.ids[project_name]
  abort("Project '#{project_name}' not Found!\nPossible Names:\n  #{projects.names.values.join("\n  ")}") if project_id.nil?

  builds_xml = rest_api["/projects/id:#{project_id}/buildTypes"].get
  builds = TeamCityBuilds.new(builds_xml)

  build_name = os_specific?(:build, $options)
  abort("You need to specify build!\nPossible Name:\n  #{builds.names.values.join("\n  ")}") if build_name.nil?

  build_type = builds.ids[build_name]
  abort("Build '#{build_name}' not Found!\nPossible Names:\n  #{builds.names.values.join("\n  ")}") if build_type.nil?
  verbose("Selected: project=#{project_name}, build_name=#{build_name} => build_type=#{build_type}")
else
  build_type = $options[:build_type]
  verbose("Config: build_type=#{build_type}")
end
abort("You need to specify project/build or build_type in #{$script.path}!") if build_type.nil?


deps_xml = rest_api["/buildTypes/id:#{build_type}/artifact-dependencies"].get

abort("BuildType '#{build_type}' not Found!") if deps_xml.nil?

deps = ArtifactDependencies.new(deps_xml)
abort("Dependencies not found!") if deps.nil?

deps.dependencies.select { |dep| dep.clean_destination_directory }.each do |d|
  $script.lines.push(comment("clean destination directories"))
  d.path_rules.each do |src,dst|
    $script.lines.push($script.actions.rmdir("#{root_dir}/#{dst}"))
  end
end

build_xml = rest_api["/buildTypes/id:#{build_type}"].get
build = BuildType.new(build_xml)

unless build.vcs_root_id.nil?
  req = "/vcs-roots/id:#{build.vcs_root_id}"
  vcs_xml = rest_api[req].get
  verbose("VCS req:#{req}\nxml:#{vcs_xml}")
  vcs = VCSRoot.new(vcs_xml)
end

$script.lines.push("")
[
    "*** Results ***",
    "build: #{build.build_name} (#{build_type})",
    "project: #{build.project_name}",
    "URL: #{build.url}"
].each { |line| $script.lines.push(comment(line)) }

unless vcs.nil?
  $script.lines.push(comment("VCS: #{vcs.repository_path} [#{build.resolve(vcs.branch_name)}]"))
end

$script.lines.push(comment("dependencies:"))
deps.dependencies.each_with_index do |d, i|
  build_xml = rest_api["/buildTypes/id:#{d.build_type}"].get
  build = BuildType.new(build_xml)

  [
    "[#{i}] build: #{build.build_name} (#{d.build_type})",
    "    project: #{build.project_name}",
    "    URL: #{build.url}",
    "    clean: #{d.clean_destination_directory}",
    "    revision: #{d.revision_value}",
    "    paths: #{d.path_rules}"
  ].each { |line| $script.lines.push(comment(line)) }

  unless build.vcs_root_id.nil?
    vcs_xml = rest_api["/vcs-roots/id:#{build.vcs_root_id}"].get
    vcs = VCSRoot.new(vcs_xml)
    $script.lines.push(comment("    VCS: #{vcs.repository_path} [#{build.resolve(vcs.branch_name)}]"))
  end
end


dst_dirs = Set.new
dst_files = []
deps.dependencies.each do |d|
  d.path_rules.each do |key,dst|
    src = key.gsub("\\", "/")
    dst.gsub!("\\", "/")
    files = []
    if src.glob?
      ivy_xml = repo_api["/download/#{d.build_type}/#{d.revision_value}/teamcity-ivy.xml"].get
      ivy = IvyArtifacts.new(ivy_xml)
      matching_files = ivy.artifacts.select { |a| File.fnmatch(src, a, File::FNM_DOTMATCH)}
      files.concat(matching_files)
    else
      files.push(src)
    end

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
      dst_dirs << dst_dir
      dst_files << ["#{repo_url}/download/#{d.build_type}/#{d.revision_value}/#{f}", "#{root_dir}/#{dst_file}"]
    end
  end
end

$script.lines.push("")
$script.lines.push(comment("make sure output directories exist"))
dst_dirs.each do |dir|
  $script.lines.push($script.actions.mkdir("#{root_dir}/#{dir}"))
end

$script.lines.push("")
$script.lines.push(comment("download artifact dependencies"))
dst_files.each do |pair|
  $script.lines.push($script.actions.download(pair[0], pair[1]))
end

$script.set_header($options[:server], $options[:project], $options[:build], $options[:build_type], $options[:root_dir])
$script.update
