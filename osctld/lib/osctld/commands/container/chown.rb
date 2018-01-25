module OsCtld
  class Commands::Container::Chown < Commands::Logged
    handle :ct_chown

    include Utils::Log
    include Utils::System
    include Utils::Zfs

    def find
      ct = DB::Containers.find(opts[:id], opts[:pool])
      ct || error!('container not found')
    end

    def execute(ct)
      user = DB::Users.find(opts[:user], ct.pool)
      return error('user not found') unless user

      return error("already owned by #{user.name}") if ct.user == user

      return error('container has to be stopped first') if ct.state != :stopped
      Monitor::Master.demonitor(ct)

      old_user = ct.user

      user.inclusively do
        ct.exclusively do
          # Double check state while having exclusive lock
          next error('container has to be stopped first') if ct.state != :stopped

          progress('Moving LXC configuration')

          # Ensure LXC home
          unless ct.group.setup_for?(user)
            Dir.mkdir(ct.group.userdir(user), 0751)
            File.chown(0, ct.user.ugid, ct.group.userdir(user))
          end

          # Move CT dir
          syscmd("mv #{ct.lxc_dir} #{ct.lxc_dir(user: user)}")
          File.chown(0, user.ugid, ct.lxc_dir(user: user))

          # Chown assets
          File.chown(0, user.ugid, ct.log_path) if File.exist?(ct.log_path)

          # Switch user, regenerate configs
          ct.chown(user)

          # Configure dataset
          progress('Unmounting dataset')
          zfs(:unmount, nil, ct.dataset)

          progress('Switching UID/GID offsets')
          zfs(:set, "uidoffset=#{ct.uid_offset} gidoffset=#{ct.gid_offset}", ct.dataset)

          progress('Remounting dataset')
          zfs(:mount, nil, ct.dataset)

          # Restart monitor
          Monitor::Master.monitor(ct)

          # Clear old LXC home if possible
          unless ct.group.has_containers?(old_user)
            progress('Cleaning up original LXC home')
            Dir.rmdir(ct.group.userdir(old_user))
          end

          ok
        end
      end
    end
  end
end
