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
  attr_accessor :clean_destination_directory, :path_rules, :exclusion_rules, :revision_name, :revision_value, :build_type

  def initialize(props)
    @clean_destination_directory = false
    @path_rules = {}
    @exclusion_rules = {}
    props.each do |p|
      name = p[:@name]
      value = p[:@value]
      case name
        when 'cleanDestinationDirectory'
          @clean_destination_directory = value.to_bool
        when 'pathRules'
          value.split("\n").each do |line|
            if line =~ /^[+\-]:/
              (op,pattern) = line.split(':')
              @exclusion_rules[pattern] = op
            else
              (src,dst) = line.split('=>')
              if dst.nil?
                @path_rules[src.strip] = ''
              else
                @path_rules[src.strip] = dst.strip
              end
            end
          end
        when 'source_buildTypeId'
          @build_type = value
        else
          self.send("#{name.snakecase}=", value)
      end
    end
  end

  def use_tagged_build(build_id)
    @revision_name = "tcbuildid"
    @revision_value = "#{build_id}.tcbuildid"
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
      obj.build_type = d[:source_build_type][:@id]
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
  attr_reader :project_name, :build_name, :url, :vcs_root_id, :parameters, :settings
  def initialize(xml)
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
    build = parser.parse(xml)[:build_type]
    @build_name = build[:@name]
    @url = build[:@web_url]
    @project_name = build[:project][:@name]
    @parameters = get_properties(build[:parameters])
    @settings = get_properties(build[:settings])

    def artifacts
      result = []
      rules = @settings['artifactRules']
      unless rules.nil?
        results = rules.split("\n")
      end
    end
    begin
      @vcs_root_id = build[:vcs_root_entries][:vcs_root_entry][:@id]
    rescue
      verbose("Note: No VCS Root defined for project=#{@project_name}, build_name=#{@build_name}")
    end
  end
  def get_properties(container)
    properties = {}
    begin
      props = container[:property]
      props.each do |p|
        name = p[:@name]
        value = p[:@value]
        properties[name] = value
      end
    rescue
      # No properties
    end
    properties
  end
  def resolve(str)
    if str =~ /%[^%]+%/
      key = str.gsub(/%/,'')
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
        when 'url'
          @repository_path = value
        when 'branch'
          @branch_name = value
        when 'repositoryPath'
          @repository_path = value
        when 'branchName'
          @branch_name = value
        else
          # ignore these
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

class Builds
  attr_reader :build_ids
  def initialize(xml)
    @build_ids = []
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym})
    builds =  ensure_array_of_objects(parser.parse(xml)[:builds][:build])
    builds.each do |b|
      @build_ids.push(b[:@id])
    end
  end
end

class BuildDependency
  attr_reader :build_id, :build_type
  def initialize(build_id, build_type)
    @build_id = build_id
    @build_type = build_type
  end
end

class Build
  attr_reader :build_id, :dependencies
  def initialize(xml)
    @dependencies = []
    parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym})
    build = parser.parse(xml)[:build]
    @build_id = build[:@id]
    dependencies = build[:artifact_dependencies][:build]
    dependencies.each do |d|
      @dependencies.push(BuildDependency.new(d[:@id], d[:@build_type_id]))
    end
  end
end