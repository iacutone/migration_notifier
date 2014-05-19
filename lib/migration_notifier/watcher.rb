module MigrationNotifier
  class Watcher
    attr_reader :notifier
    attr_reader :path
    attr_reader :flags
    attr_reader :id

    def callback!(event)
      @callback[event]
    end

    def close
      if Native.inotify_rm_watch(@notifier.fd, @id) == 0
        @notifier.watchers.delete(@id)
        return
      end

      raise SystemCallError.new("Failed to stop watching #{path.inspect}",
                                FFI.errno)
    end

    def initialize(notifier, path, *flags, &callback)
      @notifier = notifier
      @callback = callback || proc {}
      @path = path
      @flags = flags.freeze
      @id = Native.inotify_add_watch(@notifier.fd, path.dup,
        Native::Flags.to_mask(flags))

      unless @id < 0
        @notifier.watchers[@id] = self
        return
      end

      raise SystemCallError.new(
        "Failed to watch #{path.inspect}" +
        case FFI.errno
        when Errno::EACCES::Errno; ": read access to the given file is not permitted."
        when Errno::EBADF::Errno; ": the given file descriptor is not valid."
        when Errno::EFAULT::Errno; ": path points outside of the process's accessible address space."
        when Errno::EINVAL::Errno; ": the given event mask contains no legal events; or fd is not an inotify file descriptor."
        when Errno::ENOMEM::Errno; ": insufficient kernel memory was available."
        when Errno::ENOSPC::Errno; ": The user limit on the total number of inotify watches was reached or the kernel failed to allocate a needed resource."
        else; ""
        end,
        FFI.errno)
    end
  end
end