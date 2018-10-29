require 'osctld/commands/base'

module OsCtld
  class Commands::Container::Runscript < Commands::Base
    handle :ct_runscript

    include OsCtl::Lib::Utils::Log
    include Utils::SwitchUser

    def execute
      ct = DB::Containers.find(opts[:id], opts[:pool])
      error!('container not found') unless ct

      ct.inclusively do
        error!('container not running') if !ct.running? && !opts[:run]

        client.send({status: true, response: 'continue'}.to_json + "\n", 0)

        ct_runscript(ct, opts[:script])
      end
    end
  end
end