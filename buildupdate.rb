#!/usr/bin/env ruby
# $Id$
require 'rubygems'
require 'rest_client'
require 'optparse'
require 'nori'
require 'set'
require 'uri'
require 'highline/import'

require 'awesome_print'

path = File.dirname(File.expand_path($0))
require "#{path}/core_ext.rb"
require "#{path}/team_city.rb"
require "#{path}/script_actions.rb"
require "#{path}/update_script.rb"

# these methods are already present in Active Support
module Kernel
  def silence_warnings
    with_warnings(nil) { yield }
  end

  def with_warnings(flag)
    old_verbose, $VERBOSE = $VERBOSE, flag
    yield
  ensure
    $VERBOSE = old_verbose
  end
end unless Kernel.respond_to? :silence_warnings

silence_warnings do
  require 'nokogiri'
  require 'nokogiri-pretty'
end

def pretty_xml(xml)
  begin
    doc = Nokogiri::XML(xml)
    doc.human
  rescue LoadError
    xml
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

$options = { :server => 'build.palaso.org', :verbose => false, :file => 'buildupdate.sh', :root_dir => '.', :download_app => 'auto'}

def verbose(message)
  $stderr.puts message if $options[:verbose]
end

def debug(message)
  $stderr.puts "DEBUG: #{message}"
end

$warned_missing_view = false
def warn_missing_view_build_configuration
  unless $warned_missing_view
    warn "Failed to get VCS information. Enable 'View build configuration settings' for guest user."
    $warned_missing_view = true
  end
end

cmd_options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: buildupdate.rb [options]'
  opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
    cmd_options[:verbose] = v
  end

  opts.on('-d', '--download_app APP', 'Specify the app to use to download the content') do |d|
    abort("Invalid app: #{d}.  Should be curl or wget") if d !~ /^(curl|wget)$/
    cmd_options[:download_app] = d
  end

  opts.on('-s', '--server SERVER', 'Specify the TeamCity Server Hostname') do |s|
    cmd_options[:server] = s
  end

  opts.on('-p', '--project PROJECT', 'Specify the Project in TeamCity') do |p|
    cmd_options[:project] = p
  end

  opts.on('-b', '--build BUILD', 'Specify the Build within a Project in TeamCity') do |b|
    cmd_options[:build] = b
  end

  opts.on('-r', '--root_dir ROOT', 'Specify the root dir to execute shell commands') do |r|
    cmd_options[:root_dir] = r
  end

  opts.on('--tag TAG', 'Specify a specific tagged build to pull dependencies') do |t|
    cmd_options[:build_tag] = t
  end

  # Really need to look up the build type based on environment
  opts.on('-t', '--build_type BUILD_TYPE', 'Specify the BuildType in TeamCity') do |t|
     cmd_options[:build_type] = t
  end

  opts.on('-f', '--file SHELL_FILE', 'Specify the shell file to update (default: buildupdate.sh') do |f|
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
$username = ENV["BUILDUPDATE_USER"] || ask("Enter #{server} username: ") { |q| q.echo = true }
$password = ENV["BUILDUPDATE_PASSWORD"] || ask("Enter #{server} password: ") { |q| q.echo = "*" }
rest_url = "https://#{server}/httpAuth/app/rest/10.0"
rest_api = RestClient::Resource.new(rest_url, :user=>$username, :password => $password) #, :headers => { :accept => "application/json"})
repo_url = "https://#{server}/guestAuth/repository"
repo_api = RestClient::Resource.new(repo_url)

if $options[:build_type].nil?
  projects_xml = rest_api['/projects'].get
  projects = TeamCityProjects.new(projects_xml)

  # Lookup build_type based on project name and build name
  project_name = os_specific?(:project, $options)
  abort("You need to specify project!\nPossible Names:\n  #{projects.names.values.join("\n  ")}") if project_name.nil?

  project_id = projects.ids[project_name]
  abort("Project '#{project_name}' not Found!\nPossible Names:\n  #{projects.names.values.join("\n  ")}") if project_id.nil?

  build_types_xml = rest_api["/projects/id:#{project_id}/buildTypes"].get
  build_types = TeamCityBuilds.new(build_types_xml)

  build_name = os_specific?(:build, $options)
  build_type = build_types.ids[build_name] unless build_name.nil?

  if build_type.nil?
    possible_names = Array.new
    build_types.names.each do |build_type, name|
      possible_names.push("#{build_type} : #{name}")
    end
    abort("Missing Build!\nPossible 'Build Type : Build Name' pairs:\n  #{possible_names.join("\n  ")}")
  end
  verbose("Selected: project=#{project_name}, build_name=#{build_name} => build_type=#{build_type}")
else
  build_type = $options[:build_type]
  verbose("Config: build_type=#{build_type}")
end
abort("You need to specify project/build or build_type in #{$script.path}!") if build_type.nil?


tagged_build_dependencies = {}
tagged_build_id = nil
unless $options[:build_tag].nil?
  builds_xml = rest_api["/buildTypes/id:#{build_type}/builds?tag=#{$options[:build_tag]}"].get
  tagged_build_id = Builds.new(builds_xml).build_ids.first
  build_xml = rest_api["/builds/id:#{tagged_build_id}"].get
  build = Build.new(build_xml)
  build.dependencies.each do |dep|
    tagged_build_dependencies[dep.build_type] = dep.build_id
  end
end

deps_req = "/buildTypes/id:#{build_type}/artifact-dependencies"
begin
  deps_xml = rest_api[deps_req].get
rescue
  abort("BuildType '#{build_type}' not Found!")
end
verbose("Artifact Dependencies: req:#{deps_req}\nxml: #{pretty_xml(deps_xml)}")

deps = ArtifactDependencies.new(deps_xml)
abort('Dependencies not found!') if deps.nil?

deps.dependencies.select { |dep| dep.clean_destination_directory }.each do |d|
  $script.lines.push(comment('clean destination directories'))
  d.path_rules.each do |src,dst|
    $script.lines.push($script.actions.rmdir("#{File.join(root_dir,dst)}"))
  end
end

req = "/buildTypes/id:#{build_type}"
build_type_xml = rest_api[req].get
verbose("BuildType: req:#{req}\nxml: #{pretty_xml(build_type_xml)}")
build = BuildType.new(build_type_xml)


vcs = nil
#Bug: vcs-roots not accessible via guestAuth
# https://youtrack.jetbrains.com/issue/TW-40586
unless build.vcs_root_id.nil?
  req = "/vcs-roots/id:#{build.vcs_root_id}"
  verbose("VCS req:#{req}")
  begin
    vcs_xml = rest_api[req].get
    verbose("xml:#{pretty_xml(vcs_xml)}")
    vcs = VCSRoot.new(vcs_xml)
  rescue
    warn_missing_view_build_configuration
  end
end

$script.lines.push('')
[
    '*** Results ***',
    "build: #{build.build_name} (#{build_type})",
    "project: #{build.project_name}",
    "URL: #{build.url}"
].each { |line| $script.lines.push(comment(line)) }

unless tagged_build_id.nil?
  $script.lines.push(comment("TAG: #{$options[:build_tag]} [build_id=#{tagged_build_id}]"))
end

unless vcs.nil?
  $script.lines.push(comment("VCS: #{vcs.repository_path} [#{build.resolve(vcs.branch_name)}]"))
end

$script.lines.push(comment('dependencies:'))
deps.dependencies.each_with_index do |d, i|
  req = "/buildTypes/id:#{d.build_type}"
  build_type_xml = rest_api[req].get
  verbose("BuildType[#{i}] req:#{req}\nxml:#{pretty_xml(build_type_xml)}")
  build_type = BuildType.new(build_type_xml)

  #work around bug in TC 9.0 implementation of 7.0 API
  verbose("build_type.url: #{build_type.url}")
  url_build_type = URI.parse(build_type.url).query.split(/=/)[1]
  if d.build_type != url_build_type
    d.build_type = url_build_type
  end

  if tagged_build_dependencies.has_key?(d.build_type)
    d.use_tagged_build(tagged_build_dependencies[d.build_type])
  end

  [
    "[#{i}] build: #{build_type.build_name} (#{d.build_type})",
    "    project: #{build_type.project_name}",
    "    URL: #{build_type.url}",
    "    clean: #{d.clean_destination_directory}",
    "    revision: #{d.revision_value}",
    "    paths: #{d.path_rules}"
  ].each { |line| $script.lines.push(comment(line)) }

  #Bug: vcs-roots not accessible via guestAuth
  # https://youtrack.jetbrains.com/issue/TW-40586
  unless build_type.vcs_root_id.nil?
    req = "/vcs-roots/id:#{build_type.vcs_root_id}"
    begin
      vcs_xml = rest_api[req].get
      verbose("VCS req:#{req}\nxml:#{pretty_xml(vcs_xml)}")
      vcs = VCSRoot.new(vcs_xml)
      $script.lines.push(comment("    VCS: #{vcs.repository_path} [#{build_type.resolve(vcs.branch_name)}]"))
    rescue
      warn_missing_view_build_configuration
    end
  end
end


dst_dirs = Set.new
dst_files = []
unzip_files = []
deps.dependencies.each do |d|
  d.path_rules.each do |path_rules_key,path_rules_dst|
    next if path_rules_key.to_s.empty? && path_rules_dst.to_s.empty?  # Ignore blank lines in path rules
    src = path_rules_key.gsub("\\", '/')
    path_rules_dst.gsub!("\\", '/')
    files = []
    if src.include?('zip!')
      abort("Only supporting zip!** pattern for now!: src=#{src}") unless src.end_with?('zip!**')
      files.push(src)
    elsif src.glob?
      ivy_api_call = "/download/#{d.build_type}/#{d.revision_value}/teamcity-ivy.xml"
      ivy_xml = repo_api[ivy_api_call].get
      verbose("glob: src=#{src}, dst=#{path_rules_dst}, api=#{ivy_api_call}\n\n#{pretty_xml(ivy_xml)}")
      ivy = IvyArtifacts.new(ivy_xml)
      matching_files = ivy.artifacts.select { |a| File.fnmatch(src, a, File::FNM_DOTMATCH)}
      files.concat(matching_files)
    else
      files.push(src)
    end

    filtered_files = []
    files.each do |file|
      matches = d.exclusion_rules.select { |pat,op| File.fnmatch(pat.sub(/=>.*/,''), file, File::FNM_DOTMATCH)}
      if matches.count > 0
        sorted_matches = matches.sort_by { |pat, op| pat.index(/[\?\*]/) || -1 }
        if sorted_matches[0][1] == '+'
          # This may include a different dst
          filtered_files.push(sorted_matches[0][0])
        end
      else
        filtered_files.push(file)
      end
    end

    filtered_files.each do |f|
      dst = path_rules_dst
      if f =~ /=>/
        # This was do to exclusion moving the file to another dst
        (f, dst) = f.split('=>')
      end
      verbose("Input: f=#{f}, dst=#{dst}")
      if src.end_with?('zip!**')
        f = f.split('!')[0]

        # Download to Downloads directory, but unzip to dst directory
        downloads_dir = "Downloads"
        dst_dirs << downloads_dir
        dst_file = File.join(downloads_dir, File.basename(f))
        dst_dir = dst
        verbose("zip_file: f=#{f} basename(f)=#{File.basename(f)} dst_file=#{dst_file} dst_dir=#{dst_dir}")
        unzip_files << %W(#{dst_file} #{dst_dir})
      elsif src.end_with?('/**')
              # e.g. f = foo/bar/baz.dll and src = foo/** => bar/baz.dll
        dst_file = File.join(dst,f.sub(src.sub('**', ''), ''))
        dst_dir = File.dirname(dst_file)
      elsif src.include?('**')
        abort("Can't handle recursive match that isn't at the end: #{src}")
      else
        dst_file = File.join(dst, File.basename(f))
        dst_dir = dst
      end
      dst_dirs << dst_dir
      dst_files << %W(#{repo_url}/download/#{d.build_type}/#{d.revision_value}/#{f}#{"?#{URI.encode_www_form(:branch => d.revision_branch)}" unless d.revision_branch.nil?} #{File.join(root_dir,dst_file)})
      verbose("Added: #{dst_files[-1]}")
    end
  end
end

$script.lines.push('')
$script.lines.push(comment('make sure output directories exist'))
dst_dirs.sort.each do |dir|
  $script.lines.push($script.actions.mkdir("#{File.join(root_dir,dir)}"))
end

$script.lines.push('')
$script.lines.push(comment('download artifact dependencies'))
dst_files.each do |pair|
  $script.lines.push($script.actions.download(pair[0], pair[1]))
end

if unzip_files.any?
  $script.lines.push(comment('extract downloaded zip files'))
  unzip_files.each do |zip_pair|
    $script.lines.push($script.actions.unzip("#{File.join(root_dir,zip_pair[0])}", "#{File.join(root_dir,zip_pair[1])}"))
  end
end
$script.set_header($options[:server], $options[:project], $options[:build], $options[:build_type], $options[:root_dir], $options[:build_tag])
$script.update
