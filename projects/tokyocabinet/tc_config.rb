# Rubuild build file for Tokyo Cabinet
# (http://fallabs.com/tokyocabinet/tokyocabinet-1.4.48.tar.gz)
#
# Author: ram

require './tc_customize.rb' if File.exist? './tc_customize.rb'

# Project configuration for tokyocabinet -- specifies global items like compilers,
# compiler options, etc. Individual bundles of libraries and executables are specified in
# tokyocabinet.rb
#
class Build

  def init_cpp_options    # global preprocessor options
    opt = case @build_type    # variations based on build_type
          when :dbg, :opt then ['-UNDEBUG']
          when :rel       then ['-DNDEBUG']
          else raise "Bad build_type = #{@build_type}"
          end
    opt << '-DPIC' if :dynamic == @link_type

    opt += ['-D_GNU_SOURCE=1',
            '-D_REENTRANT',
            '-D__EXTENSIONS__',
            # the double quotes need to be part of the macro definition so we need
            # extra quotes
            #
            '-D_TC_PREFIX=\'"/usr/local"\'',
            '-D_TC_INCLUDEDIR=\'"/usr/local/include"\'',
            '-D_TC_LIBDIR=\'"/usr/local/lib"\'',
            '-D_TC_BINDIR=\'"/usr/local/bin"\'',
            '-D_TC_LIBEXECDIR=\'"/usr/local/libexec"\'',
            '-D_TC_APPINC=\'"-I/usr/local/include"\'',
            '-D_TC_APPLIBS=\'"-L/usr/local/lib"\'']
    opt << '-I' + File.join( @obj_root, 'include' )

    @options.add opt, :cpp
  end  # init_cpp_options

  def init_cc_options    # global C compiler options
    opt = {    # variations based on build_type
      :dbg => ['-g'],
      :opt => ['-g', '-O2'],
      :rel => ['-s', '-O2']
    }
    list = opt[ @build_type ]

    # -fPIC is the default on OSX
    list << '-fPIC' if (:dynamic == @link_type) && ! @@system.darwin?
    list << '-fno-common' if @@system.darwin?
    list += ['-std=c99',  '-Wall', '-fsigned-char ']
    @options.add list, :cc
  end  # init_cc_options

  def init_cxx_options    # global C++ compiler options
    # no C++ files in tokyocabinet
  end  # init_cxx_options

  def init_ld_cc_lib_options    # global options for linking with gcc (C libraries)
    common = []
    if @@system.darwin?
      common << '-dynamiclib' if :dynamic == @link_type
    else
      common += ['-shared', '-fPIC'] if :dynamic == @link_type
    end
    opt = {    # variations based on build_type
      :dbg => [],
      :opt => ['-O2'],  # linker optimization
      :rel => ['-O2'],  # linker optimization
    }

    list = common + opt[ @build_type ] +
      ['-Wl,-rpath',
       (@@system.darwin? ? '-Wl,@loader_path/../lib' : '-Wl,\$ORIGIN/../lib'),
       '-lbz2', '-lz', '-lpthread', '-lm']

    if @@system.darwin?
      v1, v2 = if defined?( @v_major ) && defined?( @v_minor ) && defined?( @v_bugfix )
                  ["#{@v_major}", "#{@v_major}.#{@v_minor}.#{@v_bugfix}"]
               else
                  ['0','0']
               end
      list += ["-compatibility_version #{v1}", "-current_version #{v2}"]
    else
      list << '-lrt'    # not available on OSX
    end

    @options.add list, :ld_cc_lib
  end  # init_ld_cc_lib_options

  def init_ld_cc_exec_options    # global options for linking with gcc (C executables)
    if :static == @link_type
    else    # fully dynamic linking
      opt = {    # variations based on build_type
        :dbg => [],
        :opt => ['-O2'],  # linker optimization
        :rel => ['-O2'],  # linker optimization
      }

      list = opt[ @build_type ] +
        ['-Wl,-rpath',
         (@@system.darwin? ? '-Wl,@loader_path/../lib' : '-Wl,\$ORIGIN/../lib'),
         '-lbz2', '-lz', '-lpthread', '-lm']
      list << '-lrt' if ! @@system.darwin?    # not available on OSX
    end  # static check

    @options.add list, :ld_cc_exec
  end  # init_ld_cc_exec_options

  def init_ld_cxx_lib_options    # options for linking with g++ (C++ libs)
    # no C++ files in tokyocabinet
  end  # init_ld_cxx_lib_options

  def init_ld_cxx_exec_options    # options for linking with g++ (C++ executables)
    # no C++ files in tokyocabinet
  end  # init_ld_cxx_exec_options

  def init_options    # initialize global default options
    log = Build.logger
    log.info "Initializing global options ..."

    @options = OptionGroup.new @build_type
    init_cpp_options            # Pre-processor
    init_cc_options             # C compiler
    init_cxx_options            # C++ compiler
    init_ld_cc_lib_options      # Linker, library (C files)
    init_ld_cc_exec_options     # Linker, executable (C files)
    init_ld_cxx_lib_options     # Linker, library (C++ files)
    init_ld_cxx_exec_options    # Linker, executable (C++ files)

    log.info "... done initializing global options"
  end  # init_options

  # default targets to build; argument is a list of pairs [file, kind] where 'file'
  # is the file name without extension and 'kind' is a symbol identifying the kind of
  # target: :lib -> library, :exe -> executable, :obj -> object
  #
  # NOTE: This target list may be overridden by commandline options
  #
  def add_default_targets list
    raise "@targets not defined" if !defined? @targets    # should be defined

    list.each_slice( 2 ) { |nm, kind|
      name = add_ext nm, kind    # append appropriate extension to name

      # target must already exist
      t = find_target name
      raise "Target #{name} not found" if !t
      raise "Multiple targets for #{name}" if t.size > 1
      @targets << t.first
    }
  end  # add_default_targets

  def create_dirs    # create necessary directories under obj_root
    cmd = "mkdir -p %s %s %s" % ['lib', 'bin', 'include'].map!{ |f|
      File.join @obj_root, f }
    Util.run_cmd cmd, @@logger
  end  # create_dirs

  @@bundles = []

  # argument is a class with a class method 'setup' which will be invoked by Build#setup
  def self.add_bundle bundle
    raise "Argument is nil" if bundle.nil?
    raise "Argument not a Bundle" if ! (bundle <= Bundle)
    raise "Argument already added" if @@bundles.include? bundle

    # cannot log anything since the logger is not yet initialized; this code runs during
    # load of yovo.rb
    # @@logger.info "Adding bundle %s" % bundle.name
    #
    @@bundles << bundle
  end  # add_bundle

  def setup    # invoked while initializing a build
    create_dirs    # create needed directories under build.obj_root

    # default options for compilers, linkers, etc. Create these first since they may
    # have to be duplicated and customized by the targets
    #
    init_options

    @@logger.info "Setting up %d bundles" % @@bundles.size
    @@bundles.each { |m| b = m.new self; b.setup }

    customize if respond_to? :customize       # user customizations if any
  end # setup

end  # Build
