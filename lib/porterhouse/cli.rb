require 'optparse'
require 'ostruct'
require 'logger'

module Porterhouse

  class Cli

    def self.parse(args)
      params = OpenStruct.new(
        :loglevel => Logger::INFO,
        :dry_run => false,
        :workdir => nil,
        :init => false,
        :start => false,
        :stop => false,
        :test => false,
        :workspace => ENV['DOCKERS_WORKSPACE'],
        :stack_branch => 'master'
      )

      loglevels = {
        :debug => Logger::DEBUG,
        :info => Logger::INFO,
        :warn => Logger::WARN,
        :error => Logger::Error,
        :fatal => Logger::FATAL,
        :unknown => Logger::UNKNOWN
      }

      parser = OptionParser.new
      parser.banner = "Usage: #{$0} [options]"
      parser.on( '--log-level [LEVEL]', [:debug, :info, :warn, :error, :fatal, :unknown] ) { |l| params.loglevel = loglevels[l] }
      parser.on( '--workspace DOCKERS_WORKSPACE', String, 'Path to dockers stack workspace directory' ) { |p| params.workspace = p }
      parser.on( '--init', 'Initialize DOCKERS_WORKSPACE as dockers stack directory' ) { params.init = true }
      parser.on( '--start', 'Start dockers stack in DOCKERS_WORKSPACE' ) { params.start = true }
      parser.on( '--stop', 'Stop dockers stack in DOCKERS_WORKSPACE' ) { params.stop = true }
      parser.on( '--stack-clone REPO', String, 'Clone dockers stack from git repo into DOCKERS_WORKSPACE' ) { |r| params.stack_clone = true; params.stack_repo = r }
      parser.on( '--stack-subdir DIR', String, 'Subdir in git repo where dockers stack is located' ) { |s| params.stack_subdir = s }
      parser.on( '--stack-branch BRANCH', String, 'Dockers stack branch' ) { |r| params.stack_branch = r }
      parser.on( '--stack-commit COMMIT', String, 'Docker stack commit' ) { |c| params.stack_commit = c }
      parser.on( '--run-tests', 'Run tests defined in test section in stack.yaml' ) { params.tests = true }
      parser.on( '--run-tasks TASK1,TASK2,...', String, 'Run task defined tasks section in stack.yaml' ) { |t| params.run_tasks = t.split(',') }
      parser.on( '--show-tasks', 'Show tasks defined tasks section in stack.yaml' ) { params.show_tasks = true }
      parser.on( '--dry-run' ) { params.dry_run = true }
      parser.on( '-h', '--help', 'Display this screen' ) { puts parser; exit 0 }
      parser.parse!(args)

      unless params.workspace
        puts "Workspace path is not set"
        puts parser
        exit 1
      end

      params
    end
  end
end

