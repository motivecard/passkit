require "apnotic"

module Passkit
  # A push APNs answered with something other than 200, or never answered.
  class PushError < Error
    attr_reader :status, :reason, :pass_type_identifier

    def initialize(status:, reason:, pass_type_identifier:)
      @status = status
      @reason = reason
      @pass_type_identifier = pass_type_identifier
      super("APNs #{status || "timeout"} #{reason} (#{pass_type_identifier})".squish)
    end
  end

  class PushNotificationService
    POOL_MUTEX = Mutex.new
    LAST_USE_MUTEX = Mutex.new
    # The push token no longer reaches the device (pass deleted, device wiped): Apple
    # asks to stop pushing to it.
    INVALID_TOKEN_REASONS = %w[BadDeviceToken Unregistered].freeze
    # A connection that fails like this is dead: it is closed and the next push opens
    # a new one.
    SOCKET_ERRORS = [SystemCallError, IOError, SocketError, OpenSSL::SSL::SSLError].freeze

    class << self
      # Pushes to the devices of the pass (or only to `devices`) and returns the ones
      # worth pushing again later: no answer even after reconnecting, 429 or 5xx. A
      # device APNs reports as gone is forgotten; other rejections go to
      # push_error_handler. Neither is returned.
      def notify_pass_update(pass, devices: nil)
        devices = (devices || pass.devices).select { |device| device.push_token.present? }
        return [] if devices.empty?

        pass_type_identifier = pass.pass_type_identifier
        connection_pool(pass_type_identifier).with do |connection|
          devices.reject { |device| push(connection, device, pass_type_identifier) }
        end
      end

      # Apple recommends keeping APNs connections open instead of opening one per
      # notification: a new HTTP/2 + TLS handshake cost ~300 ms per push. A pass
      # pushes with a certificate of its own pass type identifier, so there is one
      # pool per identifier, built lazily per process (after Puma forks). When the
      # certificate of an identifier is renewed, its pool is replaced on the next push.
      def connection_pool(pass_type_identifier)
        material = Passkit.signing_material_for(pass_type_identifier)
        POOL_MUTEX.synchronize do
          @pools ||= {}
          fingerprint, pool = @pools[pass_type_identifier]
          return pool if fingerprint == material.fingerprint

          pool&.shutdown(&:close)
          @pools[pass_type_identifier] = [material.fingerprint, build_connection_pool(material)]
          @pools[pass_type_identifier].last
        end
      end

      # Closes every pooled connection.
      def reset_connection_pool!
        pools = POOL_MUTEX.synchronize { (@pools || {}).values.tap { @pools = {} } }
        pools.each { |_fingerprint, pool| pool.shutdown(&:close) }
      end

      private

      def build_connection_pool(material)
        Apnotic::ConnectionPool.new(
          {cert_path: StringIO.new(material.apns_pem)},
          {size: Passkit.configuration.apns_pool_size}
        ) do |connection|
          # Without a handler net-http2 raises socket errors in its own thread.
          connection.on(:error) { |exception| report_error(exception) }
        end
      end

      def report_error(exception)
        Rails.logger.error "APNs: #{exception.class}: #{exception.message}"
        Passkit.configuration.push_error_handler&.call(exception)
      end

      # True when the push is settled (delivered, device forgotten or rejected for
      # good), false when it is worth retrying. A connection idle for a while can be
      # half open: the push is written, nobody answers, and the socket only errors
      # minutes later. So an idle connection is reopened before use, and a push without
      # answer closes it and goes again once over a new one.
      def push(connection, device, pass_type_identifier)
        reopen_if_idle(connection)
        response = nil
        2.times do
          response = attempt(connection, device, pass_type_identifier)
          break if response
        end
        handle_response(response, device, pass_type_identifier)
      end

      def attempt(connection, device, pass_type_identifier)
        notification = create_notification(device.push_token, pass_type_identifier)
        response = connection.push(notification, timeout: Passkit.configuration.apns_push_timeout)
        mark_used(connection)
        connection.close unless response
        response
      rescue *SOCKET_ERRORS => e
        Rails.logger.warn "APNs: #{e.class}: #{e.message}, reconnecting"
        connection.close
        nil
      end

      def reopen_if_idle(connection)
        idle_after = Passkit.configuration.apns_idle_reconnect_after
        last_use = LAST_USE_MUTEX.synchronize { last_uses[connection] }
        connection.close if idle_after && last_use && monotonic_now - last_use > idle_after
      end

      def mark_used(connection)
        LAST_USE_MUTEX.synchronize { last_uses[connection] = monotonic_now }
      end

      # Weak keys: a connection of a replaced pool takes its entry with it.
      def last_uses
        @last_uses ||= ObjectSpace::WeakMap.new
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def create_notification(push_token, pass_type_identifier)
        notification = Apnotic::Notification.new(push_token)
        notification.topic = pass_type_identifier
        notification.push_type = "background"
        notification.content_available = 1
        notification
      end

      def handle_response(response, device, pass_type_identifier)
        return false unless response

        status = response.status.to_i
        if status == 200
          Rails.logger.info "Push notification sent successfully to token: #{device.push_token}"
          return true
        end
        return false if status == 429 || status >= 500

        reason = response.body.is_a?(Hash) ? response.body["reason"] : response.body
        if status == 410 || INVALID_TOKEN_REASONS.include?(reason)
          forget_device(device)
        else
          report_error(PushError.new(status: response.status, reason: reason, pass_type_identifier: pass_type_identifier))
        end
        true
      end

      # The device unregistered its passes or no longer exists: Apple asks to stop
      # pushing to its token. Its next registration creates it again.
      def forget_device(device)
        Rails.logger.info "APNs: forgetting device #{device.identifier}, its push token is no longer valid"
        Passkit::Registration.where(passkit_device_id: device.id).delete_all
        device.destroy
      end
    end
  end
end
