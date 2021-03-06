require 'osctld/commands/logged'

module OsCtld
  class Commands::Container::Stop < Commands::Logged
    handle :ct_stop

    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::SwitchUser

    def find
      ct = DB::Containers.find(opts[:id], opts[:pool])
      ct || error!('container not found')
    end

    def execute(ct)
      manipulate(ct) do
        progress('Stopping container')

        mode =
          case (opts[:method] || 'shutdown_or_kill')
          when 'shutdown_or_kill'
            :stop
          when 'shutdown_or_fail'
            :shutdown
          when 'kill'
            :kill
          else
            error!("unknown stop method '#{opts[:method]}'")
          end

        begin
          Container::Hook.run(ct, :pre_stop)

        rescue HookFailed => e
          error!(e.message)
        end

        begin
          ContainerControl::Commands::Stop.run!(
            ct,
            mode,
            timeout: opts[:timeout] || 60,
          )
        rescue ContainerControl::UserRunnerError
          progress('Unable to stop, killing by force')
          error!('Unable to kill or cleanup') unless force_kill(ct)
        rescue ContainerControl::Error => e
          error!(e.message)
        end

        remove_cgroups(ct)

        if ct.ephemeral? && !indirect?
          call_cmd!(
            Commands::Container::Delete,
            pool: ct.pool.name,
            id: ct.id,
            force: true,
          )
        end

        ok
      end
    end

    protected
    # @return [Boolean]
    def force_kill(ct)
      recovery = Container::Recovery.new(ct)

      # Freeze all processes before the kill
      CGroup.freeze_tree(ct.cgroup_path)

      # Send SIGKILL to all processes
      progress('Killing container processes')
      recovery.kill_all

      # Thaw all processes
      CGroup.thaw_tree(ct.cgroup_path)

      # Give the system some time to kill the processes
      sleep(10)

      progress('Recovering container state')
      recovery.recover_state

      progress('Cleaning up')
      recovery.cleanup_or_taint
    end

    # Remove accounting cgroups to reset counters
    def remove_cgroups(ct)
      tries = 0

      begin
        %w(blkio cpuacct memory).each do |subsys|
          CGroup.rmpath(CGroup.real_subsystem(subsys), ct.base_cgroup_path)
        end
      rescue SystemCallError => e
        ct.log(:warn, "Error occurred while pruning cgroups: #{e.message}")

        return if tries >= 5
        tries += 1
        sleep(0.5)
        retry
      end
    end
  end
end
