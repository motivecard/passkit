module Passkit
  module Api
    module V1
      class RegistrationsController < ActionController::API
        before_action :load_pass, only: %i[create destroy]
        before_action :load_device, only: %i[show]

        def create
          if @pass.devices.exists?(identifier: params[:device_id])
            render json: {}, status: :ok
          else
            register_device
            render json: {}, status: :created
          end
        end

        def show
          if @device.nil?
            render json: {}, status: :not_found
            return
          end

          passes = fetch_registered_passes
          if passes.none?
            render json: {}, status: :no_content
          else
            render json: updatable_passes(passes)
          end
        end

        def destroy
          @pass.registrations.where(passkit_device_id: params[:device_id]).delete_all
          render json: {}, status: :ok
        end

        private

        def load_pass
          auth_header = request.headers["Authorization"]
          unless auth_header.present?
            render json: {}, status: :unauthorized
            return
          end

          auth_type, token = auth_header.split(' ', 2)
          case auth_type
          when 'ApplePass'
            @pass = Pass.find_by(serial_number: params[:serial_number], authentication_token: token)
          when 'AndroidPass'
            # Implementar lógica de autenticación para Android si es necesario
          else
            render json: {}, status: :unauthorized
            return
          end

          render json: {}, status: :unauthorized unless @pass
        end

        def load_device
          @device = Passkit::Device.find_by(identifier: params[:device_id])
        end

        def register_device
          device = Passkit::Device.find_or_create_by!(identifier: params[:device_id]) do |d|
            d.push_token = push_token
          end
          @pass.registrations.create!(device: device)
        end

        def fetch_registered_passes
          passes = @device.passes
          if params[:passesUpdatedSince].present?
            passes = passes.where('updated_at > ?', Time.zone.parse(params[:passesUpdatedSince]))
          end
          passes
        end

        def updatable_passes(passes)
          {
            lastUpdated: passes.maximum(:updated_at).iso8601,
            serialNumbers: passes.pluck(:serial_number)
          }
        end

        def push_token
          return unless request&.body

          request.body.rewind
          JSON.parse(request.body.read)["pushToken"]
        end
      end
    end
  end
end