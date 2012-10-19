#!/usr/bin/ruby -w

# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# Thread pool with job queue for parallel builds
#

# for thread-safe Queue
require 'thread'

class Build
  # Run by a separate thread by invoking #go()
  class Task
    # target object and its method to invoke
    attr :target, :t_method

    def initialize t, m    # target and method
      raise "Missing target" if !t
      raise "Empty method" if !m
      @target, @t_method = t, m
    end  # initialize

    def go    # real work
      @target.send @t_method
    end  # go
  end  # Task

  # Thread pool
  #
  # size  -- create a thread pool with this many threads
  # tasks -- queue of tasks
  # log   -- logger
  #
  class Pool
    attr :size, :tasks, :log

    def initialize size, logger = nil
      raise "Pool size too small" if size < 1
      raise "Pool size too large" if size > 10_000
      @size, @tasks = size, Queue.new
      @log = logger

      Thread.abort_on_exception = true  # exception on any thread aborts application

      # create thread pool
      @log.info "Creating thread pool of size %d" % @size if @log
      @pool = []
      @size.times { |i|
        t = Thread.new {
          # save name of thread and pool in thread-local storage
          Thread.current[ :id ] = "Thr_#{i}"    # name of thread

          # deque task and run it; terminate thread if we get nil
          loop {
            task = @tasks.pop false    # pop and shift are the same for Queue
            if task.nil?
              @tasks << nil     # done; put it back for other threads
              @log.info "#{Thread.current[ :id ]} terminating normally" if @log
              break
            end
            begin    # run task
              @log.info "%s: Starting work on %s ..." %
                [Thread.current[ :id ], task.target.path] if @log
              task.go
              @log.info "%s: ... finished work on %s" %
                [Thread.current[ :id ], task.target.path] if @log
            rescue => ex
              @tasks << nil     # force all other threads to exit
              @log.error Thread.current[ :id ] + ex.message + "\n" +
                ex.backtrace.join( "\n" ) if @log
              raise ex
            end
          }  # thread work loop
        }    # Thread.new
        raise "Failed to create thread #{i}" if !t
        @log.info "Created thread %d" % i if @log
        @pool << t
      }        # times
    end  # initialize

    def add *jobs
      jobs.each { |job|
        raise "Bad task: #{job.class.name}" if Task != job.class
        @tasks << job
      }
    end

    def close    # write nil task and reap all threads
      @tasks << nil
      @pool.map( &:join )
    end
  end  # Pool
end  # Build

if $0 == __FILE__

  # create logger
  log = Logger.new( 'mylog', 2, 100_000 )
  log.formatter = proc { |severity, datetime, progname, msg|
    t = "#{datetime.hour}:#{datetime.min}:#{datetime.sec}"
    "#{Thread.current[ :id ]} #{t} #{severity}: #{msg}\n"
  }
  log.level = Logger::DEBUG    # levels are: DEBUG, INFO, WARN, ERROR and FATAL

  # create pool
  p = Build::Pool.new 2, log

  if false
    t1 = Build::Task.new "sleep 2; echo task1"
    t2 = Build::Task.new "sleep 1; echo task2"
    t3 = Build::Task.new "sleep 1; echo task3"
    #t3 = Build::Task.new "foo"
    t4 = Build::Task.new "sleep 4; echo task4"
    p.add t1, t2, t3, t4;
  else
    t1 = Build::Task.new "cd test; gcc -Wall -Werror -std=c99 -o good good.c"
    #t2 = Build::Task.new "cd test; gcc -Wall -Werror -std=c99 -o bad bad.c"
    t2 = Build::Task.new "cd test; gcc -Wall -Werror -std=c99 -o better better.c"
    p.add t1, t2
  end

  p.close
end
