#!/usr/bin/ruby -w

# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# Top-level driver and command line parser
#

# we need 1.9.X
raise "RUBY_VERSION = #{RUBY_VERSION}; need 1.9.3 or later" if
  Gem::Version.new(RUBY_VERSION) < Gem::Version.new('1.9.1')

# Execution starts with Build.start defined here.

%w{ thread set optparse ostruct system.rb thread-pool.rb histogram.rb db.rb }.each{ |f|
    require f }


class Build    # main class and namespace
  class Stats    # various statistics about the build
    # Counts of various types of files that were built:
    # num_as_objs     -- number of assembler objects
    # num_cc_objs     -- number C objects
    # num_cxx_objs    -- number of C++ objects
    # num_cc_libs     -- libraries linked with gcc
    # num_cxx_libs    -- libraries linked with g++
    # num_cc_execs    -- executables linked with gcc
    # num_cxx_execs   -- executables linked with g++
    # histogram_time       -- histogram of target build times
    # histogram_deps       -- histogram of target dependency counts
    #
    # lock -- mutex to control access since multiple threads will update these counts
    #
    attr :num_as_objs, :num_cc_objs, :num_cxx_objs, :num_cc_libs, :num_cxx_libs,
         :num_cc_execs, :num_cxx_execs, :histogram_time, :histogram_deps, :lock

    def initialize
      @num_as_objs = @num_cc_objs = @num_cxx_objs = @num_cc_libs = @num_cxx_libs =
        @num_cc_execs = @num_cxx_execs = 0
      @lock = Mutex.new
      @histogram_time = Histogram.new 'target build times (seconds)', 0...10, 10
      @histogram_deps = Histogram.new 'target dependency counts', 0...500, 20
    end  # initialize

    def update name, time    # increment named field and add time to histogram
      @lock.synchronize {
        i = 1 + instance_variable_get( name )
        instance_variable_set name, i
        @histogram_time.add time.to_i
      }
    end  # update

    def update_deps count    # add count to dependency histogram
      @histogram_deps.add count
    end  # incr

    def dump    # dump all stats via logger
      log = Build.logger
      log.info "No. of assembler objects = %d" % @num_as_objs
      log.info "No. of C objects = %d"         % @num_cc_objs
      log.info "No. of C++ objects = %d"       % @num_cxx_objs
      log.info "No. of C libraries = %d"       % @num_cc_libs
      log.info "No. of C++ libraries = %d"     % @num_cxx_libs
      log.info "No. of C executables = %d"     % @num_cc_execs
      log.info "No. of C++ executables = %d"   % @num_cxx_execs
      @histogram_time.dump log
      @histogram_deps.dump log
    end  # dump
  end  # Stats

  # constants
  BUILD_TYPES = Set[ :dbg, :rel, :opt ]
  LINK_TYPES = Set[ :static, :dynamic ]

  # persistence database related
  KEY_SRC_ROOT = 'src_root'                      # path to src root
  KEY_OBJ_ROOT = 'obj_root'                      # path to object root
  KEY_CC_PATH  = 'cc_path'                       # path to C compiler driver
  KEY_CXX_PATH = 'cxx_path'                      # path to C++ compiler driver

  KEY_OPT_CPP  = 'opt_cpp'                       # default pre-processor options
  KEY_OPT_ASM  = 'opt_asm'                       # default assembler options
  KEY_OPT_COMPILE_CC   = 'opt_compile_cc'        # default C options
  KEY_OPT_COMPILE_CXX  = 'opt_compile_cxx'       # default C++ options
  KEY_OPT_LINK_CC_LIB   = 'opt_link_c_lib'       # default C library linker options
  KEY_OPT_LINK_CXX_LIB = 'opt_link_cxx_lib'      # default C++ library linker options
  KEY_OPT_LINK_CC_EXE   = 'opt_link_c_exe'       # default C executable linker options
  KEY_OPT_LINK_CXX_EXE = 'opt_link_cxx_exe'      # default C++ executable linker options

  # regex for version string
  R_VERSION = /\A(\d+)\.(\d+)\.(\d+)\Z/o

  # class variables:

  # dbg        -- toggles verbose debug output
  @@dbg = true

  # commandline options parsed and stored here.
  #
  # debug      : toggles debug output
  # targets    : targets to build
  # build_type : dbg, opt, rel (debug, optimized, or release build)
  # link_type  : dbg, opt, rel (debug, optimized, or release build)
  # cc         : name of C compiler
  # cxx        : name of C++ compiler
  # num_threads : number of threads in thread pool
  # src_root   : root of source directory
  # obj_root   : root of object directory
  # version    : version in the form X.Y.Z
  # no_db      : disable use of persistence database
  # dump_db    : dump contents of persistence database
  #
  @@cl_options = OpenStruct.new( :debug       => false,
                                 :targets     => nil,
                                 :build_type  => nil,
                                 :link_type   => nil,
                                 :cc          => nil,
                                 :cxx         => nil,
                                 :num_threads => nil,
                                 :src_root    => nil,
                                 :obj_root    => nil,
                                 :version     => nil,
                                 :dump_db     => nil,
                                 :no_db       => nil )

  # defaults
  DEF_BUILD_TYPE, DEF_LINK_TYPE = :dbg, :dynamic
  DEF_CC, DEF_CXX = 'gcc', 'g++'
  DEF_OBJ_ROOT = '/var/tmp/rubuild/tmp'

  # src_root    -- path to root of source files
  # obj_root    -- path to root of object files
  # build_type  -- :dbg, :opt, :rel
  # link_type   -- :dynamic, :static
  # cc          -- absolute path to C compiler driver
  # cxx         -- absolute path to C++ compiler driver
  # options     -- OptionGroup of CPP, CC, CXX, AS and LD options
  # targets     -- list of targets to build; order may be important, so use array
  # all_targets -- hash of all known targets
  # thr_pool    -- thread pool
  # lock        -- mutex
  # done        -- condition variable
  # needs       -- set of top-level out-of-date targets
  # stats       -- various statistics about build
  # v_major     -- major version
  # v_minor     -- minor version
  # v_bugfix    -- patch version
  # v_lib       -- major.minor (used for soname/install_name)
  # version     -- major.minor.patch (used for actual file name of library files)
  # deps_enq_cnt -- count of dependency discovery tasks enqueued
  # deps_done_cnt -- count of dependency discovery tasks completed
  # db          -- persistence database (undefined if disabled)
  #
  attr_accessor :src_root, :obj_root, :cc, :cxx, :options, :targets, :all_targets,
                :build_type, :link_type, :thr_pool, :lock, :done, :needs, :stats,
                :v_major, :v_minor, :v_bugfix, :version, :v_lib,
                :deps_enq_cnt, :deps_done_cnt, :db

  def initialize
    @targets, @all_targets = Set[], {}
    @stats = Stats.new
    @deps_enq_cnt = @deps_done_cnt = 0
    @lock, @done = Mutex.new, ConditionVariable.new
  end  # initialize

  def dump    # debugging
    log = Build.logger
    msg = sprintf( "\nsrc_root = %s\nobj_root = %s\nbuild_type = %s\n",
                   @src_root, @obj_root, build_type )
    msg += "targets = "
    msg += targets.map( &:path ).join ', '
    log.debug msg
    @options.dump
  end  # dump

  # parse commandline args
  def self.parse_args
    opt = OptionParser.new
    opt.on( '-h', '--help', 'Show option summary' ) { puts opt; exit }

    # optional arg to enable debug (of this tool, not build type)
    opt.on( '-g', '--debug', "Enable debug" ) { |v| @@cl_options.debug = true }

    # optional arg to disable persistence database
    opt.on( '-p', '--no-db', "Disable database" ) { |v| @@cl_options.no_db = true }

    # optional arg to dump persistence database
    opt.on( '-q', '--dump-db', "Dump database" ) { |v| @@cl_options.dump_db = true }

    # optional arg for path to C compiler
    opt.on( '-c', '--cc PATH', "Path to C compiler" ) { |v|
      p = Util.strip v
      raise "Path to C compiler is empty" if p.empty?
      @@cl_options.cc = p
    }

    # optional arg for path to C++ compiler
    opt.on( '-x', '--cxx PATH', "Path to C++ compiler" ) { |v|
      p = Util.strip v
      raise "Path to C++ compiler is empty" if p.empty?
      @@cl_options.cxx = p
    }

    # optional size of thread pool
    opt.on( '-d', '--threads N', Integer, "Number of threads" ) { |n|
      raise "No. of threads too small: #{n}" if n < 1
      raise "No. of threads too large: #{n}" if n > 256
      @@cl_options.num_threads = n
    }

    # optional arg for type of build (debug, optimized, release)
    opt.on( '-b', '--build-type TYPE',
            "dbg (debug)[default], opt (optimized) or rel (release)" ) { |v|
      t = Util.strip v
      raise "Build type is empty" if t.empty?
      t = t.to_sym
      raise "Bad build type: #{t}" if !BUILD_TYPES.include? t
      @@cl_options.build_type = t
    }

    # required arg for root directory of sources
    opt.on( '-s', '--src-root DIR', "root directory of sources" ) { |v|
      d = Util.strip v
      # remove trailing slash if any since it causes regex matching problems later in
      # discover_deps
      #
      d[ -1 ] = '' if '/' == d[ -1 ]
      raise "src root dir is empty" if d.empty?
      File.check_dir d
      @@cl_options.src_root = d
    }

    # optional arg for root directory of objects
    opt.on( '-o', '--obj-root DIR', "root directory of objects" ) { |v|
      d = Util.strip v
      raise "object root dir is empty" if d.empty?
      @@cl_options.obj_root = d
    }

    # optional arg for type of link (static, dynamic)
    opt.on( '-l', '--link-type TYPE', "dynamic [default], static" ) { |v|
      t = Util.strip v
      raise "Link type is empty" if t.empty?
      t = t.to_sym
      raise "Bad link type: #{t}" if !LINK_TYPES.include? t
      @@cl_options.link_type = t
    }

    # optional arg for targets
    opt.on( '-t', '--targets T1,T2', Array, "Targets to build" ) { |list|
      raise "Target list empty" if list.empty?
      @@cl_options.targets = list.map( &:strip )
    }

    # optional arg for version
    opt.on( '-v', '--version VERSION', "Version" ) { |v|
      v = Util.strip v
      raise "Version is empty" if v.empty?
      @@cl_options.version = v
    }

    opt.parse ARGV
    raise "Need root dir of sources" if !@@cl_options.src_root
    @@cl_options.freeze

  end  # parse_args

  # list of targets to build (usually executables, .so files etc.); argument is a list of:
  # + absolute paths; or
  # + paths relative to obj_root (e.g. strings of the form bin/foo,
  #   lib/libBaz.so, etc.)
  #
  # must be invoked after Build.setup since it needs @build_type set correctly
  #
  def set_targets arg
    raise "Target list is nil" if arg.nil?
    raise "Target list is empty" if arg.empty?
    t_list = Set[]
    arg.each { |tgt|
      # Need to append suffix based on link_type -- do later
      # if it ends in .o or .so, add build_type suffix
      tgt += "_#{@build_type}" if tgt =~ /.(?:o|a|so)$/o
      list = find_target tgt
      raise "Target #{tgt} not found" if list.nil? || list.empty?
      raise "Target #{tgt} not unique: #{list}" if list.size > 1
      t_list << list.first
    }
    log = Build.logger
    if t_list == @targets
      log.warn "Target list unchanged"
    else
      @targets = t_list
      log.debug "Target list changed to:"
      @targets.each { |t| puts( "  %s" % t.path ) }
    end

  end  # set_targets

  def pre_build_check    # comprehensive pre-build check; call after discover_deps
    raise "Target list empty" if !@targets || @targets.empty?
    # add more later
  end  # pre_build_check

  def self.logger    # main logger
    raise "@@logger not defined (call Build.start first)" if !defined? @@logger
    @@logger
  end  # logger

  def self.start    # main entry point
    Thread.current[ :id ] = "Thr_main"    # name of thread

    # determine what kind of system we're running on
    #init_system

    # initialize logger
    LogMain.set_log_file_params( :name => 'build.log' )
    @@logger = log = Build::LogMain.get

    # parse commandline arguments
    parse_args
    log.info "Done parsing command line args."
    #p @@cl_options    # debug

    # initialize new build object
    build = Build.new

    # get version number from commandline
    v = @@cl_options.version
    if v
      raise "Bad version: #{v}" if v !~ R_VERSION
      build.v_major, build.v_minor, build.v_bugfix = $1, $2, $3
      build.version = [build.v_major, build.v_minor, build.v_bugfix].join '.'
      build.v_lib   = [build.v_major, build.v_minor].join '.'    # library version
    end

    # Build#setup needs src_root and obj_root
    build.src_root = @@cl_options.src_root
    build.obj_root = @@cl_options.obj_root || DEF_OBJ_ROOT

    # create thread pool
    n = @@cl_options.num_threads || @@system.ncores
    build.thr_pool = Pool.new n, log
    log.info "Done creating thread pool."

    # Build#setup needs to know the desired build type (because it determines what
    # compiler options to use)
    #
    build.build_type = @@cl_options.build_type || DEF_BUILD_TYPE
    build.link_type  = @@cl_options.link_type  || DEF_LINK_TYPE

    # override compilers with commandline parameters if necessary
    # Build#setup needs to know paths to compilers so it can determine the versions
    # On OSX, 10.6 and earlier need a different compiler name
    #
    c_path   = @@cl_options.cc  || (@@system.pre_lion? ? 'gcc-4.2' : DEF_CC)
    cxx_path = @@cl_options.cxx || (@@system.pre_lion? ? 'g++-4.2' : DEF_CXX)
    build.cc  = Util.find_in_path c_path
    build.cxx = Util.find_in_path cxx_path

    # get project specific info; Build#setup invokes Build#customize as the last step
    build.setup
    log.info "Done initializing project."

    # other modifications needed by commandline options

    # default targets are set earlier by Build#setup; override if needed
    t = @@cl_options.targets
    build.set_targets( t ) if t

    if @@cl_options.dump_db    # dump database and quit
      Db.new( build ).dump
      exit 0
    end

    # open persistence database
    # do this as late as possible but before we discover dependencies; in particular,
    # src_root and obj_root are used to validate the persisted DB
    #
    if ! @@cl_options.no_db             # persistence database enabled
      build.db = Db.new build
      build.db.check_db
    end

    # find dependencies: do this after default targets have been immutably set
    # since we only find dependencies of the desired targets
    #
    print "Discovering dependencies ..."
    build.discover_deps
    puts ' done'

    # dump some info (debugging)
    build.dump if @@dbg

    # comprehensive pre-build check
    build.pre_build_check

    # finally, build targets
    build.go

  end  # start
end  # Build
