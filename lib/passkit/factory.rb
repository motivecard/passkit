module Passkit
  class Factory
    class << self
      # generator is an optional ActiveRecord object, the application data for the pass
      def create_pass(pass_class, generator = nil)
        pass = if generator
                Passkit::Pass.find_or_create_by!(
                  klass: pass_class,
                  generator_type: generator.class.name,
                  generator_id: generator.id
                )
              else
                Passkit::Pass.find_or_create_by!(klass: pass_class)
              end

        # Actualiza los datos del pase si es necesario
        pass.update!(
          serial_number: pass.serial_number || SecureRandom.uuid,
          authentication_token: pass.authentication_token || SecureRandom.hex
        )

        Passkit::Generator.new(pass).generate_and_sign
      end

      def update_pass(pass)
        generator = pass.generator
        pass.update!(
          serial_number: pass.serial_number || SecureRandom.uuid,
          authentication_token: pass.authentication_token || SecureRandom.hex,
          data: (pass.data || {}).merge(generate_pass_data(generator)),
          updated_at: Time.current # Forzar actualización del timestamp
        )
        Passkit::Generator.new(pass).generate_and_sign
      end

      private

      def generate_pass_data(generator)
        {
          balance: generator.balance,
          visit_tracker: generator.visit_tracker,
        }
      end
    end
  end
end