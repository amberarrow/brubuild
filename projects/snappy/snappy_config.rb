# Rubuild build file for snappy (http://code.google.com/p/snappy/)
# Author: ram

require './snappy_customize.rb' if File.exist? './snappy_customize.rb'

# Project configuration for snappy -- specifies global items like compilers, compiler
# options, etc. Individual bundles of libraries and executables are specified in
# snappy.rb
#
class Build

  def init_cpp_options    # global preprocessor options
    opt = case @build_type    # variations based on build_type
          when :dbg, :opt then ['-UNDEBUG']
          when :rel       then ['-DNDEBUG']
          else raise "Bad build_type = #{@build_type}"
          end
    opt << '-DPIC' if :dynamic == @link_type

    # We copy a suitable config.h file to @obj_root/include
    opt << '-DHAVE_CONFIG_H'
    opt << '-I' + File.join( @obj_root, 'include' )

    @options.add opt, :cpp
  end  # init_cpp_options

  def init_cc_options    # global C compiler options
    # no C files in snappy
  end  # init_cc_options

  def init_cxx_options    # global C++ compiler options
    opt = {    # variations based on build_type
      :dbg => ['-g'],
      :opt => ['-g', '-O2'],
      :rel => ['-s', '-O2']
    }
    list = opt[ @build_type ]

    # -fPIC is the default on OSX
    list << '-fPIC' if (:dynamic == @link_type) && ! @@system.darwin?
    list << '-fno-common' if @@system.darwin?

    @options.add list, :cxx
  end  # init_cxx_options

  def init_ld_cc_lib_options    # global options for linking with gcc (C libraries)
    # no C files in snappy
  end  # init_ld_cc_lib_options

  def init_ld_cc_exec_options    # global options for linking with gcc (C executables)
    # no C files in snappy
  end  # init_ld_cc_exec_options

  def init_ld_cxx_lib_options    # options for linking with g++ (C++ libs)
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
       '-lm']

    if @@system.darwin?
      v1, v2 = if defined?( @v_major ) && defined?( @v_minor )
                  ["#{@v_major}", "#{@v_major}.#{@v_minor}"]
               else
                  ['0','0']
               end
      list += ["-compatibility_version #{v1}", "-current_version #{v2}"]
    end

    @options.add list, :ld_cxx_lib
  end  # init_ld_cxx_lib_options

  def init_ld_cxx_exec_options    # options for linking with g++ (C++ executables)
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
         '-lz'
        ]
    end  # static check

    @options.add list, :ld_cxx_exec
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

    # copy appropriate header file if necessary
    dest = File.join @obj_root, 'include', 'config.h'
    if !File.exist? dest
      f = @@system.darwin? ? 'config_osx.h' : 'config_linux.h'
      cmd = "cp %s %s" % [f, dest]
      Util.run_cmd cmd, Build.logger
    end

    # default options for compilers, linkers, etc. Create these first since they may
    # have to be duplicated and customized by the targets
    #
    init_options

    @@logger.info "Setting up %d bundles" % @@bundles.size
    @@bundles.each { |m| b = m.new self; b.setup }

    customize if respond_to? :customize       # user customizations if any
  end # setup

end  # Build
