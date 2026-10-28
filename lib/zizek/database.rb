# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Zizek
  # Where a counterexample goes after the run that found it.
  #
  # A database is a cache that never needs invalidating. It stores raw
  # serialized choice streams — the bytes under a reproduce blob, not the blob
  # — keyed by a property's name, so the next run replays yesterday's failure
  # instead of hoping to rediscover it.
  #
  # Both digests are the project's compiled keyed-draw hash (ir/keys.zir), so a
  # directory written by this gem is byte-for-byte the directory the Python and
  # Go packages write.
  module Database
    # Where a database goes when a caller asks for one without saying where.
    DEFAULT_PATH = ".zizek/examples"

    # An entry's filename: sixteen lowercase hex digits and nothing else.
    # Anything else in a key directory belongs to something other than the
    # engine — .name, a .gitignore, an editor's swap file — and is ignored
    # rather than replayed.
    ENTRY_PATTERN = /\A[0-9a-f]{16}\z/.freeze

    # The file naming a key directory, for a human reading a checkout. The
    # engine writes it and never reads it.
    NAME_FILE = ".name"

    module_function

    # The sixteen hex digits a name or a stream is stored under.
    #
    # FNV-1a 64 over the tagged encoding compiled from ir/keys.zir, which is the
    # same hash a keyed draw uses and the reason a database directory is
    # portable across languages.
    def digest(value)
      format("%016x", Zizek.key_hash(value.to_s.b))
    end

    # The order stored entries are replayed in: shortest first, then bytes.
    # The same order the shrinker prefers, so the simplest stored
    # counterexample is the first one a run pays for.
    def shortlex(stream)
      [stream.bytesize, stream]
    end

    # Turn what a caller passed for `database:` into a database or nil.
    #
    # nil and false disable it, true selects the default directory, ":memory:"
    # an in-memory one, any other string or Pathname a directory, and anything
    # else is assumed to implement fetch/save/delete itself.
    def resolve(spec)
      return nil if spec.nil? || spec == false
      return Directory.new(DEFAULT_PATH) if spec == true
      return Memory.new if spec == ":memory:"
      return Directory.new(spec) if spec.is_a?(String) || spec.respond_to?(:to_path)

      %i[fetch save delete].each do |method|
        next if spec.respond_to?(method)

        raise ArgumentError,
              "database must be a path, \":memory:\", true, nil, or an object " \
              "responding to fetch/save/delete; #{spec.inspect} does not respond to #{method}"
      end
      spec
    end

    # A database that forgets when the process exits.
    #
    # For a suite that wants replay within a run — or a test about the database
    # itself — without leaving anything behind.
    class Memory
      def initialize
        @entries = Hash.new { |store, key| store[key] = [] }
      end

      def inspect
        "#<Zizek::Database::Memory>"
      end

      def fetch(key)
        @entries.key?(key) ? @entries[key].dup : []
      end

      def save(key, value)
        stream = value.b.freeze
        @entries[key] << stream unless @entries[key].include?(stream)
      end

      def delete(key, value)
        return unless @entries.key?(key)

        @entries[key].delete(value.b)
        @entries.delete(key) if @entries[key].empty?
      end
    end

    # A directory of counterexamples, one subdirectory per property.
    #
    # The layout is shared with every other zizek package, so a directory
    # checked into version control replays in any of them:
    #
    #   .zizek/examples/
    #     9dc0c2b1f8a17c4e/          # the key's digest
    #       .name                    # the property's name, for a human
    #       3a6e0f5c9b2d1877         # a stored stream
    #
    # Every operation is best-effort: a database that cannot be read or written
    # must not fail a test that would otherwise pass.
    class Directory
      attr_reader :path

      def initialize(path = DEFAULT_PATH)
        @path = path.to_s
      end

      def inspect
        "#<Zizek::Database::Directory #{path.inspect}>"
      end

      def ==(other)
        other.is_a?(Directory) && other.path == path
      end
      alias eql? ==

      def hash
        [Directory, path].hash
      end

      def key_path(key)
        File.join(path, Database.__send__(:digest, key))
      end

      def value_path(key, value)
        File.join(key_path(key), Database.__send__(:digest, value))
      end

      private :key_path, :value_path

      def fetch(key)
        directory = key_path(key)
        names = begin
          Dir.children(directory)
        rescue SystemCallError
          return []
        end
        names.select { |name| ENTRY_PATTERN.match?(name) }.map do |name|
          begin
            File.binread(File.join(directory, name))
          rescue SystemCallError
            # Deleted between the listing and the read: a concurrent run
            # collected it, which is exactly what it is supposed to do.
            nil
          end
        end.compact
      end

      def save(key, value)
        directory = key_path(key)
        FileUtils.mkdir_p(directory)
        name_file = File.join(directory, NAME_FILE)
        Database.__send__(:atomic_write, name_file, key.to_s.b) unless File.exist?(name_file)
        entry = File.join(directory, Database.__send__(:digest, value))
        Database.__send__(:atomic_write, entry, value.b) unless File.exist?(entry)
      rescue SystemCallError
        nil
      end

      def delete(key, value)
        File.unlink(value_path(key, value))
        # An emptied key directory takes its .name with it, so a database that
        # collected everything leaves no husk behind — but only once the last
        # entry is gone, or a directory that still holds counterexamples would
        # lose the label that says whose they are.
        begin
          directory = key_path(key)
          return if Dir.children(directory).any? { |name| ENTRY_PATTERN.match?(name) }

          File.unlink(File.join(directory, NAME_FILE))
          Dir.rmdir(directory)
        rescue SystemCallError
          nil
        end
      rescue SystemCallError
        nil
      end
    end

    # Write through a temporary file, so a reader never sees a partial entry.
    def atomic_write(path, payload)
      directory = File.dirname(path)
      temporary = Tempfile.create(".zizek", directory, binmode: true)
      begin
        temporary.write(payload)
        temporary.close
        File.rename(temporary.path, path)
      rescue SystemCallError
        begin
          File.unlink(temporary.path)
        rescue SystemCallError
          nil
        end
      end
    end

    private_class_method :digest, :shortlex, :resolve, :atomic_write
    private_constant :ENTRY_PATTERN, :NAME_FILE
  end
end
