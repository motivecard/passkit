# frozen_string_literal: true

require "rails_helper"
require "minitest/mock"

class TestPushNotificationService < ActiveSupport::TestCase
  FakePass = Struct.new(:devices, :pass_type_identifier)
  FakeDevice = Struct.new(:push_token, :identifier, :id)
  FakeResponse = Struct.new(:status, :body)

  class FakeConnection
    attr_reader :pushed, :error_handler, :options

    def initialize(options = {}, responses = {})
      @options = options
      @responses = responses
      @pushed = []
    end

    def on(event, &block)
      @error_handler = block if event == :error
    end

    def push(notification)
      @pushed << [notification.token, notification.topic]
      @responses.fetch(notification.token) { FakeResponse.new("200", "") }
    end

    def close
    end
  end

  setup { Passkit::PushNotificationService.reset_connection_pool! }
  teardown { Passkit::PushNotificationService.reset_connection_pool! }

  def pass_with(*tokens, identifier: "pass.com.example.pass")
    FakePass.new(tokens.map { |token| FakeDevice.new(token, "device-#{token}") }, identifier)
  end

  def test_reuses_the_connection_across_passes_of_the_same_identifier
    connection = FakeConnection.new
    opened = 0
    Apnotic::Connection.stub(:new, ->(*) {
      opened += 1
      connection
    }) do
      Passkit::PushNotificationService.notify_pass_update(pass_with("a", "b"))
      Passkit::PushNotificationService.notify_pass_update(pass_with("c"))
    end

    assert_equal 1, opened
    assert_equal %w[a b c], connection.pushed.map(&:first)
  end

  def test_each_identifier_pushes_with_its_own_certificate_and_topic
    connections = []
    Apnotic::Connection.stub(:new, ->(options) { FakeConnection.new(options).tap { |c| connections << c } }) do
      Passkit::PushNotificationService.notify_pass_update(pass_with("a", identifier: "pass.com.example.one"))
      Passkit::PushNotificationService.notify_pass_update(pass_with("b", identifier: "pass.com.example.two"))
    end

    assert_equal 2, connections.size
    assert_equal [["a", "pass.com.example.one"]], connections.first.pushed
    assert_equal [["b", "pass.com.example.two"]], connections.last.pushed
    pems = connections.map { |c| c.options[:cert_path].read }
    assert_includes pems.first, TestSigningMaterial.for("pass.com.example.one").certificate.to_pem
    assert_includes pems.last, TestSigningMaterial.for("pass.com.example.two").certificate.to_pem
  end

  def test_a_renewed_certificate_replaces_the_pool
    identifier = "pass.com.example.renewed"
    old_material = TestSigningMaterial.for(identifier)
    new_material = TestSigningMaterial.for("pass.com.example.renewed-next")
    current = old_material
    previous = Passkit.configuration.signing_material_resolver
    Passkit.configuration.signing_material_resolver = ->(_identifier) { current }
    opened = 0

    Apnotic::Connection.stub(:new, ->(*) {
      opened += 1
      FakeConnection.new
    }) do
      Passkit::PushNotificationService.notify_pass_update(pass_with("a", identifier: identifier))
      Passkit::PushNotificationService.notify_pass_update(pass_with("b", identifier: identifier))
      current = new_material
      Passkit::PushNotificationService.notify_pass_update(pass_with("c", identifier: identifier))
    end

    assert_equal 2, opened
  ensure
    Passkit.configuration.signing_material_resolver = previous
  end

  def test_skips_devices_without_token_and_does_not_connect_without_tokens
    opened = 0
    Apnotic::Connection.stub(:new, ->(*) {
      opened += 1
      FakeConnection.new
    }) do
      Passkit::PushNotificationService.notify_pass_update(pass_with(nil, ""))
    end

    assert_equal 0, opened
  end

  def test_socket_errors_go_to_the_configured_handler
    connection = FakeConnection.new
    reported = with_error_handler do
      Apnotic::Connection.stub(:new, ->(*) { connection }) do
        Passkit::PushNotificationService.notify_pass_update(pass_with("a"))
      end
      connection.error_handler.call(SocketError.new("connection reset"))
    end

    assert_equal ["SocketError"], reported.map { |error| error.class.name }
  end

  def test_a_rejected_push_is_reported
    connection = FakeConnection.new({}, {"a" => FakeResponse.new("403", {"reason" => "InvalidProviderToken"})})
    reported = with_error_handler do
      Apnotic::Connection.stub(:new, ->(*) { connection }) do
        Passkit::PushNotificationService.notify_pass_update(pass_with("a"))
      end
    end

    assert_equal 1, reported.size
    assert_kind_of Passkit::PushError, reported.first
    assert_equal ["403", "InvalidProviderToken"], [reported.first.status, reported.first.reason]
  end

  def test_an_unregistered_token_forgets_the_device
    pass = Passkit::Pass.create!(klass: "Passkit::ExampleStoreCard")
    gone = Passkit::Device.create!(identifier: "gone", push_token: "gone-token")
    alive = Passkit::Device.create!(identifier: "alive", push_token: "alive-token")
    pass.registrations.create!(device: gone)
    pass.registrations.create!(device: alive)
    connection = FakeConnection.new({}, {"gone-token" => FakeResponse.new("410", {"reason" => "Unregistered"})})

    reported = with_error_handler do
      Apnotic::Connection.stub(:new, ->(*) { connection }) do
        Passkit::PushNotificationService.notify_pass_update(pass)
      end
    end

    assert_empty reported
    assert_equal ["alive"], pass.reload.devices.pluck(:identifier)
    refute Passkit::Device.exists?(identifier: "gone")
  end

  private

  def with_error_handler
    reported = []
    previous = Passkit.configuration.push_error_handler
    Passkit.configuration.push_error_handler = ->(error) { reported << error }
    yield
    reported
  ensure
    Passkit.configuration.push_error_handler = previous
  end
end
