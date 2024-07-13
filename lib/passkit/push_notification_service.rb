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

        begin
          p12 = OpenSSL::PKCS12.new(File.read(Passkit.configuration.private_p12_certificate), Passkit.configuration.certificate_key)
          http.cert = p12.certificate
          http.key = p12.key
        rescue OpenSSL::PKCS12::PKCS12Error => e
          Passkit.logger.error "Error loading P12 certificate: #{e.message}"
          Passkit.logger.error "Certificate path: #{Passkit.configuration.private_p12_certificate}"
          return nil
        rescue Errno::ENOENT => e
          Passkit.logger.error "Certificate file not found: #{e.message}"
          return nil
        rescue => e
          Passkit.logger.error "Unexpected error loading certificate: #{e.message}"
          Passkit.logger.error "Error backtrace: #{e.backtrace.join("\n")}"
          return nil
        end

        request = Net::HTTP::Post.new(uri.request_uri)
        request['apns-topic'] = pass_type_identifier
        request['apns-push-type'] = 'background'
        
        payload = {
          aps: {
            'content-available': 1
          }
        }

        request.body = payload.to_json

        begin
          response = http.request(request)
          case response
          when Net::HTTPSuccess
            Passkit.logger.info "Push notification sent successfully to token: #{push_token}"
          else
            Passkit.logger.error "Failed to send push notification to token: #{push_token}. Error: #{response.body}"
          end
          response
        rescue => e
          Passkit.logger.error "Error sending push notification: #{e.message}"
          Passkit.logger.error "Error backtrace: #{e.backtrace.join("\n")}"
          nil
        end
      end

      def test_certificate
        p12 = OpenSSL::PKCS12.new(File.read(Passkit.configuration.private_p12_certificate), Passkit.configuration.certificate_key)
        cert = p12.certificate
        
        Passkit.logger.info "Certificate loaded successfully"
        Passkit.logger.info "Certificate subject: #{cert.subject}"
        Passkit.logger.info "Certificate issuer: #{cert.issuer}"
        Passkit.logger.info "Certificate valid from: #{cert.not_before}"
        Passkit.logger.info "Certificate valid to: #{cert.not_after}"
      rescue OpenSSL::PKCS12::PKCS12Error => e
        Passkit.logger.error "Error loading P12 certificate: #{e.message}"
      rescue Errno::ENOENT => e
        Passkit.logger.error "Certificate file not found: #{e.message}"
      rescue => e
        Passkit.logger.error "Unexpected error loading certificate: #{e.message}"
        Passkit.logger.error "Error backtrace: #{e.backtrace.join("\n")}"
      end

      private

      def apple_gateway
        Rails.env.production? ? APPLE_PRODUCTION_GATEWAY : APPLE_DEVELOPMENT_GATEWAY
      end
    end
  end
end