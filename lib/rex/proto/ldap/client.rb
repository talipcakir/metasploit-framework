require 'net/ldap'

module Rex
  module Proto
    module LDAP
      # This is a Rex Proto wrapper around the Net::LDAP client which is currently coming from the 'net-ldap' gem.
      # The purpose of this wrapper is to provide 'peerhost' and 'peerport' methods to ensure the client interfaces
      # are consistent between various session clients.
      class Client < Net::LDAP

        # @return [Rex::Socket]
        attr_reader :socket

        def initialize(args)
          @base_dn = args[:base]
          super
        end

        # @return [Array<String>] LDAP servers naming contexts
        def naming_contexts
          @naming_contexts ||= search_root_dse[:namingcontexts]
        end

        # @return [String] LDAP servers Base DN
        def base_dn
          @base_dn ||= discover_base_dn
        end

        # @return [String, nil] LDAP servers Schema DN, nil if one isn't found
        def schema_dn
          @schema_dn ||= discover_schema_naming_context
        end

        # @return [String] The remote IP address that LDAP is running on
        def peerhost
          host
        end

        # @return [Integer] The remote port that LDAP is running on
        def peerport
          port
        end

        # @return [String] The remote peer information containing IP and port
        def peerinfo
          "#{peerhost}:#{peerport}"
        end

        # https://github.com/ruby-ldap/ruby-net-ldap/issues/11
        # We want to keep the ldap connection open to use later
        # but there's no built in way within the `Net::LDAP` library to do that
        # so we're
        # @param connect_opts [Hash] Options for the LDAP connection.
        def self._open(connect_opts)
          client = new(connect_opts)
          client._open
        end

        # https://github.com/ruby-ldap/ruby-net-ldap/issues/11
        def _open
          raise Net::LDAP::AlreadyOpenedError, 'Open already in progress' if @open_connection

          instrument 'open.net_ldap' do |payload|
            @open_connection = new_connection
            @socket = @open_connection.socket
            payload[:connection] = @open_connection
            payload[:bind] = @result = @open_connection.bind(@auth)
            return self
          end
        end

        def discover_schema_naming_context
          result = search(base: '', attributes: [:schemanamingcontext], scope: Net::LDAP::SearchScope_BaseObject)
          if result.first && !result.first[:schemanamingcontext].empty?
            schema_dn = result.first[:schemanamingcontext].first
            ilog("#{peerinfo} Discovered Schema DN: #{schema_dn}")
            return schema_dn
          end
          wlog("#{peerinfo} Could not discover Schema DN")
          nil
        end

        def discover_base_dn
          unless naming_contexts
            elog("#{peerinfo} Base DN cannot be determined, no naming contexts available")
            return
          end

          # NOTE: Find the first entry that starts with `DC=` as this will likely be the base DN.
          result = naming_contexts.select { |context| context =~ /^([Dd][Cc]=[A-Za-z0-9-]+,?)+$/ }
                                  .reject { |context| context =~ /(Configuration)|(Schema)|(ForestDnsZones)/ }
          if result.blank?
            elog("#{peerinfo} A base DN matching the expected format could not be found!")
            return
          end
          base_dn = result[0]

          dlog("#{peerinfo} Discovered base DN: #{base_dn}")
          base_dn
        end
      end
    end
  end
end
