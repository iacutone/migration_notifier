module MigrationNotifier
  class Notifier
    attr_reader :watchers
    attr_reader :fd
    
    def to_io
      unless self.class.supports_ruby_io?
        raise NotImplementedError.new("INotify::Notifier#to_io is not supported under JRuby")
      end
      @io ||= IO.new(@fd)
    end

    # Watches a file or directory for changes,
    # calling the callback when there are.
    # This is only activated once \{#process} or \{#run} is called.
    #
    # **Note that by default, this does not recursively watch subdirectories
    # of the watched directory**.
    # To do so, use the `:recursive` flag.
    # 
    # ### Directory-Specific Flags
    #
    # These flags only apply when a directory is being watched.
    # `:create`
    # : A file is created in the watched directory.
    #
    # ### Options Flags
    #
    # These flags don't actually specify events.
    # Instead, they specify options for the watcher.
    #
    # `:onlydir`
    # : Only watch the path if it's a directory.
    #
    # @param path [String] The path to the file or directory
    # @param flags [Array<Symbol>] Which events to watch for
    # @yield [event] A block that will be called
    #   whenever one of the specified events occur
    # @yieldparam event [Event] The Event object containing information
    #   about the event that occured
    # @return [Watcher] A Watcher set up to watch this path for these events
    # @raise [SystemCallError] if the file or directory can't be watched,
    #   e.g. if the file isn't found, read access is denied,
    #   or the flags don't contain any events
    def watch(path, *flags, &callback)
      return Watcher.new(self, path, *flags, &callback) unless flags.include?(:recursive)

      dir = Dir.new(path)

      dir.each do |base|
        d = File.join(path, base)
        binary_d = d.respond_to?(:force_encoding) ? d.dup.force_encoding('BINARY') : d
        next if binary_d =~ /\/\.\.?$/ # Current or parent directory
        watch(d, *flags, &callback) if !RECURSIVE_BLACKLIST.include?(d) && File.directory?(d)
      end

      dir.close

      rec_flags = [:create, :moved_to]
      return watch(path, *((flags - [:recursive]) | rec_flags)) do |event|
        callback.call(event) if flags.include?(:all_events) || !(flags & event.flags).empty?
        next if (rec_flags & event.flags).empty? || !event.flags.include?(:isdir)
        begin
          watch(event.absolute_name, *flags, &callback)
        rescue Errno::ENOENT
          # If the file has been deleted since the glob was run, we don't want to error out.
        end
      end
    end

    # Starts the notifier watching for filesystem events.
    # Blocks until \{#stop} is called.
    #
    # @see #process
    def run
      @stop = false
      process until @stop
    end

    # Stop watching for filesystem events.
    # That is, if we're in a \{#run} loop,
    # exit out as soon as we finish handling the events.
    def stop
      @stop = true
    end

    # Blocks until there are one or more filesystem events
    # that this notifier has watchers registered for.
    # Once there are events, the appropriate callbacks are called
    # and this function returns.
    #
    # @see #run
    def process
      read_events.each {|event| event.callback!}
    end

    # Close the notifier.
    #
    # @raise [SystemCallError] if closing the underlying file descriptor fails.
    def close
      if Native.close(@fd) == 0
        @watchers.clear
        return
      end

      raise SystemCallError.new("Failed to properly close inotify socket" +
       case FFI.errno
       when Errno::EBADF::Errno; ": invalid or closed file descriptior"
       when Errno::EIO::Errno; ": an I/O error occured"
       end,
       FFI.errno)
    end

    # Blocks until there are one or more filesystem events
    # that this notifier has watchers registered for.
    # Once there are events, returns their {Event} objects.
    #
    # {#run} or {#process} are ususally preferable to calling this directly.
    def read_events
      size = 64 * Native::Event.size
      tries = 1

      begin
        data = readpartial(size)
      rescue SystemCallError => er
        # EINVAL means that there's more data to be read
        # than will fit in the buffer size
        raise er unless er.errno == Errno::EINVAL::Errno || tries == 5
        size *= 2
        tries += 1
        retry
      end

      events = []
      cookies = {}
      while event = Event.consume(data, self)
        events << event
        next if event.cookie == 0
        cookies[event.cookie] ||= []
        cookies[event.cookie] << event
      end
      cookies.each {|c, evs| evs.each {|ev| ev.related.replace(evs - [ev]).freeze}}
      events
    end

    private

    # Same as IO#readpartial, or as close as we need.
    def readpartial(size)
      # Use Ruby's readpartial if possible, to avoid blocking other threads.
      return to_io.readpartial(size) if self.class.supports_ruby_io?

      tries = 0
      begin
        tries += 1
        buffer = FFI::MemoryPointer.new(:char, size)
        size_read = Native.read(fd, buffer, size)
        return buffer.read_string(size_read) if size_read >= 0
      end while FFI.errno == Errno::EINTR::Errno && tries <= 5

      raise SystemCallError.new("Error reading inotify events" +
        case FFI.errno
        when Errno::EAGAIN::Errno; ": no data available for non-blocking I/O"
        when Errno::EBADF::Errno; ": invalid or closed file descriptor"
        when Errno::EFAULT::Errno; ": invalid buffer"
        when Errno::EINVAL::Errno; ": invalid file descriptor"
        when Errno::EIO::Errno; ": I/O error"
        when Errno::EISDIR::Errno; ": file descriptor is a directory"
        else; ""
        end,
        FFI.errno)
    end
  end
end