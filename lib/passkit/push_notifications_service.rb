require 'net/http'
require 'uri'
require 'json'
require 'openssl'

module Passkit
  class PushNotificationService
    APPLE_PRODUCTION_GATEWAY = "https://api.push.apple.com"
    APPLE_DEVELOPMENT_GATEWAY = "https://api.sandbox.push.apple.com"

    class << self
      def notify_pass_update(pass)
        pass.devices.each do |device|
          send_push_notification(device.push_token, pass.pass_type_identifier)
        end
      end

      def send_push_notification(push_token, pass_type_identifier)
        uri = URI.parse("#{apple_gateway}/3/device/#{push_token}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER

        # Cargar el certificado
        http.cert = OpenSSL::X509::Certificate.new(File.read(Passkit.configuration.apn_certificate_path))
        http.key = OpenSSL::PKey::RSA.new(File.read(Passkit.configuration.apn_certificate_path), Passkit.configuration.apn_certificate_passphrase)

        request = Net::HTTP::Post.new(uri.request_uri)
        request['apns-topic'] = pass_type_identifier
        request['apns-push-type'] = 'alert'

        # Payload de la notificación
        payload = {
          aps: {
            alert: 'Your pass has been updated!',
            'content-available': 1
          },
          passTypeIdentifier: pass_type_identifier
        }

        request.body = payload.to_json

        response = http.request(request)

        case response
        when Net::HTTPSuccess
          Rails.logger.info "Push notification sent successfully to token: #{push_token}"
        else
          Rails.logger.error "Failed to send push notification to token: #{push_token}. Error: #{response.body}"
        end

        response
      rescue => e
        Rails.logger.error "Error sending push notification: #{e.message}"
        nil
      end

      private

      def apple_gateway
        Passkit.configuration.apn_environment == 'production' ? APPLE_PRODUCTION_GATEWAY : APPLE_DEVELOPMENT_GATEWAY
      end
    end
  end
end