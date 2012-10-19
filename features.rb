#!/usr/bin/ruby -w

# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# Class to interrogate system for presence or absence of features (e.g. header files,
# packages, etc.). Very limited right now but more extensive facilities will be added
# soon.
#
require 'system.rb'

# code to extract information about installed features of the system

class Build

  # a single feature of the environment which is typically the existence of a package such
  # as bonjour, fontconfig, or gtest
  #
  class Feature
    @@features = {}    # cache of features already checked

    # @@pkg_config -- path to binary
    # @@pkg_config_path -- search path for pkg_config

    # most features have corresponding CFLAGS (-I for include directories), -L (for
    # link-time location of libraries) and -l (for names of libraries) flags
    #
    attr :cflags, :ldflags_L, :ldflags_l

    # return feature object or nil if feature not present
    # argument is a symbol corresponding to the class name, e.g. 'PkgConfig'
    #
    def self.get name

      # we expect to find a class with this name
      raise "Expected Symbol, got #{name.class} (#{name})" if ! name.is_a? Symbol
      #raise "Expected String, got #{name.class} (#{name})" if ! name.is_a? String
      #full = ('Buld::' + name).to_sym

      c = Build.const_get name rescue nil
      raise "Unknown feature: #{name}" if !c
      raise "Expected Class but got #{c.class}" if !c.is_a? Class

      f = @@features[ name ]       # check cache
      return f if f                # feature present
      return nil if false == f     # feature absent

      # test for feature
      obj = c.new
      if obj.exist?                 # feature present
        @@features[ name ] = obj
        return obj
      end
      @@features[ name ] = false    # feature absent
      obj = nil
      return nil
    end  # get

    def exist?    # return true iff feature exists; override as needed
      true
    end  # exist?
  end  # Feature

  class PkgConfig < Feature      # pkg-config

    attr :pkg_config

    def initialize
      pc = Util.find_in_path 'pkg-config'
      raise "Unable to find pkg-config executable" if !pc
      @pkg_config = pc
    end  # initialize

    # runs pkg-config and returns flags; kind = :exist, :c, :l or :L
    def get_flags name, kind
      log = Build::LogMain.get
      case kind
      when :exist    # --exists
        cmd = "%s --exists %s" % [@pkg_config, name]
        status = Util.run_cmd cmd, log, false
        return status.first

      when :c        # --cflags
        cmd = "%s --cflags %s" % [@pkg_config, name]
        status = Util.run_cmd cmd, log, false
        raise "pkg-config failed to get cflags" if !status.first
        return status.last

      when :L        # --libs-only-L
        cmd = "%s --libs-only-L %s" % [@pkg_config, name]
        status = Util.run_cmd cmd, log, false
        raise "pkg-config failed to get libs-only-L flags" if !status.first
        return status.last

      when :l        # --libs-only-l
        cmd = "%s --libs-only-l %s" % [@pkg_config, name]
        status = Util.run_cmd cmd, log, false
        raise "pkg-config failed to get libs-only-l flags" if !status.first
        return status.last

      else raise "Unexpected: kind = #{kind}"
      end  # case
    end  # get_flags
  end  # PkgConfig

end  # Build

if $0 == __FILE__
  Build.init_system
  Build::LogMain.set_log_file_params( :name => 'features.log' )

  [ :PkgConfig ].each { |f|
    obj = Build::Feature.get f
    if !obj
      puts "Feature %s absent: #{obj.to_s}" % f
      next
    end
    puts "Feature %s present" % f
  }
end
