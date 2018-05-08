require 'yaml'
require 'rubygems'
require 'rubygems/package'
require 'zlib'

module OsCtld
  # An interface for reading tar archives generated by
  # {OsCtl::Lib::Container::Exporter}
  class Container::Importer
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System

    def initialize(pool, io)
      @pool = pool
      @tar = Gem::Package::TarReader.new(io)
    end

    # Load metadata describing the archive
    #
    # Loading the metadata is the first thing that should be done, because all
    # other methods depend on its result.
    def load_metadata
      ret = tar.seek('metadata.yml') do |entry|
        YAML.load(entry.read)
      end
      fail 'metadata.yml not found' unless ret
      @metadata = ret
      ret
    end

    def user_name
      metadata['user']
    end

    def group_name
      metadata['group']
    end

    def ct_id
      metadata['container']
    end

    # Create a new instance of {User} as described by the tar archive
    #
    # The returned user is not registered in the internal database, it may even
    # conflict with a user already registered in the database.
    def load_user
      User.new(
        pool,
        metadata['user'],
        config: tar.seek('config/user.yml') { |entry| entry.read }
      )
    end

    # Create a new instance of {Group} as described by the tar archive
    #
    # The returned group is not registered in the internal database, it may even
    # conflict with a group already registered in the database.
    def load_group
      Group.new(
        pool,
        metadata['group'],
        config: tar.seek('config/group.yml') { |entry| entry.read },
        devices: false
      )
    end

    # Create a new instance of {Container} as described by the tar archive
    #
    # The returned CT is not registered in the internal database, it may even
    # conflict with a CT already registered in the database.
    #
    # @param opts [Hash] options
    # @option opts [String] id defaults to id from the archive
    # @option opts [User] user calls {#get_or_create_user} by default
    # @option opts [Group] group calls {#get_or_create_group} by default
    # @option opts [String] dataset
    # @option opts [Hash] ct_opts container options
    def load_ct(opts)
      id = opts[:id] || metadata['container']
      user = opts[:user] || get_or_create_user
      group = opts[:group] || get_or_create_group
      ct_opts = opts[:ct_opts] || {}
      ct_opts[:load_from] = tar.seek('config/container.yml') { |entry| entry.read }

      Container.new(
        pool,
        id,
        user,
        group,
        opts[:dataset] || Container.default_dataset(pool, id),
        ct_opts
      )
    end

    # Load the user from the archive and register him
    #
    # If a user with the same name already exists and all his parameters are the
    # same, the existing user is returned. Otherwise an exception is raised.
    def get_or_create_user
      name = metadata['user']

      db = DB::Users.find(name, pool)
      u = load_user

      if db.nil?
        # The user does not exist, create him
        Commands::User::Create.run!(
          pool: pool.name,
          name: u.name,
          ugid: u.ugid,
          offset: u.offset,
          size: u.size
        )

        return DB::Users.find(name, pool) || (fail 'expected user')
      end

      %i(ugid offset size).each do |param|
        mine = db.send(param)
        other = u.send(param)
        next if mine == other

        fail "user #{pool.name}:#{name} already exists: #{param} mismatch: "+
             "existing #{mine}, trying to import #{other}"
      end

      db
    end

    # Load the group from the archive and register it
    #
    # If a group with the same name already exists and all its parameters are the
    # same, the existing group is returned. Otherwise an exception is raised.
    def get_or_create_group
      name = metadata['group']

      db = DB::Groups.find(name, pool)
      grp = load_group

      if db.nil?
        # The group does not exist, create it
        Commands::Group::Create.run!(
          pool: pool.name,
          name: grp.name
        )

        return DB::Groups.find(name, pool) || (fail 'expected group')
      end

      db
    end

    # Load user-defined script hooks from the archive and install them
    # @param ct [Container]
    def install_user_hook_scripts(ct)
      tar.each do |entry|
        next if !entry.full_name.start_with?('hooks/') || !entry.file? \
                || entry.full_name.count('/') > 1

        name = File.basename(entry.full_name)
        next unless Container::Hook.exist?(name.gsub(/-/, '_').to_sym)

        copy_file_to_disk(entry, File.join(ct.user_hook_script_dir, name))
      end
    end

    # Create the root and all descendants datasets
    #
    # @param builder [Container::Builder]
    def create_datasets(builder)
      each_dataset(builder) do |ds|
        builder.create_dataset(ds, offset: true, parents: ds.root?)
      end
    end

    def load_rootfs(builder)
      case metadata['format']
      when 'zfs'
        load_streams(builder)

      when 'tar'
        unpack_rootfs(builder)

      else
        fail "unsupported archive format '#{metadata['format']}'"
      end
    end

    # Load ZFS data streams from the archive and write them to appropriate
    # datasets
    #
    # @param builder [Container::Builder]
    def load_streams(builder)
      each_dataset(builder) do |ds|
        load_stream(builder, ds, File.join(ds.relative_name, 'base'), true)
        load_stream(builder, ds, File.join(ds.relative_name, 'incremental'), false)
      end

      tar.seek('snapshots.yml') do |entry|
        snapshots = YAML.load(entry.read)

        each_dataset(builder) do |ds|
          snapshots.each { |snap| zfs(:destroy, nil, "#{ds}@#{snap}") }
        end
      end
    end

    def unpack_rootfs(builder)
      # Create private/
      builder.setup_rootfs

      ret = tar.seek('rootfs/base.tar.gz') do |tf|
        IO.popen("exec tar -xz -C #{builder.ct.rootfs}", 'r+') do |io|
          io.write(tf.read(16*1024)) until tf.eof?
        end

        fail "tar failed with exit status #{$?.exitstatus}" if $?.exitstatus != 0
        true
      end

      fail 'rootfs archive not found' unless ret === true
    end

    # Iterate over all container datasets
    #
    # @param builder [Container::Builder]
    # @yieldparam ds [OsCtl::Lib::Zfs::Dataset]
    def each_dataset(builder, &block)
      block.call(builder.ct.dataset)

      @datasets ||= metadata['datasets'].map do |name|
        OsCtl::Lib::Zfs::Dataset.new(
          File.join(builder.ct.dataset.name, name),
          base: builder.ct.dataset.name
        )
      end

      @datasets.each(&block)
    end

    def close
      tar.close
    end

    protected
    attr_reader :pool, :tar, :metadata

    def load_stream(builder, ds, name, required)
      found = nil

      stream_names(name).each do |file, compression|
        tf = tar.find { |entry| entry.full_name == file }

        if tf.nil?
          tar.rewind
          next
        end

        found = [tf, compression]
        break
      end

      if found.nil?
        tar.rewind
        fail "unable to import: #{name} not found" if required
        return
      end

      entry, compression = found
      process_stream(builder, ds, entry, compression)
      tar.rewind
    end

    def process_stream(builder, ds, tf, compression)
      builder.from_stream(ds) do |recv|
        case compression
        when :gzip
          gz = Zlib::GzipReader.new(tf)
          recv.write(gz.readpartial(16*1024)) until gz.eof?
          gz.close

        when :off
          recv.write(tf.read(16*1024)) until tf.eof?

        else
          fail "unexpected compression type '#{compression}'"
        end
      end
    end

    def stream_names(name)
      base = File.join('rootfs', "#{name}.dat")
      [[base, :off], ["#{base}.gz", :gzip]]
    end

    # Copy file from the tar archive to disk
    # @param entry [Gem::Package::TarReader::Entry]
    # @param dst [String]
    def copy_file_to_disk(entry, dst)
      File.open(dst, 'w', entry.header.mode & 07777) do |df|
        df.write(entry.read(16*1024)) until entry.eof?
      end
    end
  end
end
