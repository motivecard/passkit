module Passkit
  class Factory
    class << self
      # generator is an optional ActiveRecord object, the application data for the pass
      def create_pass(pass_class, generator = nil)
        pass = if generator
          Passkit::Pass.find_or_create_by!(
            klass: pass_class.to_s,
            generator_type: generator.class.name,
            generator_id: generator.id
          )
        else
          Passkit::Pass.find_or_create_by!(klass: pass_class.to_s)
        end

        attributes = {
          serial_number: pass.serial_number || SecureRandom.uuid,
          authentication_token: pass.authentication_token || SecureRandom.hex
        }
        # Only the first time: an installed pass never changes identifier.
        if pass.has_attribute?(:pass_type_identifier) && pass[:pass_type_identifier].blank?
          attributes[:pass_type_identifier] = pass.instance.pass_type_identifier
        end
        pass.update!(attributes)

        Passkit::Generator.new(pass).generate_and_sign
      end
    end
  end
end
