#!/usr/bin/ruby -w

# Ruby-based build system.
# Author: ram (Munagala V. Ramanath)
#
# A simple histogram class for integer values: values below range are put in first
# bucket, those above in last.
#
class Histogram
  attr :item_count

  # t   -- title
  # ran -- value range [min..max]
  # n   -- number of buckets
  #
  def initialize( t, ran, n )
    # error check
    nB = n.to_i
    raise "Bucket count #{n} must be integral" if nB != n
    raise "Too many buckets: #{nB}" if nB >= (1 << 26)
    raise "Too few buckets: #{nB}"  if nB <= 1
    raise "Range too small: #{ran}" if ran.min >= ran.max

    r = ran.max - ran.min
    dm = r.divmod( nB )
    i = dm[ 1 ] > 0 ? (1 + dm[ 0 ]) : dm[ 0 ]
    raise "interval size is 0" if i < 1

    @interval, @range, @buckets = i, ran, Array.new( nB, 0 )
    @item_count = @cntHi = @cntLo = 0
    @item_sum = 0
    @title = t
    #printf( "interval = %d, range = %s\n", @interval, @range )
  end  # initialize

  # add item to appropriate bucket
  def add item
    val = item.to_i
    @item_sum += val
    @item_count += 1

    if !defined? @min
      @min = @max = val
    else
      @min = val if ( val < @min )
      @max = val if ( val > @max )
    end

    # values below range get dumped into the first bucket and those above
    # into the last
    #
    if ( val < @range.min )
      @buckets[ 0 ] += 1
      @cntLo += 1
      return
    end
    if ( val >= @range.max )
      @buckets[ -1 ] += 1
      @cntHi += 1
      return
    end

    # normal case
    idx = (val - @range.min) / @interval
    @buckets[ idx ] += 1
    #printf( "val = %d, idx = %d\n", val, idx )
  end  # add

  # return average of values
  def avg
    @item_sum.to_f / @item_count.to_f
  end  # avg

  # print histogram
  def dump log
    log.info "Histogram for %s" % @title

    msg = "nTotal = %d, nLow = %d, nHigh = %d, " % [@item_count, @cntLo, @cntHi]
    msg += "min = %d, max = %d, avg = %f" % [@min, @max, avg]
    log.info msg

    low = @range.min
    @buckets.each { |val| log.info "%3d-  %d" % [low, val]; low += @interval }
  end  # dump
  
  # Testing

  def self.test1
    Histogram.new( 'test1', 8..8, 2 )   # fail
  end  # test1

  def self.test2
    Histogram.new( 'test2', 8..9, 1 )   # fail
  end  # test2

  def self.test3
    min, max, nBuckets = 8, 190, 10
    h = Histogram.new( 'test3', min...max, nBuckets )
    1000.times { |i|
      h.add( rand( max ) )
    }
    h.print
  end  # test3

  def self.test4
    min, max, nBuckets = 0, 1000, 10
    h = Histogram.new( 'test3', min...max, nBuckets )
    10000.times { |i|
      h.add( rand( max ) )
    }
    h.print
  end  # test4
end  # Histogram

if __FILE__ == $0
  #Histogram.test1
  #Histogram.test2
  #Histogram.test3
  Histogram.test4
end  # if
