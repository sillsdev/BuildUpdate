#!/usr/bin/env ruby
# $Id$
require 'rubygems'
require 'rest_client'
require 'optparse'
require 'nori'
require 'set'

require 'awesome_print'

path = File.dirname(File.expand_path($0))
require "#{path}/core_ext.rb"
require "#{path}/team_city.rb"
require "#{path}/script_actions.rb"
require "#{path}/build_update_script.rb"

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

  # Really need to look up the build type based on environment
  opts.on('-t', '--build_type BUILD_TYPE', 'Specify the BuildType in TeamCity') do |t|
    abort("Invalid build_type: #{t}.  Should be bt[0-9]+") if t !~ /^bt[0-9]+/
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
rest_url = "http://#{server}/guestAuth/app/rest/7.0"
rest_api = RestClient::Resource.new(rest_url) #, :headers => { :accept => "application/json"})
repo_url = "http://#{server}/guestAuth/repository"
repo_api = RestClient::Resource.new(repo_url)

if $options[:build_type].nil?
  projects_xml = rest_api['/projects'].get
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
abort('Dependencies not found!') if deps.nil?

deps.dependencies.select { |dep| dep.clean_destination_directory }.each do |d|
  $script.lines.push(comment('clean destination directories'))
  d.path_rules.each do |src,dst|
    $script.lines.push($script.actions.rmdir("#{File.join(root_dir,dst)}"))
  end
end

build_xml = rest_api["/buildTypes/id:#{build_type}"].get
build = BuildType.new(build_xml)

vcs = nil
unless build.vcs_root_id.nil?
  req = "/vcs-roots/id:#{build.vcs_root_id}"
  vcs_xml = rest_api[req].get
  verbose("VCS req:#{req}\nxml:#{vcs_xml}")
  vcs = VCSRoot.new(vcs_xml)
end

$script.lines.push('')
[
    '*** Results ***',
    "build: #{build.build_name} (#{build_type})",
    "project: #{build.project_name}",
    "URL: #{build.url}"
].each { |line| $script.lines.push(comment(line)) }

unless vcs.nil?
  $script.lines.push(comment("VCS: #{vcs.repository_path} [#{build.resolve(vcs.branch_name)}]"))
end

$script.lines.push(comment('dependencies:'))
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
    req = "/vcs-roots/id:#{build.vcs_root_id}"
    vcs_xml = rest_api[req].get
    verbose("VCS req:#{req}\nxml:#{vcs_xml}")
    vcs = VCSRoot.new(vcs_xml)
    $script.lines.push(comment("    VCS: #{vcs.repository_path} [#{build.resolve(vcs.branch_name)}]"))
  end
end


dst_dirs = Set.new
dst_files = []
unzip_files = []
deps.dependencies.each do |d|
  d.path_rules.each do |path_rules_key,path_rules_dst|
    src = path_rules_key.gsub("\\", '/')
    path_rules_dst.gsub!("\\", '/')
    files = []
    if src.include?('zip!')
      abort("Only supporting zip!** pattern for now!: src=#{src}") unless src.end_with?('zip!**')
      files.push(src)
    elsif src.glob?
      ivy_api_call = "/download/#{d.build_type}/#{d.revision_value}/teamcity-ivy.xml"
      ivy_xml = repo_api[ivy_api_call].get
      verbose("glob: src=#{src}, dst=#{path_rules_dst}, api=#{ivy_api_call}\n\n#{ivy_xml}")
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
      dst_files << %W(#{repo_url}/download/#{d.build_type}/#{d.revision_value}/#{f} #{File.join(root_dir,dst_file)})
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
$script.set_header($options[:server], $options[:project], $options[:build], $options[:build_type], $options[:root_dir])
$script.update
