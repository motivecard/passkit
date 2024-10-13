module Passkit
  class Factory
    class << self
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

        pass.update!(
          serial_number: pass.serial_number || SecureRandom.uuid,
          authentication_token: pass.authentication_token || SecureRandom.hex
        )

        Passkit::Generator.new(pass).generate_and_sign
      end

      def update_pass(pass)
        generator = pass.generator
        pass_data = generate_pass_data(generator)
        pass.update!(
          data: pass_data,
          last_updated: Time.current
        )
        Passkit::Generator.new(pass).generate_and_sign
      end

      private

      def generate_pass_data(generator)
        {
          balance: generator.balance,
          visit_tracker: generator.visit_tracker,
          lastUpdated: Time.current.iso8601
        }
      end
    end
  end
end