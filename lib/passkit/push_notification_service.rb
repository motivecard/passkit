require 'apnotic'

module Passkit
  class PushNotificationService
    POOL_MUTEX = Mutex.new

    class << self
      def notify_pass_update(pass)
        push_tokens = pass.devices.filter_map { |device| device.push_token.presence }
        return if push_tokens.empty?

        connection_pool.with do |connection|
          push_tokens.each do |push_token|
            send_push_notification(connection, push_token, pass.pass_type_identifier)
          end
        end
      end

      # Apple recommends keeping APNs connections open instead of opening one per
      # notification: a new HTTP/2 + TLS handshake with the pass certificate cost
      # ~300 ms per push. The pool lives per process and is created lazily, so it
      # is built after Puma forks. A dropped socket reconnects on the next push.
      def connection_pool
        @connection_pool || POOL_MUTEX.synchronize { @connection_pool ||= build_connection_pool }
      end

      # Closes the pooled connections, e.g. after rotating the certificate.
      def reset_connection_pool!
        pool = POOL_MUTEX.synchronize { @connection_pool.tap { @connection_pool = nil } }
        pool&.shutdown(&:close)
      end

      private

      def build_connection_pool
        Apnotic::ConnectionPool.new(
          {cert_path: Passkit.configuration.private_p12_certificate, cert_pass: Passkit.configuration.certificate_key},
          {size: Passkit.configuration.apns_pool_size}
        ) do |connection|
          # Without a handler net-http2 raises socket errors in its own thread.
          connection.on(:error) { |exception| handle_connection_error(exception) }
        end
      end

      def handle_connection_error(exception)
        Rails.logger.error "APNs connection error: #{exception.class}: #{exception.message}"
        Passkit.configuration.push_error_handler&.call(exception)
      end

      def send_push_notification(connection, push_token, pass_type_identifier)
        notification = create_notification(push_token, pass_type_identifier)

        response = connection.push(notification)

        handle_response(response, push_token)
      end

      def create_notification(push_token, pass_type_identifier)
        notification = Apnotic::Notification.new(push_token)
        notification.topic = pass_type_identifier
        notification.push_type = 'background'
        notification.content_available = 1
        notification
      end

      def handle_response(response, push_token)
        if response
          if response.status == '200'
            Rails.logger.info "Push notification sent successfully to token: #{push_token}"
          else
            Rails.logger.error "Failed to send push notification to token: #{push_token}. Status: #{response.status}, Body: #{response.body}"
          end
        else
          Rails.logger.error "Timeout sending push notification to token: #{push_token}"
        end
      end
    end
  end
end
