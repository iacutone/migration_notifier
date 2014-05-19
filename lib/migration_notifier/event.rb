module MigrationNotifier
  class Event
    attr_reader :related

    # The name of the file that the event occurred on.
    # This is only set for events that occur on files in directories;
    # otherwise, it's `""`.
    # Similarly, if the event is being fired for the directory itself
    # the name will be `""`
    #
    # This pathname is relative to the enclosing directory.
    # For the absolute pathname, use \{#absolute\_name}.
    # Note that when the `:recursive` flag is passed to {Notifier#watch},
    # events in nested subdirectories will still have a `#name` field
    # relative to their immediately enclosing directory.
    # For example, an event on the file `"foo/bar/baz"`
    # will have name `"baz"`.
    #
    # @return [String]
    attr_reader :name
    attr_reader :notifier
    attr_reader :cookie
    attr_reader :watcher_id

    def watcher
      @watcher ||= @notifier.watchers[@watcher_id]
    end

    def absolute_name
      return watcher.path if name.empty?
      return File.join(watcher.path, name)
    end

    # Returns the flags that describe this event.
    # This is generally similar to the input to {Notifier#watch},
    # except that it won't contain options flags nor `:all_events`,
    # and it may contain one or more of the following flags:
    #
    # `:unmount`
    # : The filesystem containing the watched file or directory was unmounted.
    #
    # `:ignored`
    # : The \{#watcher watcher} was closed, or the watched file or directory was deleted.
    #
    # `:isdir`
    # : The subject of this event is a directory.
    #
    # @return [Array<Symbol>]
    def flags
      @flags ||= Native::Flags.from_mask(@native[:mask])
    end

    # Constructs an {Event} object from a string of binary data,
    # and destructively modifies the string to get rid of the initial segment
    # used to construct the Event.
    #
    # @private
    # @param data [String] The string to be modified
    # @param notifier [Notifier] The {Notifier} that fired the event
    # @return [Event, nil] The event, or `nil` if the string is empty
    def self.consume(data, notifier)
      return nil if data.empty?
      ev = new(data, notifier)
      data.replace data[ev.size..-1]
      ev
    end

    # Creates an event from a string of binary data.
    # Differs from {Event.consume} in that it doesn't modify the string.
    #
    # @private
    # @param data [String] The data string
    # @param notifier [Notifier] The {Notifier} that fired the event
    def initialize(data, notifier)
      ptr = FFI::MemoryPointer.from_string(data)
      @native = Native::Event.new(ptr)
      @related = []
      @cookie = @native[:cookie]
      @name = fix_encoding(data[@native.size, @native[:len]].gsub(/\0+$/, ''))
      @notifier = notifier
      @watcher_id = @native[:wd]

      raise Exception.new("inotify event queue has overflowed.") if @native[:mask] & Native::Flags::IN_Q_OVERFLOW != 0
    end

    # Calls the callback of the watcher that fired this event,
    # passing in the event itself.
    #
    # @private
    def callback!
      watcher.callback!(self)
    end

    # Returns the size of this event object in bytes,
    # including the \{#name} string.
    #
    # @return [Fixnum]
    def size
      @native.size + @native[:len]
    end

    private

    def fix_encoding(name)
      name.force_encoding('filesystem') if name.respond_to?(:force_encoding)
      name
    end
  end
end