require 'apnotic'

module Passkit
  class PushNotificationService
    class << self
      def notify_pass_update(pass)
        Rails.logger.info "Notifying pass update for pass: #{pass.id}"
        connection = create_connection
        pass.devices.each do |device|
          send_push_notification(connection, device.push_token, pass.pass_type_identifier)
        end
      ensure
        connection&.close
      end

      private

      def create_connection
        Apnotic::Connection.new(
          cert_path: Passkit.configuration.private_p12_certificate,
          cert_pass: Passkit.configuration.certificate_key
        )
      end

      def send_push_notification(connection, push_token, pass_type_identifier)
        notification = create_notification(push_token, pass_type_identifier)
        
        Rails.logger.info "Sending push notification to APNS"
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