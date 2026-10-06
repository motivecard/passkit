module Passkit
  module Api
    module V1
      class PassesController < ActionController::API
        before_action :decrypt_payload, only: :create

        def create
          set_generator

          if @generator && @payload[:collection_name].present?
            files = @generator.public_send(@payload[:collection_name]).collect do |collection_item|
              Passkit::Factory.create_pass(@payload[:pass_class], collection_item)
            end
            file = Passkit::Generator.compress_passes_files(files)
            send_pass(file, "application/vnd.apple.pkpasses", also_delete: files)
          else
            file = Passkit::Factory.create_pass(@payload[:pass_class], @generator)
            send_pass(file, "application/vnd.apple.pkpass")
          end
        end

        # @return If request is authorized, returns HTTP status 200 with a payload of the pass data.
        # @return If the request is not authorized, returns HTTP status 401.
        # @return Otherwise, returns the appropriate standard HTTP status.
        def show
          authentication_token = request.headers["Authorization"]&.split(" ")&.last
          unless authentication_token.present?
            render json: {}, status: :unauthorized
            return
          end

          pass = Pass.find_by(serial_number: params[:serial_number], authentication_token: authentication_token)
          unless pass
            render json: {}, status: :unauthorized
            return
          end

          if stale?(last_modified: pass.last_update, etag: pass.cache_key_with_version)
            send_pass(Passkit::Generator.new(pass).generate_and_sign, "application/vnd.apple.pkpass")
          end
        end

        private

        # send_file would stream the temp file after the action returns, so it could
        # never be deleted: every request left a .pkpass and its build folder in
        # tmp/passkit. The pass is ~1 MB, read it and delete it right away.
        def send_pass(path, type, also_delete: [])
          send_data File.binread(path), type: type, disposition: "attachment", filename: File.basename(path)
        ensure
          [path, *also_delete].each { |file| Passkit::Generator.cleanup(file) }
        end

        def decrypt_payload
          @payload = Passkit::UrlEncrypt.decrypt(params[:payload])
          if DateTime.parse(@payload[:valid_until]).past?
            head :not_found
          end
        end

        def set_generator
          @generator = nil

          return unless @payload[:generator_class].present? && @payload[:generator_id].present?

          generator_class = @payload[:generator_class].constantize
          @generator = generator_class.find(@payload[:generator_id])
        end
      end
    end
  end
end
