# Ruby-based build system.
# Author: ram

c = File.expand_path( File.dirname __FILE__ )      # this dir
m = File.expand_path( File.join c, '..', '..' )    # main dir
[ c, m ].each { |p| $LOAD_PATH.unshift p unless $LOAD_PATH.include? p }

%w{ build options targets hello_world_config.rb features }.each{ |f| require f }

# Individual bundles of libraries and/or executables specified -- one class per bundle
#
class Build

  # Base class for a new subproject -- MUST be extended by each bundle
  #
  # Each collection of closely related libraries and/or executables whose sources appear
  # under a single directory is called a bundle. Each bundle is configured via a single
  # derived class of Bundle.
  #
  # Each derived class of Bundle _must_ have:
  # (a) an initialize method that takes a single argument (current build object).
  # (b) a setup method that sets up everything needed by the bundle.
  # The base class has additional methods to simplify this work but derived classes may
  # ignore these methods if they so choose.
  #
  # These are singleton classes used for encapsulating all the information about a single
  # bundle, namely:
  # A. The root directory where sources for this bundle are located.
  # B. The set of libraries and executables that must be built for this bundle.
  # C. The set of object files that comprise each library or executable.
  # D. Any additions or deletions to the compiler and linker options for any object,
  #    library, or executable in this bundle.
  #
  # The setup method must do these things:
  # 1. Define @dir_root relative to src_root (e.g. 'libFoo')
  # 2. Create any needed directories under obj_root
  # 3. Invoke build.discover_targets with suitable include/exclude lists
  # 4. Invoke build.add_targets to add all the library and executable targets.
  # 5. Invoke build.add_default_targets to add all the library and executable targets that
  #    should be built by default
  # 6. Invoke build.delete_target_options and build.add_target_options to adjust the
  #    compiler and linker options for targets in this bundle, if necessary.
  #
  class Bundle
    attr :build, :dir_root, :include, :exclude

    # derived class overrides should call 'super', then initialize these instance
    # variables and any others they might need
    #
    # dir_root    -- [required] root directory relative to build.src_root (e.g 'libFoo')
    # include     -- [optional] subdirectories to include in search for source files
    # exclude     -- [optional] subdirectories to exclude in search for source files
    # libraries   -- [optional] list of libraries
    # executables -- [optional] list of executables
    # targets     -- [optional] list of default targets
    #
    def initialize b
      @build = b
    end  # initialize

    def discover_targets
      # find targets automatically; exclude and include lists are relative to src_root
      incl = !defined?( @include ) ? [@dir_root] : @include.map!{ |f| File.join( @dir_root, f ) }
      excl = !defined?( @exclude ) ? nil : @exclude.map!{ |f| File.join( @dir_root, f ) }

      @build.discover_targets :include => incl, :exclude => excl
    end  # discover_targets

    def add_lib_targets    # add library targets and their dependencies
      if !defined?( @libraries ) || @libraries.nil? || @libraries.empty?
        Build.logger.warn "No libraries in %s" % self.class.name
        return
      end

      # Add each library target to the global list as it is created since it may need
      # to be found as a dependency for a later library
      #
      @libraries.each { |lib|
        t = @build.lib_target lib
        @build.add_targets [t]
      }
    end  # add_lib_targets

    def add_exe_targets    # add executable targets and their dependencies
      if !defined?( @executables ) || @executables.nil? || @executables.empty?
        Build.logger.warn "No executables in %s" % self.class.name
        return
      end

      # An executable cannot be a dependency of another so we can create them all and then
      # add them in one go
      #
      @build.add_targets @executables.map{ |e| @build.exe_target( e ) }
    end  # add_exe_targets

    def add_default_targets    # add any default targets
      @build.add_default_targets @targets
    end  # add_default_targets

    # create necessary directories under obj_root; by default, we create a 'static'
    # subdirectory if we are linking statically; override as needed
    #
    def create_dirs
      dir = File.join @build.obj_root, @dir_root
      cmd = "mkdir -p %s" % (:dynamic == @build.link_type ? dir
                                                          : File.join( dir, 'static' ))
      Util.run_cmd cmd
    end  # create_dirs

    def setup    # main entry point to configure this bundle
      log = Build.logger
      log.debug "Setting up %s ..." % self.class.name

      # create necessary directories under build.obj_root in derived classes

      # discover source files and create associated targets
      discover_targets

      # add library targets
      add_lib_targets

      # add executable targets
      add_exe_targets

      # customize options for individual files as needed

      # default targets to build (may be modified by customize() and later, possibly,
      # by commandline options
      #
      add_default_targets

      log.debug "... done setting up %s" % self.class.name
    end  # setup

    # Finally, add this line at the end of each derived class to register it with the
    # class variable containing all known bundles:
    #
    # Build.add_bundle self
  end  # Bundle

  class LibPlanet < Bundle

    def initialize build    # see notes at Bundle.initialize
      super
      @dir_root = '.'

      # libraries -- array of hashes, one per library; each library needs these keys:
      #
      #  :name   -- name of dynamic library excluding extension
      #  :files  -- set of object files, excluding extension
      #  :libs   -- set of user library dependencies [optional]
      #  :linker -- :ld_cc or :ld_cxx for C or C++ linking respectively
      #
      @libraries = [{ :name   => 'libPlanet',
                      :files  => %w{ planet },
                      :linker => :ld_cc }]

      # an executable is defined by a name, list of objects and libraries and type of link
      @executables = [{ :name   => 'hello',
                        :files  => ['main'],
                        :libs   => ['libPlanet'],
                        :linker => :ld_cxx }]

      # default targets to build
      @targets = ['libPlanet', :lib, 'hello', :exe]
    end  # initialize

    def setup    # main entry point to configure libPlanet
      log = Build.logger
      log.debug "Setting up libPlanet ..."

      # create necessary directories
      create_dirs

      # discover source files and create associated targets
      discover_targets

      # add library targets
      add_lib_targets

      # add executable targets
      add_exe_targets

      # default targets to build (may be modified by customize() and later, possibly,
      # by commandline options
      #
      add_default_targets

      log.debug "... done setting up libPlanet"
    end  # setup

    Build.add_bundle self
  end  # LibPlanet

end  # Build

Build.start
