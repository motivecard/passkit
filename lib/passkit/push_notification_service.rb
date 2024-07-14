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
        Rails.logger.info "Notifying pass update for pass: #{pass.id}"
        pass.devices.each do |device|
          send_push_notification(device.push_token, pass.pass_type_identifier)
        end
      end

      def send_push_notification(push_token, pass_type_identifier)
        retries = 3
        begin
          Rails.logger.info "Initiating push notification to token: #{push_token}"
          uri = URI.parse("#{apple_gateway}/3/device/#{push_token}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.open_timeout = 60
          http.read_timeout = 60
      
          load_certificate(http)
      
          request = create_request(uri, pass_type_identifier)
      
          Rails.logger.info "Sending request to APNS"
          response = http.request(request)
          Rails.logger.info "Received response from APNS: #{response.code} #{response.message}"
      
          handle_response(response, push_token)
        rescue EOFError => e
          Rails.logger.error "EOFError encountered: #{e.message}"
          retries -= 1
          if retries > 0
            Rails.logger.info "Retrying push notification. Attempts left: #{retries}"
            sleep 1
            retry
          else
            Rails.logger.error "Failed to send push notification after 3 attempts"
            raise
          end
        rescue => e
          Rails.logger.error "Unexpected error sending push notification: #{e.class} - #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          nil
        end
      end

      def test_certificate
        Rails.logger.info "Testing certificate..."
        p12 = OpenSSL::PKCS12.new(File.read(Passkit.configuration.private_p12_certificate), Passkit.configuration.certificate_key)
        cert = p12.certificate
        
        Rails.logger.info "Certificate loaded successfully"
        Rails.logger.info "Certificate subject: #{cert.subject}"
        Rails.logger.info "Certificate issuer: #{cert.issuer}"
        Rails.logger.info "Certificate valid from: #{cert.not_before}"
        Rails.logger.info "Certificate valid to: #{cert.not_after}"
      rescue OpenSSL::PKCS12::PKCS12Error => e
        Rails.logger.error "Error loading P12 certificate: #{e.message}"
      rescue Errno::ENOENT => e
        Rails.logger.error "Certificate file not found: #{e.message}"
      rescue => e
        Rails.logger.error "Unexpected error loading certificate: #{e.message}"
        Rails.logger.error "Error backtrace: #{e.backtrace.join("\n")}"
      end

      private

      def apple_gateway
        APPLE_PRODUCTION_GATEWAY
      end

      def load_certificate(http)
        p12 = OpenSSL::PKCS12.new(File.read(Passkit.configuration.private_p12_certificate), Passkit.configuration.certificate_key)
        http.cert = p12.certificate
        http.key = p12.key
        Rails.logger.info "Certificate loaded successfully"
      rescue OpenSSL::PKCS12::PKCS12Error => e
        raise "Error loading P12 certificate: #{e.message}"
      rescue Errno::ENOENT => e
        raise "Certificate file not found: #{e.message}"
      rescue => e
        raise "Unexpected error loading certificate: #{e.message}"
      end

      def create_request(uri, pass_type_identifier)
        request = Net::HTTP::Post.new(uri.request_uri)
        request['apns-topic'] = pass_type_identifier
        request['apns-push-type'] = 'background'
        
        payload = {
          aps: {
            'content-available': 1
          }
        }

        request.body = payload.to_json
        request
      end

      def handle_response(response, push_token)
        Rails.logger.info "Push notification response: #{response.code} #{response.message}"
        Rails.logger.info "Response body: #{response.body}"

        case response
        when Net::HTTPSuccess
          Rails.logger.info "Push notification sent successfully to token: #{push_token}"
        else
          Rails.logger.error "Failed to send push notification to token: #{push_token}. Status: #{response.code}, Body: #{response.body}"
        end
        response
      end
    end
  end
end