module StackDockers
    module Vagrant
        require 'yaml'
        require 'pathname'
        require 'set'
        
    	API_VERSION = "2"
        require_relative 'vagrant/docker'

        DOCKER_VM = "docker-vm"

        class << self
            # Returns a command suitable for execution either locally or on a remote docker-vm
            def create_command(command, remote)
                return command unless remote

                vmdir = File.expand_path("#{ENV['DOCKERS_PATH']}/vm/#{DOCKER_VM}")
                ssh_config = "#{vmdir}/ssh.conf"

                unless File.exist?(ssh_config)
                    raise RuntimeError, "#{ssh_config} does not exists. Please go to the #{vmdir} direcotry and run '(sudo) vagrant ssh-config > ssh.conf'"
                end

                return "ssh -F #{ssh_config} #{DOCKER_VM} #{Pathname.is_windows_path(command) ? Pathname.linux_full_path(command) : command}"
            end
        end
    end
end
