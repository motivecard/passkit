module Passkit
  class PassUpdater
    def self.update_pass(pass, attributes)
      pass.update!(attributes)
      new_pass_file = Passkit::Generator.new(pass).generate_and_sign
      Passkit::PushNotificationService.notify_pass_update(pass)
      new_pass_file
    end
  end
end