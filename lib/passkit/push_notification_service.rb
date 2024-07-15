require 'apnotic'

module Passkit
  class PushNotificationService
    def self.notify_pass_update(pass)
      Rails.logger.info "Notifying pass update for pass: #{pass.id}"
      pass.devices.each do |device|
        send_push_notification(device.push_token, pass.pass_type_identifier)
      end
    end

    def self.send_push_notification(push_token, pass_type_identifier)
      connection = create_apnotic_connection
      notification = create_notification(push_token, pass_type_identifier)

      Rails.logger.info "Sending push notification to APNS"
      response = connection.push(notification)
      handle_response(response, push_token)
    ensure
      connection&.close
    end

    private

    def self.create_apnotic_connection
      Apnotic::Connection.new(
        cert_path: Passkit.configuration.private_p12_certificate,
        cert_pass: Passkit.configuration.certificate_key
      )
    end

    def self.create_notification(push_token, pass_type_identifier)
      notification = Apnotic::Notification.new(push_token)
      notification.topic = pass_type_identifier
      notification.push_type = 'background'
      notification.payload = { aps: { 'content-available': 1 } }
      notification
    end

    def self.handle_response(response, push_token)
      if response.success?
        Rails.logger.info "Push notification sent successfully to token: #{push_token}"
      else
        Rails.logger.error "Failed to send push notification to token: #{push_token}. Error: #{response.body}"
      end
    end
  end
end