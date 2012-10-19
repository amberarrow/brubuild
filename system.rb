#!/usr/bin/ruby -w

# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# Classes to extract platform, OS and hardware details
#

# keep requirements here to a minimum since Build.init_system is low-level code whose
# results are used in many other places
#
%w{ set singleton common.rb }.each{ |f| require f }

# code to extract system information such as OS, architecture, no. of cores, etc.

class Build
  def self.system
    raise "@@system not yet initialized" if !defined?( @@system )
    return @@system
  end  # system

  def self.init_system
    return if defined? @@system

    # create and store appropriate singleton object in class variable
    # use uname to get basic info about machine
    uname = Util.find_in_path 'uname'
    raise "Unable to find uname executable" if uname.nil?
    name = Util.run_cmd( "#{uname} -s" ).last
    case name
    when 'Linux' then @@system = Linux.instance
    when 'Darwin' then @@system = Darwin.instance
    else raise "Unknown sytem type: #{name}"
    end  # case
  end  # init_system

  class Nix    # generic Linux/Unix stuff
    # Some sample values:
    #
    #             Ubuntu 10.4        RedHat 5             OSX 10.6
    #             ===========        ========             ========
    # os_name     Linux              Linux                Darwin
    # os_release  2.6.32-41-generic  2.6.18-238.12.1.el5  10.8.0
    # os_version  (see below)        (see below)          (see below)
    # cpu_type    x86_64             x86_64               x86_64
    # cpu_width   64                 64                   64
    #
    # os_version:
    # Ubuntu 10.4 -- #88-Ubuntu SMP Thu Mar 29 13:10:32 UTC 2012
    # Redhat 5 -- #1 SMP Sat May 7 20:18:50 EDT 2011
    # OSX 10.6 -- Darwin Kernel Version 10.8.0: Tue Jun  7 16:32:41 PDT 2011; root:xnu-1504.15.3~1/RELEASE_X86_64
    #
    attr :hostname, :host, :os_name, :os_release, :os_verson, :cpu_type, :cpu_width

    def dump  # debugging
      printf( "host = %s\nos_name = %s\nos_release = %s\nos_version = %s\n" +
              "cpu_type = %s\ncpu_width = %d\nhostname = %s\n",
              @host, @os_name, @os_release, @os_version,
              @cpu_type, @cpu_width, @hostname )
    end  # dump

    def initialize
      # use uname to get basic info about machine
      uname = Util.find_in_path 'uname'
      hostname = Util.find_in_path 'hostname'
      raise "Unable to find hostname executable" if hostname.nil?
      @hostname   = Util.run_cmd( "#{hostname} -s" ).last    # omit domain name
      @host       = Util.run_cmd( "#{uname} -n" ).last
      @os_name    = Util.run_cmd( "#{uname} -s" ).last
      @os_release = Util.run_cmd( "#{uname} -r" ).last
      @os_version = Util.run_cmd( "#{uname} -v" ).last
      @cpu_type   = Util.run_cmd( "#{uname} -m" ).last
      @cpu_width  = (/_64$/o =~ @cpu_type) ? 64 : 32
    end  # initialize

    def darwin?    # return true iff OS is Darwin
      'Darwin' == @os_name
    end  # darwin?

    def pre_lion?    # return true iff OS is pre-Lion Darwin (10.6 or earlier)
      darwin? && @prod_version_major <= 10 && @prod_version_minor <= 6
    end  # pre_lion?
  end  # Nix

  class Linux < Nix    # Linux specific stuff
    include Singleton

    # Some sample values:
    #
    #                   Ubuntu 10.4        RedHat 5
    #                   ===========        ========
    # dist_id           Ubuntu             RedHatEnterpriseClient
    # dist_release      10.04              5.6
    # dist_codename     lucid              Tikanga
    #
    # dist_description:
    # Ubuntu 10.04 -- Ubuntu 10.04.4 LTS
    # Redhat 5 -- Red Hat Enterprise Linux Client release 5.6 (Tikanga)
    #
    attr :dist_id, :dist_release, :dist_codename, :dist_description, :ncores, :mem

    def dump  # debugging
      super
      printf( "dist_id = %s\ndist_release = %s\ndist_codename = %s\n" +
              "dist_description = %s\nncores = %d\nmem = %d MB\n",
              @dist_id, @dist_release, @dist_codename, @dist_description, @ncores, @mem )
    end  # dump

    def initialize
      super
      # use lsb_release if installed
      lsb_rel = Util.find_in_path 'lsb_release'
      if lsb_rel
        @dist_id          = Util.run_cmd( "#{lsb_rel} -si" ).last
        @dist_release     = Util.run_cmd( "#{lsb_rel} -sr" ).last
        @dist_codename    = Util.run_cmd( "#{lsb_rel} -sc" ).last
        @dist_description = Util.run_cmd( "#{lsb_rel} -sd" ).last
      else    # check common files
        ['/etc/lsb_release', '/etc/centos_release', '/etc/redhat_release'].each { |f|
          next if !File.exist? f
          IO.foreach( f ) { |line|
            fields = line.split '='
            raise "Bad line: #{line}" if 2 != fields.size
            fields.map( &:strip! )
            raise "Empty key" if fields[ 0 ].empty?
            key, val = fields

            case key
            when 'DISTRIB_ID'          then @dist_id          = val
            when 'DISTRIB_RELEASE'     then @dist_release     = val
            when 'DISTRIB_CODENAME'    then @dist_codename    = val
            when 'DISTRIB_DESCRIPTION' then @dist_description = val
            else raise "Bad key: #{key}"
            end  # case
          }  # IO.foreach
        }    # files block
      end   # lsb_rel

      # no. of cores
      @ncores = Util.run_cmd( "grep -c processor /proc/cpuinfo" ).last.to_i

      # memory
      free = Util.find_in_path 'free'
      raise "Command 'free' not found" if !free
      # in MBs
      @mem = Util.run_cmd( "#{free} -m" ).last.split( $/ )[ 1 ].split[ 1 ].to_i

    end  # initialize

  end  # LinuxUbuntu

  class Darwin < Nix    # Darwin/OSX specific stuff
    include Singleton

    attr :ncores, :mem, :prod_name, :prod_version_major, :prod_version_minor,
         :prod_version_patch, :build_version

    def dump    # debugging
      super
      printf( "ncores = %d\nmem = %d MB\nProduct Name = %s\n" +
              "Product Version = %d.%d.%d\nBuild Version = %s\npre_lion? = %s\n",
              @ncores, @mem, @prod_name, @prod_version_major, @prod_version_minor,
              @prod_version_patch, @build_version, pre_lion? )
    end  # dump

    # regex to extract major, minor, patch components of product version
    R_PROD_VERSION = /^ProductVersion:\s+(\d+)\.(\d+)\.(\d+)/o

    def initialize
      super

      # Output of sw_vers looks something like this:
      # ProductName:	Mac OS X Server
      # ProductVersion:	10.6.8
      # BuildVersion:	10K540
      #
      sys = Util.run_cmd( 'sw_vers' ).last
      sys.each_line { |line|
        case line
        when /^ProductName:/ then
          @prod_name = line.split[ 1..-1 ].join ' '
        when R_PROD_VERSION then
          @prod_version_major = $1.to_i
          @prod_version_minor = $2.to_i
          @prod_version_patch = $3.to_i
        when /^BuildVersion:/ then
          @build_version = line.split[ 1 ]
        # ignore any other output
        end
      }

      # this shows different values
      # @ncores = Util.run_cmd( "sysctl hw.ncpu" ).last.split[ 1 ].to_i

      sys = Util.run_cmd( "/usr/sbin/system_profiler SPHardwareDataType" ).last
      sys.each_line { |line|
        line.strip!
        case line    # ignore case since we see 'Of' on 10.6, 'of' on 10.7
        when /Total Number Of Cores:/io then @ncores = line.split[ 4 ].to_i
        when /Memory:/io
          arr = line.split; unit = arr[ 2 ]
          @mem = case unit
                 when 'GB' then arr[ 1 ].to_i * 1024
                 when 'MB' then arr[ 1 ].to_i
                 else raise "Unknown units: #{unit}"
                 end
        end
      }  # line loop
      raise "Unable to determine number of cores" if !defined? @ncores
      raise "Unable to determine size of installed RAM" if !defined? @mem
    end  # initialize

  end  # OSX

  def self.dump_system  # debugging
    raise "System not yet initialized" if !defined? @@system
    @@system.dump
  end  # dump_system

  init_system    # do this right away so results are available elsewhere
end  # Build

if $0 == __FILE__
  Build.init_system
  Build.dump_system
end
