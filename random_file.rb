#!/usr/bin/env ruby
require "curses"
Curses.init_screen
Curses.refresh

class String
  def highlighted
    "#{Out.command "30;47m"}#{self}#{Out.command "0m"}"
  end
end

module Sys
  class << self
    def alternate(a, b)
      loop do
        break unless a.call
        break unless b.call
      end
    end

    def quit!
      @quit = true
    end

    def quit?
      @quit
    end
  end
end

module In
  class << self
    def press_any_key
      Curses.getch
    end
  end
end

module Out
  CSI = "\e["

  class << self
    def clear!
      write command("2J")
    end

    def clear_line!
      write command("2K")
    end

    def beginning!
      write command("1;1H")
    end

    def middle!(height)
      write command("#{(height / 2) + 1};1H")
    end

    def trim(str, width)
      if str.length > width
        "#{str[0, width - 3]}..."
      else
        str
      end
    end

    def command(cmd)
      "#{CSI}#{cmd}"
    end

    def write(msg)
      $stdout.write msg
    end

    def puts(msg)
      $stdout.write msg
      $stdout.write "\n\r"
    end

    def hide_cursor!
      Curses.curs_set 0
    end

    def show_cursor!
      Curses.curs_set 1
    end

    def width
      `tput cols`.to_i
    end

    def height
      `tput lines`.to_i
    end
  end
end

module Git
  class << self
    def root_dir
      `git rev-parse --show-toplevel`.strip
    end

    def ls_files
      `cd "#{root_dir}" && git ls-files`
    end
  end
end

class Window
  attr_accessor :index
  attr_reader :files, :first, :middle, :last

  def initialize(files, first, length)
    @files = files
    @first = first
    @middle = first + (length / 2)
    @last = first + length - 1
  end

  def middle?
    index == middle
  end

  def last?
    index == last
  end

  def each
    first.upto last do |i|
      self.index = i
      yield files[index]
    end
  end
end

class Animation
  attr_reader :duration, :first, :last, :start_time, :end_time, :fn

  def initialize(duration, &block)
    @duration = duration.to_f
    @fn = block
  end

  def start!(first, last)
    @first = first
    @last = last
    @start_time = now
    @end_time = @start_time + duration
  end

  def now
    Time.now.to_f
  end

  def finished?
    @finished
  end

  def t
    n = now

    if n >= end_time
      @finished = true
      return 1.0
    end

    (n - start_time) / duration
  end

  def value
    instance_exec t, &fn
  end

  class << self
    def linear(duration)
      new(duration) { |t| ((last - first) * t).floor }
    end
  end
end

class Files
  include Enumerable
  attr_accessor :trimmed_winner
  attr_reader :files, :winner, :winner_index, :screen_width, :screen_height

  def initialize
    @files = Git.ls_files.split.select do |f|
      yield f
    end

    @screen_width = Out.width
    @screen_height = Out.height
    @winner = files.sample
    @winner_index = files.index @winner
    trim!
    adjust_to_winner_window!
  end

  def size
    files.size
  end

  def sliding_window(animation)
    animation.start! 0, size - screen_height

    until animation.finished?
      yield Window.new(self, animation.value, screen_height)
    end
  end

  def each(&block)
    files.each &block
  end

  def [](index)
    files[index]
  end

  private

  def trim!
    files.map! do |f|
      Out.trim f, screen_width
    end

    self.trimmed_winner = Out.trim winner, screen_width
  end

  def adjust_to_winner_window!
    first = winner_index - (screen_height / 2)
    last = first + screen_height - 1
    split_index = last + 1
    split_index = split_index % size
    @files = files[split_index, size - split_index] + files[0, split_index]
  end
end

files = Files.new do |f|
  f =~ /\.rb$/
end

Out.hide_cursor!
Out.clear!

files.sliding_window Animation.linear(5) do |window|
  Out.beginning!

  window.each do |f|
    Out.clear_line!

    if window.middle?
      Out.puts f.highlighted
    elsif window.last?
      Out.write f
    else
      Out.puts f
    end
  end
end

Thread.new do
  Sys.alternate lambda {
    Out.middle! files.screen_height
    Out.write files.trimmed_winner.highlighted
    sleep 0.5
    !Sys.quit?
  }, lambda {
    Out.middle! files.screen_height
    Out.write files.trimmed_winner
    sleep 0.5
    !Sys.quit?
  }
end

In.press_any_key
Sys.quit!
