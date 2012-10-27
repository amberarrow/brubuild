#!/usr/bin/ruby -w

# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# Class to interrogate system for presence or absence of features (e.g. header files,
# packages, etc.). Very limited right now but more extensive facilities will be added
# soon.

c = File.expand_path( File.dirname __FILE__ )      # this dir
$LOAD_PATH.unshift c if ! $LOAD_PATH.include? c

require 'system.rb'

# code to extract information about installed features of the system

class Build

  class Version    # version strings of the form X.Y.Z...
    attr :version

    def initialize vs    # v is a string of the form X.Y.Z...
      raise "Version string is nil" if !vs
      vss = vs.strip
      raise "Version string is blank" if vss.empty?
      @version = vss.split( '.' ).map!( &:to_i )
    end  # initialize

    def major    # major version must exist
      @version[ 0 ]
    end  # major

    def minor    # minor version may not exist
      @version.size > 1 ? @version[ 1 ] : nil
    end  # major

    def hash
      @version.hash
    end  # hash

    def == other
      return false if self.class != other.class || self.hash != other.hash
      @version == other.version
    end  # ==

    def eql? other
      self == other
    end  # eql?
  end  # Version

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
    # first argument is a symbol corresponding to the class name, e.g. 'PkgConfig'
    # second argument is a hash passed to the initialize method of each feature.
    #
    def self.get( name, h = nil )

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
      obj = c.new h
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

    def initialize args
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

    def initialize args
      a = [(65 << 8) | 66]
      @big = (a.pack('S') == a.pack('S>'))    # Ruby 1.9.3 or later
    end  # initialize
  end  # Endian

  class Compiler < Feature      # various features of the compiler
    R_GCC_VERSION   = /\Agcc version (\d+\.\d+\.\d+)/o
    R_CLANG_VERSION = /\AApple clang version (\d+\.\d+)/o

    # adjust as needed; might need version specific sets
    GCC_BUILTINS = Set[ :__builtin_expect,
                        :__builtin_ctz, :__builtin_ctzl, :__builtin_ctzll,
                        :__builtin_clz, :__builtin_clzl, :__builtin_clzll,
                        :__builtin_ffs, :__builtin_ffsl, :__builtin_ffsll ]

    CLANG_BUILTINS = Set[ :__builtin_expect,
                          :__builtin_ctz, :__builtin_ctzl, :__builtin_ctzll,
                          :__builtin_clz, :__builtin_clzl, :__builtin_clzll,
                          :__builtin_ffs, :__builtin_ffsl, :__builtin_ffsll ]


    # cc -- path to C compiler
    # cpp -- path to pre-processor
    # cxx -- path to C++ compiler
    # include_path_common -- list of directories common to both C and C++
    # include_path_cc -- extra list of directories to search for C headers
    # include_path_cxx -- extra list of directories to search for C++ headers
    # version -- Version object representing compiler version
    #
    attr :cc, :cpp, :cxx, :include_path_common, :include_path_cc, :include_path_cxx,
         :version

    # helper routine to set attribute based on args; the attribute name is formed by
    # prepending '@' to key
    # args  -- argument hash
    # key   -- key in args to retrieve value
    # msg   -- message string to print for diagnostics
    #
    def set_path key, args, msg
      p = args[ key ]
      return if !p
      p.strip!
      raise "Path to #{msg} is empty"  if p.empty?
      raise "#{msg} not found at #{p}" if ! File.exist? p
      field = ('@' + key.to_s).to_sym
      instance_variable_set field, p
    end  # set_path

    # return include path for system header files for C or C++
    def get_include_path lang    # argument should be either 'c' or 'c++'
      log = Build::LogMain.get
      prog = defined?( @cpp ) ? @cpp : 'cpp'
      
      cmd = "#{prog} -x#{lang} -v"  # desired output goes to stderr
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

    # internal helper routine
    def get_version    # get compiler version
      return if defined? @version    # already done
      log = Build::LogMain.get

      # versions of C and C++ compiler are usually the same, so just get one
      prog = defined?( @cc ) ? @cc : defined( @cxx ) ? @cxx : nil
      raise "Neither C not C++ compiler found" if !prog
      cmd = "#{prog} -v"  # desired output goes to stderr
      status = Util.run_cmd cmd, log, false
      raise "Failed to get compiler version" if !status.first
      if prog =~ /clang/o
        line = status.last.split( $/ ).first    # first line has version
        raise "Unable to find clang version in #{line}" if line !~ R_CLANG_VERSION
      else  # assume gcc
        line = status.last.split( $/ ).last    # last line has version
        raise "Unable to find gcc version in #{line}" if line !~ R_GCC_VERSION
      end
      @version = Version.new $1

      # parse output
    end  # get_version

    def initialize args
      raise "args is nil" if !args
      raise "args is empty" if args.empty?
      [ :cpp, "pre-processor", :cc, "C compiler",
        :cxx, "C++ compiler"].each_slice( 2 ) { |k, m| set_path k, args, m }

      @include_path_cc  = get_include_path 'c'
      @include_path_cxx = get_include_path 'c++'
      raise "C header path empty"   if @include_path_cc.empty?
      raise "C++ header path empty" if @include_path_cxx.empty?
      @include_path_common = @include_path_cc & @include_path_cxx
      @include_path_cc  -= @include_path_common
      @include_path_cxx -= @include_path_common

      get_version
    end  # initialize

    # returns directory containing system header file if found, nil otherwise; if 'quick'
    # is true, we just check for the presence of the file in C and C++ include paths;
    # otherwise, we actually run the pre-processor to see if we get an error (latter not
    # yet implemented)
    #
    def get_hdr_dir( file, quick = true )
      return nil if !file || file.empty?
      raise "Slow checking not yet implemented" if ! quick
      dir = @include_path_common.find{ |d| File.exist? File.join( d, file ) }
      return dir if dir
      dir = @include_path_cc.find{ |d| File.exist? File.join( d, file ) }
      return dir if dir
      @include_path_cxx.find{ |d| File.exist? File.join( d, file ) }
      # frame directories need special treatment on Mac -- do later
    end  # get_hdr_dir
      
    def has_builtin name
      prog = defined?( @cc ) ? @cc : defined( @cxx ) ? @cxx : nil
      raise "Neither C not C++ compiler found" if !prog
      case prog
      when /clang/ then
        return true if CLANG_BUILTINS.include? name
      when /gcc/ then
        return true if GCC_BUILTINS.include? name
      end  # case
      return false
    end  # has_builtin

  end  # Compiler

  class Executables < Feature      # presence of various executables

    def get file    # returns path to executable file if found, nil otherwise
      return nil if !file || file.empty?
      Util.find_in_path file
    end  # get
      
  end  # Executables

end  # Build

if $0 == __FILE__
  Build.init_system
  Build::LogMain.set_log_file_params( :name => 'features.log' )

  obj = Build::Feature.get :Endian
  puts "Endianness: %s" % (obj.big ? 'big' : 'little')

  obj = Build::Feature.get :PkgConfig
  puts "pkg-config is %s" % (obj.exist? ? 'present' : 'absent')

  obj = Build::Feature.get( :Compiler, { :cpp => '/usr/bin/cpp', :cc => '/usr/bin/gcc',
                                         :cxx => '/usr/bin/g++' } )
  # foo.h is nonexistent
  %w{ byteswap.h dlfcn.h inttypes.h memory.h stddef.h stdint.h stdlib.h strings.h
      string.h sys/mman.h sys/resource.h sys/types.h unistd.h
      foo.h
    }.each{ |f|
    puts "%s: %s" % [f, obj.get_hdr_dir( f )]
  }
  
  puts "Compiler version: major = %d, minor = %d" % obj.version.version[ 0..1 ]
  puts "Has __builtin_expect: %s" % obj.has_builtin( :__builtin_expect )
  puts "Has __builtin_foo: %s" % obj.has_builtin( :__builtin_foo )
end
