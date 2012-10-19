#!/usr/bin/ruby -w

# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# Class to interrogate system for presence or absence of features (e.g. header files,
# packages, etc.). Very limited right now but more extensive facilities will be added
# soon.
#
c = File.expand_path( File.dirname __FILE__ )      # this dir
$LOAD_PATH.unshift c if ! $LOAD_PATH.include? c

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
      @pkg_config = pc if pc
    end  # initialize

    def exist?    # return true iff pkg-config was found
      defined? @pkg_config
    end  # exist?

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

  class Endian < Feature      # test processor endianness
    attr :big    # true iff big-endian

    def initialize
      a = [(65 << 8) | 66]
      @big = (a.pack('S') == a.pack('S>'))    # Ruby 1.9.3 or later
    end  # initialize
  end  # Endian

  class Headers < Feature      # presence of various system header files

    attr :dirs    # list of directories to search for headers

    def get_include_path    # get compiler include path for system files
      log = Build::LogMain.get
      cmd = 'cpp -xc++ -v'  # desired output goes to stderr
      status = Util.run_cmd cmd, log, false
      raise "Failed to get include path" if !status.first

      # parse output
      line1 = '#include <...> search starts here:'
      line2 = 'End of search list.'
      state, result = :init, []
      status.last.each_line{ |line|
        line.strip!
        case state
        when :init then
          next if line != line1
          state = :path
        when :path then
          raise "Unexpected: line is empty" if line.empty?
          if line2 == line
            state = :done
            break
          end
          result << line
        else raise "Bad state: #{state}"
        end  # state
      }  # each_line
      raise "Failed to find last line" if :done != state
      return result
    end  # get_include_path

    def initialize
      @dirs = get_include_path
      raise "Header path empty" if @dirs.empty?
    end  # initialize

    # returns directory containing system header file if found, nil otherwise; if 'quick'
    # is true, we just check for the presence of the file in @dirs otherwise, we actually
    # run the pre-processor to see if we get an error (latter not yet implemented)
    #
    def get( file, quick = true )
      return nil if !file || file.empty?
      raise "Slow checking not yet implemented" if ! quick
      @dirs.find{ |d| File.exist? File.join( d, file ) }
    end  # file
      
  end  # Headers

  class Executables < Feature      # presence of various executables

    def get file    # returns path to executable file if found, nil otherwise
      return nil if !file || file.empty?
      Util.find_in_path file
    end  # file
      
  end  # Headers

end  # Build

if $0 == __FILE__
  Build.init_system
  Build::LogMain.set_log_file_params( :name => 'features.log' )

  obj = Build::Feature.get :Endian
  puts "Endianness: %s" % (obj.big ? 'big' : 'little')

  obj = Build::Feature.get :PkgConfig
  puts "pkg-config is %s" % (obj.exist? ? 'present' : 'absent')

  obj = Build::Feature.get :Headers
  # foo.h is nonexistent
  %w{ byteswap.h dlfcn.h inttypes.h memory.h stddef.h stdint.h stdlib.h strings.h
      string.h sys/mman.h sys/resource.h sys/types.h unistd.h
      foo.h
    }.each{ |f|
    puts "%s: %s" % [f, obj.get( f )]
  }
  
end
