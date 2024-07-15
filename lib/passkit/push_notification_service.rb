require 'apnotic'

module Passkit
  class PushNotificationService
    class << self
      def notify_pass_update(pass)
        Rails.logger.info "Notifying pass update for pass: #{pass.id}"
        connection = create_connection
        changes = get_pass_changes(pass)
        pass.devices.each do |device|
          send_push_notification(connection, device.push_token, pass.pass_type_identifier, changes)
        end
      ensure
        connection&.close
      end

      private

      def get_pass_changes(pass)
        # Implementa la lógica para determinar qué ha cambiado en el pase
        # Esto podría implicar comparar con una versión anterior o simplemente
        # recopilar los campos que se han actualizado recientemente
        changes = {}
        changes[:balance] = pass.balance if pass.saved_change_to_balance?
        changes[:expiration_date] = pass.expiration_date if pass.saved_change_to_expiration_date?
        # Añade más campos según sea necesario
        changes
      end

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

      def send_push_notification(connection, push_token, pass_type_identifier, changes)
        notification = create_notification(push_token, pass_type_identifier, changes)
        
        Rails.logger.info "Sending push notification to APNS for token: #{push_token}"
        response = connection.push(notification)
        
        handle_response(response, push_token)
      end

      def create_notification(push_token, pass_type_identifier, changes)
        notification = Apnotic::Notification.new(push_token)
        notification.topic = pass_type_identifier
        notification.push_type = 'alert'
        
        # Crear un mensaje basado en los cambios
        message = create_change_message(changes)
        
        notification.alert = {
          title: "Actualización de tu pase",
          body: message
        }
        
        # Mantén content_available para que el dispositivo sepa que debe actualizar el pase
        notification.content_available = 1
        
        notification
      end
      
      def create_change_message(changes)
        # Personaliza este método según tus necesidades
        messages = []
        changes.each do |key, value|
          case key
          when :balance
            messages << "Tu saldo ha sido actualizado a #{value}"
          when :expiration_date
            messages << "La fecha de expiración ha cambiado a #{value}"
          # Añade más casos según sea necesario
          end
        end
        
        messages.join(". ")
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