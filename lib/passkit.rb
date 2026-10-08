# frozen_string_literal: true

require "rails"
require "passkit/engine"

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.setup

module Passkit
  class Error < StandardError; end

  class << self
    attr_accessor :configuration
    attr_writer :logger

    def logger
      @logger ||= Logger.new(STDOUT)
    end
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration) if block_given?
  end

  # Signing material of a pass type identifier, from the app's resolver.
  def self.signing_material_for(pass_type_identifier)
    resolver = configuration.signing_material_resolver
    raise Error, "Configure Passkit.configuration.signing_material_resolver" unless resolver

    resolver.call(pass_type_identifier) ||
      raise(Error, "No signing material for pass type identifier #{pass_type_identifier}")
  end

  class Configuration
    attr_accessor :available_passes,
      :web_service_host,
      :signing_material_resolver,
      :apple_team_identifier,
      :pass_type_identifier,
      :apns_pool_size,
      :push_error_handler

    DEFAULT_AUTHENTICATION = proc do
      authenticate_or_request_with_http_basic("Passkit Dashboard. Login required") do |username, password|
        username == ENV["PASSKIT_DASHBOARD_USERNAME"] && password == ENV["PASSKIT_DASHBOARD_PASSWORD"]
      end
    end
    def authenticate_dashboard_with(&block)
      @authenticate = block if block
      @authenticate || DEFAULT_AUTHENTICATION
    end

    def initialize
      @available_passes = {"Passkit::ExampleStoreCard" => -> {}}
      @web_service_host = ENV["PASSKIT_WEB_SERVICE_HOST"] || (raise "Please set PASSKIT_WEB_SERVICE_HOST")
      raise("PASSKIT_WEB_SERVICE_HOST must start with https://") unless @web_service_host.start_with?("https://")
      # Callable that receives a pass type identifier and returns its Passkit::SigningMaterial.
      # It signs the passes of that identifier and authenticates their APNs pushes.
      @signing_material_resolver = nil
      @apple_team_identifier = ENV["PASSKIT_APPLE_TEAM_IDENTIFIER"] || (raise "Please set PASSKIT_APPLE_TEAM_IDENTIFIER")
      @pass_type_identifier = ENV["PASSKIT_PASS_TYPE_IDENTIFIER"] || (raise "Please set PASSKIT_PASS_TYPE_IDENTIFIER")
      # Persistent APNs connections per process and pass type identifier; size it to the
      # threads that push.
      @apns_pool_size = 5
      # Called with errors raised by an APNs socket (they happen outside the push call).
      @push_error_handler = nil
    end
  end
end

require "passkit/push_notification_service"
