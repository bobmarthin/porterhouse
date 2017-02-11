module StackDockers
    module Vagrant
        module Docker

            DOCKER_VM = "docker-vm"

            # Namespace - a string appended to any attribute requiring unique identifier (docker name, volume path, ...)
            #
            @namespace = ENV['VAGRANT_NAMESPACE'] ? "-#{ENV['VAGRANT_NAMESPACE']}" : ""

            # Hash of docker containers (with parameters) to run
            #
            @dockers = {}

            # Settings hash containing stack docker configs.
            # These settings are used to share values between the docker runtime and docker config time.
            #
            @settings = {}

            # Default settings, that every container merges
            #
            @defaults = {}

            # Snapshots hash used to store per container btrfs subvolume snapshot paths
            #
            @snapshots = {}

            # Provisioners hash used to store per container scipts to run within container
            #
            @provisioners = {}

            # vm_mounts set used to store volumes and provisioner scripts mount points between the host and the virtual machine.
            # Enables supporting windows and mac, transparently provisioning the required files
            #
            @vm_mounts = Set.new

            # If to use docker stack to map ports, volumes and other shared volumes
            # Default yes, can be disabled if VAGRANT_DOCKER_STACK env set to 'false' and the a namespace is not specified
            #
            @network = (@namespace.empty? && ENV['VAGRANT_STACK_NETWORK'] === 'false') ? false : true

            # If to use force the docker run on VM
            #
            @force_vm = ENV['VAGRANT_FORCE_VM'] === 'true' ? true : false

            # List of docker configurations which are not mergable, and can be only overridden
            #
            @unmergable = ['cmd', 'ports', 'entrypoint']

            # The stack name
            #
            @stack = File.basename(Dir.pwd)

            # Default registry to use for images
            @registry = nil

            # Default organization to use for images
            @org = nil

            class << self
                attr_reader :namespace, :network, :force_vm, :stack, :snapshots, :provisioners, :dockers, :vm_mounts, :registry, :org

                # Adds array of stack settings by name and type (e.g. "my-docker" and "ports")
                #
                def configure(name: nil, ports: [], volumes: [], env: {}, create_args: [])
                    @settings[name] ||= { :ports => [], :volumes => [], :env => {}, :create_args => []}
                    @settings[name][:ports].concat(ports)
                    @settings[name][:volumes].concat(volumes)
                    @settings[name][:env].merge!(env)
                    @settings[name][:create_args].concat(create_args)
                end

                def ports
                    get_settings_all(:ports)
                end

                 def volumes
                    get_settings_all(:volumes)
                end

                def host_ports
                    get_settings_all(:ports).inject(Set.new) {|aggr, pair| aggr << pair.split(":").first}
                end

                # Runtime preparations
                #
                def runtime(docker)
                    # Map docker arguments for easier access
                    docker_args = {}
                    docker.create_args.each_with_index {|v, i| docker_args[v] = i}

                    if @network
                        # Set network stack unless overriden directly
                        unless docker_args["--net"]
                            @settings[docker.name][:create_args].concat(["--net", "container:#{@stack}#{@namespace}"])
                        end
                    end

                    if @settings.has_key?(docker.name)
                        @settings[docker.name].each do |key, value|
                            # configure docker container according to settings
                            docker.send("#{key}=",value) unless key == :ports
                        end
                    end
                end

                def interpolate_docker_config(docker)
                    docker.each do |key, value|
                        if value.kind_of?(Array)
                            docker[key] = []
                            value.each do |item|
                                docker[key] << item.gsub(/\${([^:]*)}/) do
                                    match = $1
                                    unless ENV[match]
                                        raise Exception.new("Env variable #{match} is not set")
                                    end
                                    ENV[match]
                                end
                            end
                        end
                    end
                end

                # Run all dockers
                #
                def run
                    stack = YAML.load_file(Dir.pwd + '/stack.yaml')

                    raise "No dockers defined in stack.yaml" unless stack.has_key?('dockers')
                    raise "No registry defined in stack.yaml" unless stack.has_key?('registry')
                    raise "No organization defined in stack.yaml" unless stack.has_key?('organization')
                    @registry = stack['registry']
                    @org = stack['organization']

                    # Load and merge global and stack defaults if exist
                    @defaults = stack['dockers'].delete('defaults') if stack['dockers'].has_key?('defaults')
                    if File.exists?("#{ENV['DOCKERS_WORKSPACE']}/dockers/defaults/docker.yaml")
                        @defaults = YAML.load_file("#{ENV['DOCKERS_WORKSPACE']}/dockers/defaults/docker.yaml").deep_merge(@defaults, @unmergable)
                    end
                    if File.exists?("#{ENV['DOCKERS_PATH']}/dockers/defaults/docker.yaml")
                        @defaults = YAML.load_file("#{ENV['DOCKERS_PATH']}/dockers/defaults/docker.yaml").deep_merge(@defaults, @unmergable)
                    end

                    stack['dockers'].each do |name, params|
                        params ||= {}

                        # Load and merge specific docker defaults config
                        if File.exists?("#{ENV['DOCKERS_WORKSPACE']}/dockers/#{name}/docker.yaml")
                            params = YAML.load_file("#{ENV['DOCKERS_WORKSPACE']}/dockers/#{name}/docker.yaml").deep_merge(params, @unmergable)
                        end
                        if File.exists?("#{ENV['DOCKERS_PATH']}/dockers/#{name}/docker.yaml")
                            params = YAML.load_file("#{ENV['DOCKERS_PATH']}/dockers/#{name}/docker.yaml").deep_merge(params, @unmergable)
                        end

                        # Merge defaults
                        docker = @defaults.deep_merge(params, @unmergable)

                        # If docker config includes/inherits from other docker then merge with the other docker config
                        if docker.has_key?('include')
                            if File.exists?("#{ENV['DOCKERS_WORKSPACE']}/dockers/#{docker['include']}/docker.yaml")
                                docker = YAML.load_file("#{ENV['DOCKERS_WORKSPACE']}/dockers/dockers/#{docker['include']}/docker.yaml").deep_merge(docker, @unmergable)
                            end
                            if File.exists?("#{ENV['DOCKERS_PATH']}/dockers/#{docker['include']}/docker.yaml")
                                docker = YAML.load_file("#{ENV['DOCKERS_PATH']}/dockers/dockers/#{docker['include']}/docker.yaml").deep_merge(docker, @unmergable)
                            end
                            #If image is not defined explicitly in both docker and included docker , then use default image based on inherited docker name
                            docker['image'] = docker.has_key?('image') ? docker['image'] : "#{@org}/#{docker['include']}"
                        end

                        docker['image'] = docker.has_key?('image') ? docker['image'] : "#{@org}/#{name}"

                        docker = interpolate_docker_config(docker)

                        #Load stack defined provision scripts
                        if docker.has_key?('provisioners')
                            docker['provisioners'].each do |script|
                                @provisioners["#{@stack}-#{name}#{@namespace}"] ||= []
                                script_path, *script_args = script.split(/\s/)
                                @provisioners["#{@stack}-#{name}#{@namespace}"] << script_args.inject(Pathname.new(script_path).basename.to_s){|args, param| args << " #{param}"}
                                configure name: :"#{@stack}-#{name}#{@namespace}", volumes: ["#{Pathname.linux_full_path(script_path)}:/provisioners/#{Pathname.new(script_path).basename}"]

                                # VM Support
                                script = File.expand_path(script, Dir.pwd)
                                @vm_mounts << "#{script}"

                            end
                        end

                        # Load stack defined ports
                        if docker.has_key?('ports')
                            configure name: :"#{@stack}-#{name}#{@namespace}", ports: docker['ports']
                        end

                        # Load stack defined volumes
                        if docker.has_key?('volumes')
                            docker['volumes'].each do |pair|
                                host_mountpoint, _, container_mountpoint = pair.rpartition(':')
                                container_mountpoint, volume_owner, volume_group = container_mountpoint.split("|")
                                configure name: :"#{@stack}-#{name}#{@namespace}", volumes: ["#{Pathname.linux_full_path(host_mountpoint)}:#{container_mountpoint}"]

                                # VM Support
                                host_mountpoint = File.expand_path(host_mountpoint, Dir.pwd)
                                @vm_mounts << "#{host_mountpoint}|#{volume_owner}|#{volume_group}"
                            end
                        end

                        # Load stack defined btrfs snapshot based volumes
                        if docker.has_key?('snapshots')
                            @snapshots["#{@stack}-#{name}#{@namespace}"] = docker['snapshots']
                        end

                        # Load custom envs
                        if docker.has_key?('env')
                            configure name: :"#{@stack}-#{name}#{@namespace}", env: docker['env']
                        end

                        # Load custom docker create_args
                        if docker.has_key?('create_args')
                            configure name: :"#{@stack}-#{name}#{@namespace}", create_args: docker['create_args']
                        end

                        # See if docker is privileged
                        if docker.has_key?('privileged')
                            if docker['privileged']
                                configure name: :"#{@stack}-#{name}#{@namespace}", create_args: ["--privileged"]
                            end
                        end

                        @dockers[name] = docker
                    end

                    load "#{File.dirname(__FILE__)}/Vagrantfile"
                end

                # Gets docker stack settings by name and type
                #
                private
                def get_settings(name, type)
                    (@settings.has_key?(name) && @settings[name].has_key?(type)) ? @settings[name][type] : []
                end

                # Collect stack settings for type from all dockers
                #
                private
                def get_settings_all(type)
                    @settings.values.inject([]) { |result, name| result += name[type] }
                end
            end
        end
    end
end
