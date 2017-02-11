require 'fileutils'
require 'colorize'
require 'yaml'

module Porterhouse

  class Stack

    def initialize(params)
      @params = params

      @logger = Logger.new(STDOUT)
      @logger.level = @params.loglevel

      unless ENV['DOCKERS_PATH']
        @logger.fatal("DOCKERS_PATH is not set")
        exit 1
      end

      unless ENV['DOCKERS_PATH']
        @logger.fatal("DOCKERS_PATH is not set")
        exit 1
      end
    end

    def init_stack
      FileUtils.mkdir_p @params.workspace unless File.exists?(@params.workspace)
      unless File.directory?(@params.workspace)
        @logger.fatal("specified workspace dir already exists and not a directory")
        exit 1
      end

      unless File.exists?("#{@params.workspace}/stack.yaml")
        File.open("#{@params.workspace}/stack.yaml",'w') do |f|
          f.puts <<EOF
registry: local-registry.com
organization: myorganisation
dockers:
  consul:
setup:
  - "echo setup"
tests:
  before:
    - "echo before"
  run:
    - "echo run"
  after:
    - "echo after"
EOF
        end
      end

      unless File.exists?("#{@params.workspace}/Vagrantfile")
        File.open("#{@params.workspace}/Vagrantfile",'w') do |f|
          f.puts <<EOF
unless ENV['DOCKERS_PATH']
  raise "DOCKERS_PATH is not set"
end
unless File.directory?(ENV['DOCKERS_PATH'])
  raise "DOCKERS_PATH is not point to a directory"
end

ENV.store('DOCKERS_WORKSPACE', File.dirname(__FILE__))

require_relative "\#{ENV['DOCKERS_PATH']}/lib/stack-dockers"

StackDockers::Vagrant::Docker.run
EOF
        end
      end

      FileUtils.mkdir_p("#{@params.workspace}/workdir") unless File.exists?("#{@params.workspace}/workdir")
    end

    def fail(msg, exit_code=1)
      puts msg.colorize(:red)
      exit exit_code
    end

    def interpolate_command(command)
      command.gsub(/\${([^:]*)}/) do
        match = $1
        unless ENV[match]
          puts "Error: Env variable #{match} is not set".colorize(:red)
          exit 1
        end
        ENV[match]
      end
    end

    def exec_command(command, die=true)
      puts "Running: #{command}".colorize(:green)
      begin
        IO.popen(command) do |io|
          while (line = io.gets) do
            puts line
          end
        end
      rescue => e
        puts e.message
        puts "Failed: #{command}".colorize(:red)
        if die
          exit(1)
        else
          return 1
        end
      end
      unless $?.exitstatus == 0
        puts "Failed: #{command}".colorize(:red)
        if die
          exit($?.exitstatus)
        else
          return $?.exitstatus
        end
      end
      puts "OK: #{command}".colorize(:green)
      return $?.exitstatus
    end

    def run_hooks(phase)
      stack = YAML.load_file(Dir.pwd + '/stack.yaml')
      if stack['hooks'] and stack['hooks'][phase]
        puts "----------------------------- Running: #{phase} Hooks -----------------------------".colorize(:green)
        stack['hooks'][phase].each do |hook|
          exec_command(interpolate_command(hook))
        end
        puts "----------------------------- OK: #{phase} Hooks -----------------------------".colorize(:green)
      end
    end

    def start_stack
      fail "Fatal: DOCKERS_WORKSPACE #{@params.workspace} directory does not exists" unless File.directory?(@params.workspace)
      FileUtils.chdir(@params.workspace)
      run_hooks('pre-start')
      exec_command("env VAGRANT_DEFAULT_PROVIDER=docker vagrant up --provider=docker --no-parallel")
      run_hooks('post-start')
    end

    def stop_stack
      fail "Fatal: DOCKERS_WORKSPACE #{@params.workspace} directory does not exists" unless File.directory?(@params.workspace)
      at_exit do
        FileUtils.chdir(@params.workspace)
        run_hooks('pre-stop')
        exec_command("env VAGRANT_DEFAULT_PROVIDER=docker vagrant destroy -f")
        run_hooks('post-stop')
      end
    end


    def git_clone_stack
      unless File.exists?(@params.workspace)
        exec_command("git clone #{@params.stack_repo} -b #{@params.stack_branch} #{@params.workspace}")
      else
        FileUtils.chdir(@params.workspace)
        exec_command("git branch -u origin/#{@params.stack_branch} #{@params.stack_branch}")
        exec_command("git pull")
      end
      if @params.stack_commit
        exec_command("git checkout #{@params.stack_commit}")
      end
      if @params.stack_subdir
        FileUtils.chdir(@params.workspace)
        fail "Fatal: repo #{@params.stack_branch} does not have #{@params.stack_subdir} subdir" unless File.exists?(@params.stack_subdir)
        @params.workspace = @params.workspace + '/' + @params.stack_subdir
      end
    end

    def show_stack_tasks
      fail "Fatal: DOCKERS_WORKSPACE #{@params.workspace} directory does not exists" unless File.directory?(@params.workspace)
      FileUtils.chdir(@params.workspace)
      stack = YAML.load_file(Dir.pwd + '/stack.yaml')
      if stack.has_key?('tasks')
        stack['tasks'].keys.each do |task|
          puts task.colorize(:green)
        end
      end
    end

    def run_stack_tasks
      fail "Fatal: DOCKERS_WORKSPACE #{@params.workspace} directory does not exists" unless File.directory?(@params.workspace)
      FileUtils.chdir(@params.workspace)
      stack = YAML.load_file(Dir.pwd + '/stack.yaml')
      if stack.has_key?('tasks')
        @params.run_tasks.each do |task|
          fail "Fatal: task #{task} is not defined in stack.yaml" unless stack['tasks'].has_key?(task)
          puts "----------------------------- Running: Task #{task} -----------------------------".colorize(:green)
          stack['tasks'][task].each do |command|
            exec_command(interpolate_command(command))
          end
          puts "----------------------------- OK: Task #{task}  -----------------------------".colorize(:green)
        end
      end
    end

    def run_stack_tests
      fail "Fatal: DOCKERS_WORKSPACE #{@params.workspace} directory does not exists" unless File.directory?(@params.workspace)
      FileUtils.chdir(@params.workspace)
      stack = YAML.load_file(Dir.pwd + '/stack.yaml')
      if stack.has_key?('tests')
        ok = true
        if stack['tests'].has_key?('before') and stack['tests']['before']
          ok_before = true
          puts "----------------------------- Running: Before Tests -----------------------------".colorize(:green)
          stack['tests']['before'].each do |command|
            unless exec_command(interpolate_command(command),false) == 0
              ok_before = false
              break
            end
          end
          ok = false unless ok_before
          if ok_before
            puts "----------------------------- OK: Before Tests -----------------------------".colorize(:green)
          else
            puts "----------------------------- FAILED: Before Tests -----------------------------".colorize(:red)
          end
        end
        if ok and stack['tests'].has_key?('run') and stack['tests']['run']
          ok_run = true
          puts "----------------------------- Running: Run Tests -----------------------------".colorize(:green)
          stack['tests']['run'].each do |command|
            unless exec_command(interpolate_command(command),false) == 0
              ok_run = false
            end
          end
          ok = false unless ok_run
          if ok_run
            puts "----------------------------- OK: Run Tests -----------------------------".colorize(:green)
          else
            puts "----------------------------- FAILED: Run Tests -----------------------------".colorize(:red)
          end
        end
        if stack['tests'].has_key?('after') and stack['tests']['after']
          ok_after = true
          puts "----------------------------- Running: After Tests -----------------------------".colorize(:green)
          stack['tests']['after'].each do |command|
            unless exec_command(interpolate_command(command),false) == 0
              ok_after = false
            end
          end
          ok = false unless ok_after
          if ok_after
            puts "----------------------------- OK: After Tests -----------------------------".colorize(:green)
          else
            puts "----------------------------- FAILED: After Tests -----------------------------".colorize(:red)
          end
        end
        at_exit do
          ok ? exit(0) : exit(1)
        end
      end
    end

    def run
      init_stack if @params.init
      git_clone_stack if @params.stack_clone
      show_stack_tasks if @params.show_tasks
      run_stack_tasks if @params.run_tasks
      start_stack if @params.start
      run_stack_tests if @params.tests
      stop_stack if @params.stop
    end
  end
end
