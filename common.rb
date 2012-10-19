# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# Common utilities
#

%w{ open3 logger }.each{ |s| require s }

# common utilities and enhancements of system classes

# add some useful methods to File class
class File
  # return base name of a file: final path component with any extension stripped off
  def File.bname path
    File.basename path, File.extname( path )
  end

  # check that all paths exist and are readable
  def File.check_er( *path )
    path.each { |p|
      raise "path is nil"          if !p
      raise "path is empty"        if 0 == p.size
      raise "#{p} does not exist"  if !File.exist?( p )
      raise "#{p} not readable"    if !File.readable?( p )
    }
  end

  # check that all paths exist, are readable, and are plain files
  def File.check_file( *path )
    path.each { |p|
      File.check_er( p )
      raise "#{p} not a plain file" if !File.file?( p )
    }
  end

  # check that all paths exist, are executable, and are plain files
  def File.check_ex( *path )
    path.each { |p|
      raise "#{p} does not exist"    if !File.exist?( p )
      raise "#{p} not executable"    if !File.executable?( p )
      raise "#{p} not a plain file"  if !File.file?( p )  # symlink is also a plain file
    }
  end

  # check that all paths exist, are readable and are directories
  def File.check_dir( *path )
    path.each { |p|
      File.check_er( p )
      raise "#{p} not a directory" if !File.directory?( p )
    }
  end
end  # File

class Build
  # simple timer class
  class Timer
    # accumulated user and system times and last chunk
    attr_reader :utime, :stime, :ulast, :slast

    def initialize
      @utime = @stime = @ulast = @slast = 0
      @begin = nil
    end  # initialize

    def start
      raise "Timer already started" if @begin
      @begin = Process.times
    end  # start

    def stop
      raise "Timer not started" if !@begin
      fin = Process.times
      @ulast, @slast = (fin.utime - @begin.utime), (fin.stime - @begin.stime)
      @utime += @ulast
      @stime += @slast
      @begin = nil
    end  # stop

    # print cumulative time
    def print_time( fmt )
      printf( fmt, utime, stime )
    end  # print_time

    # print last time
    def print_last( fmt )
      printf( fmt, ulast, slast )
    end  # print_last
  end  # Timer

  # All classes use this logger
  class LogMain

    # default number of log files and their maximum size (bytes)
    DEF_COUNT, DEF_SIZE = 2, 3_000_000

    # Logger parameters must be set by invoking this class method before the first
    # invocation of get()
    #
    # file_name -- base name of file
    # file_cnt -- number of files
    # file_size -- max size of files
    #
    def self.set_log_file_params params
      raise "Already initialized" if defined? @@initialized

      # file name is required
      name = params[ :name ]
      raise "Missing file name" if !name
      name.strip!
      raise "Empty file name" if name.empty?
      @@file_name = name

      # other parameters are optional
      if !params[ :file_cnt ]
        @@file_cnt = DEF_COUNT
      else
        cnt = params[ :count ]
        raise "Bad file count" if (cnt < 1 || cnt > 100)
        @@file_cnt = cnt
      end
      if !params[ :file_size ]
        @@file_size = DEF_SIZE
      else
        size = params[ :size ]
        raise "Bad file size" if (size < 32_000 || size > 2**30)
        @@file_size = size
      end
      @@initialized = true
    end  # set_log_file_params

    def self.get    # create unique logger and return it
      return @@log if defined? @@log
      raise "#{self} not initialized" if !defined? @@initialized

      # create new logger
      log = Logger.new @@file_name, @@file_cnt, @@file_size

      #log.datetime_format = "%H:%M:%S"
      log.formatter = proc { |severity, datetime, progname, msg|
        t = "#{datetime.hour}:#{datetime.min}:#{datetime.sec}"
        "#{Thread.current[ :id ]} #{t} #{severity}: #{msg}\n"
      }

      # levels are: DEBUG, INFO, WARN, ERROR and FATAL
      log.level = Logger::DEBUG
      #level = Logger::INFO
      @@log = log
    end  # get

  end  # LogMain

  class Util    # various utilities

    # if argument is a relative path, return full path to it in PATH or nil if not found;
    # otherwise (argument is absolute) return it unchanged if it exists, nil if not.
    #
    def self.find_in_path( name )
      raise "Argument is nil" if !name
      nm = name.strip
      raise "Argument is blank" if name.empty?
      return (File.executable?( nm ) ? nm : nil) if '/' == name[ 0 ]    # absolute path

      if !defined? @@path
        @@path = ENV[ 'PATH' ].split ':'
        raise "PATH is empty" if @@path.empty?
        @@path.map( &:strip! )
      end
      @@path.each{ |p| s = File.join( p, name ); return s if File.executable?( s ) }
      nil
    end  # find_in_path

    # run given shell command; the command is logged if a logger is provided
    # if command is successful:
    #     return 2 element array [true, s] where s is stripped command output and, if a
    #     logger is provided, and output is non-empty, log output;
    # if command failed
    #     create a message string that combines stdout and stderr and log it if a logger is
    #     provided; then, if die is true, raise exception; otherwise, [false, s] where s
    #     is the message string.
    #
    def self.run_cmd cmd, log = nil, die = true
      log.info cmd if log
      out, err, status = Open3.capture3( cmd )
      out.strip!; err.strip!
      if status.success?
        log.info out if log && !out.empty?
        return [true, out]
      end

      # command failed
      msg = 'Command failed:'
      if out.empty?
        msg += ' No output'
      else
        msg += ' Output = ' + out
      end
      if err.empty?
        msg += '. No error output.'
      else
        msg += ' Error output = ' + err
      end
      log.error msg if log
      raise msg if die
      [false, msg]

    end  # run_cmd

    def self.strip str    # strip string raising exception if it is empty
      raise "String is nil" if !str
      s = str.strip
      raise "Empty string" if s.empty?
      s
    end  # strip

    # overwrites current line on screen by moving the cursor back to column 1 and writing
    # given status string of the form: N targets remain
    #
    def self.print_status cnt
      # for some reason this is not working:
      STDERR.print "\e[2K\e[100D%d targets remain" % cnt

      # $stderr.puts "%d targets remain" % cnt; $stderr.flush
    end  # print_status

  end  # Util

end  # Build
