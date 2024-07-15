require 'apnotic'

module Passkit
  class PushNotificationService
    class << self
      def notify_pass_update(pass)
        Rails.logger.info "Notifying pass update for pass: #{pass.id}"
        connection = create_connection
        pass.devices.each do |device|
          if device.push_token.present?
            send_push_notification(connection, device.push_token, pass.pass_type_identifier)
          else
            Rails.logger.warn "Device #{device.id} for pass #{pass.id} has no push token"
          end
        end
      rescue => e
        Rails.logger.error "Error in notify_pass_update: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      ensure
        connection&.close
      end

      private

      def create_connection
        Rails.logger.info "Creating APNS connection with cert: #{Passkit.configuration.private_p12_certificate}"
        Apnotic::Connection.new(
          cert_path: Passkit.configuration.private_p12_certificate,
          cert_pass: Passkit.configuration.certificate_key
        )
      rescue => e
        Rails.logger.error "Failed to create APNS connection: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise
      end

      def send_push_notification(connection, push_token, pass_type_identifier)
        notification = create_notification(push_token, pass_type_identifier)
        
        Rails.logger.info "Sending push notification to APNS for token: #{push_token}"
        response = connection.push(notification)
        
        handle_response(response, push_token)
      rescue => e
        Rails.logger.error "Error sending push notification: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise
      end

      def create_notification(push_token, pass_type_identifier)
        notification = Apnotic::Notification.new(push_token)
        notification.topic = pass_type_identifier
        notification.push_type = 'alert'  # Cambia a 'alert' si quieres una notificación visible
        notification.alert = {
          title: "Actualización de pase",
          body: "Tu pase ha sido actualizado. Abre Wallet para ver los cambios."
        }
        notification.content_available = 1
        Rails.logger.info "Created notification: #{notification.inspect}"
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