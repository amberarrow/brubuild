# Ruby-based build system.
# Author: ram

require './openssl_customize.rb' if File.exist? './openssl_customize.rb'

# Project configuration for openssl -- specifies global items like compilers, compiler
# options, etc. Individual bundles of libraries and executables are specified in
# openssl.rb
# Build#setup is the entry point
# Build#customize, if it exists, has experimental customization
#
class Build

  def init_cpp_options    # global preprocessor options
    opt = case @build_type    # variations based on build_type
          when :dbg, :opt then ['-UNDEBUG']
          when :rel       then ['-DNDEBUG']
          else raise "Bad build_type = #{@build_type}"
          end
    opt += ['-DPIC', '-DOPENSSL_PIC'] if :dynamic == @link_type

    opt << '-I' + File.join( @obj_root, 'include' )    # for buildinf.h
    opt << '-I' + File.join( @src_root, 'include' )    # for e_os.h and e_os2.h
    opt << '-I' + @src_root
    opt << '-I' + File.join( @src_root, 'crypto' )

    # The L_ENDIAN should be removed on big endian machines -- do later
    opt += %w{ -DOPENSSL_THREADS      -D_REENTRANT           -DDSO_DLFCN
               -DHAVE_DLFCN_H         -DL_ENDIAN
               -DOPENSSL_IA32_SSE2    -DOPENSSL_BN_ASM_MONT  -DOPENSSL_BN_ASM_MONT5
               -DOPENSSL_BN_ASM_GF2m  -DSHA1_ASM             -DSHA256_ASM
               -DSHA512_ASM           -DMD5_ASM              -DAES_ASM
               -DVPAES_ASM            -DBSAES_ASM            -DWHIRLPOOL_ASM
               -DGHASH_ASM }
    opt << '-DTERMIO' if ! @@system.darwin?

    @options.add opt, :cpp
  end  # init_cpp_options

  def init_cc_options    # global C compiler options
    opt = {    # variations based on build_type
      :dbg => ['-g'],
      :opt => ['-g', '-O3'],
      :rel => ['-s', '-O3']
    }
    list = opt[ @build_type ]
    list << '-Wall'
    if @@system.darwin?
      list << '-fno-common'
    else
      list << '-fPIC' if :dynamic == @link_type
      list << '-Wa,--noexecstack'
    end

    @options.add list, :cc
  end  # init_cc_options

  def init_cxx_options    # global C++ compiler options
    # no C++ files in openssl
  end  # init_cxx_options

  def init_ld_cc_lib_options    # global options for linking with gcc (C libraries)
    opt = {    # variations based on build_type
      :dbg => [],
      :opt => ['-O3'],  # linker optimization
      :rel => ['-O3'],  # linker optimization
    }
    list = opt[ @build_type ]
    if @@system.darwin?
      list << '-dynamiclib' if :dynamic == @link_type
    else
      # '-Wl,-no-undefined'
      list += ['-shared', '-fPIC', '-ldl'] if :dynamic == @link_type
    end

    # add any other library flags to this array, e.g.
    # '-lpthread', '-lssl', '-lcrypto', '-lz', '-lm'
    #
    list += ["-L#{@obj_root}/lib", '-Wl,-rpath',
            (@@system.darwin? ? '-Wl,@loader_path/../lib' : '-Wl,\$ORIGIN/../lib')]

    @options.add list, :ld_cc_lib if ! list.empty?
  end  # init_ld_cc_lib_options

  def init_ld_cc_exec_options    # global options for linking with gcc (C executables)
    opt = {    # variations based on build_type
      :dbg => [],
      :opt => ['-O3'],  # linker optimization
      :rel => ['-O3'],  # linker optimization
    }

    list = opt[ @build_type ]
    list += ["-L#{@obj_root}/lib", '-Wl,-rpath',
            (@@system.darwin? ? '-Wl,@loader_path/../lib' : '-Wl,\$ORIGIN/../lib')]
    #list += ['-lssl -lcrypto'] if :dynamic == @link_type
    list << '-ldl'

    @options.add list, :ld_cc_exec if !list.empty?
  end  # init_ld_cc_exec_options

  def init_ld_cxx_lib_options    # options for linking with g++ (C++ libs)
    # no C++ files in openssl
  end  # init_ld_cxx_lib_options

  def init_ld_cxx_exec_options    # options for linking with g++ (C++ executables)
    # no C++ files in openssl
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
    cmd = "mkdir -p %s %s %s" % %w{ lib bin include }.map!{ |f| File.join @obj_root, f }
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
    dest = File.join @obj_root, 'include', 'buildinf.h'
    if !File.exist? dest
      f = @@system.darwin? ? 'osx-buildinf.h' : 'linux-buildinf.h'
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
