#!/usr/local/bin/ruby -w
#
# persistence via TokyoCabinet key-value DB
#

require 'tokyocabinet'
include TokyoCabinet

class Build
  class Db
    # db -- the DB object; we want to gateway all access to the DB so we don't provide
    #       accessor
    # old -- true iff the DB already exists
    #
    attr :build

    # open hash DB
    # path = path to DB file
    # read = true/false; file opened read-only if true, read-write otherwise
    #
    # returns db object
    #
    def self.open_hdb( path, read = false )
      raise "path is nil" if path.nil?
      fpath = path.strip
      raise "path is blank" if fpath.empty?
      log = Build.logger

      db = HDB.new
      raise "tune error: #{db.errmsg( db.ecode )}\n" if
        !db.tune( 2048,      # bucket size (0.5 to 4 times no. of records to be stored)
                  nil,       # record alignment
                  8,         # free block pool (2**7 = 128)
                  nil )      # options; add TokyoCabinet::HDB::TLARGE when needed

      # if read is true, file must already exist
      #
      if read    # open in read mode
        raise "File #{fpath} not found" if !File.exist? fpath
        raise "open error[#{fpath}]: #{db.errmsg( db.ecode )}\n" if
          !db.open( path, HDB::OREADER | HDB::ONOLCK )
        log.info "HDB file %s exists, opened for reading" % fpath
      else       # open for writing, create if necessary
        raise "open error[#{path}]: #{db.errmsg( db.ecode )}\n" if
          !db.open( path, HDB::OWRITER | HDB::OCREAT )
        log.info "HDB file %s opened reading and writing" % fpath
      end

      return db
    end  # open_hdb

    def initialize b    # b is the build object
      raise "Expected Build, got #{b.class.name}" if !b.is_a? Build
      raise "b.build_type not set" if !b.build_type
      raise "b.link_type not set"  if !b.link_type
      raise "b.obj_root not set"   if !b.obj_root
      file = b.link_type.to_s + '_' + b.build_type.to_s + '.tch'
      path = File.join( b.obj_root, file )
      @old = File.exist? path
      @build, @db = b, Db.open_hdb( path )
    end  # initialize

    # check critical global variables and invalidate old data if necessary
    # NOTE: Currently, we invalidate the DB if _any_ of the global values change; this
    # is overly pessimistic. For example, if the global C compiler options change, only
    # the C objects that use the global options need to be invalidated. Doing this needs
    # care since there are subtle cases to consider -- fix later
    #
    def check_db    
      return if ! @old    # if newly created, nothing to check
      log = Build.logger
      if @db[ Build::KEY_SRC_ROOT ] != @build.src_root
        log.info "DB invalidated since src_roots differ: %s != %s" %
          [@db[ Build::KEY_SRC_ROOT ], @build.src_root]
        @db.clear
      elsif @db[ Build::KEY_OBJ_ROOT ] != @build.obj_root
        log.info "DB invalidated since obj_roots differ: %s != %s" %
          [@db[ Build::KEY_OBJ_ROOT ], @build.obj_root]
        @db.clear
      elsif @db[ Build::KEY_CC_PATH ] != @build.cc
        log.info "DB invalidated since C compilers differ: %s != %s" %
          [@db[ Build::KEY_CC_PATH ], @build.cc]
        @db.clear
      elsif @db[ Build::KEY_CXX_PATH ] != @build.cxx
        log.info "DB invalidated since C++ compilers differ: %s != %s" %
          [@db[ Build::KEY_CXX_PATH ], @build.cxx]
        @db.clear
      elsif diff( :cpp,         Build::KEY_OPT_CPP )          ||
            diff( :as,          Build::KEY_OPT_ASM )          ||
            diff( :cc,          Build::KEY_OPT_COMPILE_CC )   ||
            diff( :cxx,         Build::KEY_OPT_COMPILE_CXX )  ||
            diff( :ld_cc_lib,   Build::KEY_OPT_LINK_CC_LIB )  ||
            diff( :ld_cxx_lib,  Build::KEY_OPT_LINK_CXX_LIB ) ||
            diff( :ld_cc_exec,  Build::KEY_OPT_LINK_CC_EXE )  ||
            diff( :ld_cxx_exec, Build::KEY_OPT_LINK_CXX_EXE )
        log.info "DB invalidated since options differ"
        @db.clear
      else
        log.info "DB valid"
      end
    end  # check_db

    # debugging: compare @build.options.options[ sym ] with
    # @db[ key ] (unmarshalled) and return false if they are equal; otherwise,
    # dump their values and return true
    #
    def diff sym, key
      obj1 = @build.options.options[ sym ]
      obj2 = get_obj key

      # should not be nil
      raise "Got nil for build options for #{sym}" if !obj1
      raise "Got nil for DB value for #{key}" if !obj2

      return false if obj1 == obj2

      printf( "Objects differ: #{sym}, #{key}\nClasses: %s, %s\nhashes = %d, %d\n" +
              "No. of elements: %d, %d\n",
              obj1.class.name, obj2.class.name, obj1.hash, obj2.hash,
              obj1.options.size, obj2.options.size )
      obj1.dump
      obj2.dump
    end  # dump_bad

    def persist_globals    # save global values
      log = Build.logger
      log.info 'Persisting global values ...'

      @db[ Build::KEY_SRC_ROOT ] = build.src_root
      @db[ Build::KEY_OBJ_ROOT ] = build.obj_root
      @db[ Build::KEY_CC_PATH  ] = build.cc
      @db[ Build::KEY_CXX_PATH ] = build.cxx
      # default options
      opt = build.options.options
      @db[ Build::KEY_OPT_CPP ]          = Marshal.dump opt[ :cpp ]
      @db[ Build::KEY_OPT_ASM ]          = Marshal.dump opt[ :as ]
      @db[ Build::KEY_OPT_COMPILE_CC ]   = Marshal.dump opt[ :cc ]
      @db[ Build::KEY_OPT_COMPILE_CXX ]  = Marshal.dump opt[ :cxx ]
      @db[ Build::KEY_OPT_LINK_CC_LIB ]  = Marshal.dump opt[ :ld_cc_lib ]
      @db[ Build::KEY_OPT_LINK_CXX_LIB ] = Marshal.dump opt[ :ld_cxx_lib ]
      @db[ Build::KEY_OPT_LINK_CC_EXE ]  = Marshal.dump opt[ :ld_cc_exec ]
      @db[ Build::KEY_OPT_LINK_CXX_EXE ] = Marshal.dump opt[ :ld_cxx_exec ]
      log.info '... done persisting global values'
    end  # persist_globals

    def persist_target t    # save target data if necessary
      raise "Expected BaseTarget, got #{t.class.name}" if !t.is_a? BaseTarget
      log = Build.logger
      path = t.path
      if !t.rebuilt
        log.info "Not persisted since it was not built: %s" % path
        return
      end
      obj_old = get_obj path
      obj_new = BaseTargetDB.new t
      put( path, Marshal.dump( obj_new ) ) if obj_new != obj_old
      log.info "Persisted: %s" % path
    end  # persist_target

    def has_key? key
      @db.has_key? key
    end

    def get key    # use get_obj to retrieve target object
      @db.get key
    end

    def get_obj key    # use 'get' to retrieve plain strings
      s = @db.get key
      return nil if !s
      t = Marshal.load s
      return t
    end  # get_obj

    def put key, val
      raise "put error: #{@db.errmsg @db.ecode}\n" if !@db.put( key, val )
      return self    # so we can chain: x.put(a,b).put(c,d)
    end

    def empty?
      @db.rnum.zero?
    end

    def dump    # dump whole DB (debugging)
      log = Build.logger
      if empty?
        log.info "Database is empty"
        return
      end
      log.debug "Database dump (%d items):\n" % @db.rnum

      # keys whose values are plain strings and so do not need to be unmarshalled
      s_keys = Set[Build::KEY_SRC_ROOT,        Build::KEY_OBJ_ROOT,
                   Build::KEY_CC_PATH,         Build::KEY_CXX_PATH,
                   Build::KEY_OPT_CPP,         Build::KEY_OPT_ASM,
                   Build::KEY_OPT_COMPILE_CC,  Build::KEY_OPT_COMPILE_CXX,
                   Build::KEY_OPT_LINK_CC_LIB, Build::KEY_OPT_LINK_CXX_LIB,
                   Build::KEY_OPT_LINK_CC_EXE, Build::KEY_OPT_LINK_CXX_EXE]

      msg = sprintf( "src_root = %s\nobj_root = %s\nCC = %s\nCXX = %s\n",
                     @db[ Build::KEY_SRC_ROOT ], @db[ Build::KEY_OBJ_ROOT ],
                     @db[ Build::KEY_CC_PATH  ], @db[ Build::KEY_CXX_PATH ] )
      log.debug msg

      # dump global options
      [ Build::KEY_OPT_ASM,             Build::KEY_OPT_CPP,
        Build::KEY_OPT_COMPILE_CC,      Build::KEY_OPT_COMPILE_CXX,
        Build::KEY_OPT_LINK_CC_LIB,     Build::KEY_OPT_LINK_CXX_LIB,
        Build::KEY_OPT_LINK_CC_EXE,     Build::KEY_OPT_LINK_CXX_EXE
      ].each { |v| Marshal.load( @db[ v ] ).dump }

      @db.iterinit
      while (key = @db.iternext)
        val = @db[ key ]
        next if s_keys.include? key    # already dumped
        val = Marshal.load val
        log.debug '%s ==>' % key
        val.dump
      end
    end  # dump

    def close
      @db.close
    end  # close
  end  # Db

  # classes used for persistence; most mirror target classes
  class BaseTargetDB
    # (paths to compilers saved as global items)
    #
    # path:
    #     absolute path to object file
    # options_cpp:
    #     custom pre-processor options, if any, for this target; undefined if none
    # options:
    #     custom compiler/assembler/linker options, if any, for this target, undefined if
    #     none.
    # deps:
    #     list of dependency paths
    # no_hdr_deps:
    #     true if defined
    #
    attr :path, :options_cpp, :options, :deps, :no_hdr_deps

    def initialize tgt
      @path = tgt.path

      # convert from objects to paths
      @deps = tgt.deps.map( &:path )

      nhd = tgt.no_hdr_deps        # persist only if defined
      @no_hdr_deps = nhd if nhd

      opt_cpp, opt = tgt.options_cpp, tgt.options        # persist only if defined
      @options_cpp = opt_cpp if opt_cpp
      @options     = opt if opt

      #Build.logger.debug "Initialized %s, deps.size = %d" % [p, d.size]
    end  # initialize

    # comparing targets -- used to determine if target data needs to be persisted
    def hash
      instance_variables.inject( 17 ) { |m, v| 37 * m + instance_variable_get( v ).hash }
    end  # hash

    def == other
      return false if self.class != other.class || self.hash != other.hash
      idx = instance_variables.index { |v|
        instance_variable_get( v ) != other.instance_variable_get( v )
      }
      return idx.nil?
    end  # ==

    def eql? other
      self == other
    end  # eql?

    def dump    # for debugging
      log = Build.logger

      log.debug( '  path = %s' % @path )
      # dump dependencies in sorted order (except the first which is the source file)
      msg = @deps.first + "\n" + @deps[1..-1].sort.join( "\n" )
      log.debug( '  deps = %s' % msg )
      log.debug( '  no_hdr_deps = %s' % @no_hdr_deps ) if defined? @no_hdr_deps
      @options_cpp.dump if defined? @options_cpp
      @options.dump if defined? @options
    end  # dump
  end  # BaseTargetDB
end  # Build


