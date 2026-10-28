# frozen_string_literal: true

require "rails_helper"
require "minitest/mock"

class TestPushNotificationService < ActiveSupport::TestCase
  FakePass = Struct.new(:devices, :pass_type_identifier)
  FakeDevice = Struct.new(:push_token, :identifier, :id)
  FakeResponse = Struct.new(:status, :body)

  class FakeConnection
    attr_reader :pushed, :push_options, :closes, :error_handler, :options

    # A response per token, or a list consumed in order: nil is a push nobody
    # answered, an exception class is raised by the push.
    def initialize(options = {}, responses = {})
      @options = options
      @responses = responses
      @pushed = []
      @push_options = []
      @closes = 0
    end

    def on(event, &block)
      @error_handler = block if event == :error
    end

    def push(notification, push_options = {})
      @pushed << [notification.token, notification.topic]
      @push_options << push_options
      response = @responses.fetch(notification.token) { FakeResponse.new("200", "") }
      response = response.shift if response.is_a?(Array)
      raise response, "socket" if response.is_a?(Class)
      response
    end

    def close
      @closes += 1
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

  def test_a_push_without_answer_reconnects_and_goes_again
    connection = FakeConnection.new({}, {"a" => [nil, FakeResponse.new("200", "")]})
    failed = nil
    reported = with_error_handler do
      Apnotic::Connection.stub(:new, ->(*) { connection }) do
        failed = Passkit::PushNotificationService.notify_pass_update(pass_with("a"))
      end
    end

    assert_empty failed
    assert_empty reported
    assert_equal %w[a a], connection.pushed.map(&:first)
    assert_equal 1, connection.closes
    assert_equal [10, 10], connection.push_options.map { |options| options[:timeout] }
  end

  def test_a_socket_error_reconnects_and_goes_again
    connection = FakeConnection.new({}, {"a" => [Errno::ETIMEDOUT, FakeResponse.new("200", "")]})
    failed = Apnotic::Connection.stub(:new, ->(*) { connection }) do
      Passkit::PushNotificationService.notify_pass_update(pass_with("a"))
    end

    assert_empty failed
    assert_equal 1, connection.closes
  end

  def test_returns_the_devices_still_unanswered_after_reconnecting
    connection = FakeConnection.new({}, {"a" => [nil, nil]})
    pass = pass_with("a", "b")
    failed = nil
    reported = with_error_handler do
      Apnotic::Connection.stub(:new, ->(*) { connection }) do
        failed = Passkit::PushNotificationService.notify_pass_update(pass)
      end
    end

    assert_equal ["a"], failed.map(&:push_token)
    assert_empty reported
    assert_equal %w[a a b], connection.pushed.map(&:first)
  end

  def test_throttled_and_server_errors_are_returned_without_reporting
    connection = FakeConnection.new({}, {"a" => FakeResponse.new("429", {"reason" => "TooManyRequests"}),
                                         "b" => FakeResponse.new("503", {"reason" => "ServiceUnavailable"})})
    failed = nil
    reported = with_error_handler do
      Apnotic::Connection.stub(:new, ->(*) { connection }) do
        failed = Passkit::PushNotificationService.notify_pass_update(pass_with("a", "b"))
      end
    end

    assert_equal %w[a b], failed.map(&:push_token)
    assert_empty reported
    assert_equal 0, connection.closes
  end

  def test_an_idle_connection_is_reopened_before_use
    connection = FakeConnection.new
    with_config(apns_idle_reconnect_after: 0) do
      Apnotic::Connection.stub(:new, ->(*) { connection }) do
        Passkit::PushNotificationService.notify_pass_update(pass_with("a"))
        Passkit::PushNotificationService.notify_pass_update(pass_with("b"))
      end
    end

    assert_equal 1, connection.closes
    assert_equal %w[a b], connection.pushed.map(&:first)
  end

  def test_a_recently_used_connection_is_kept
    connection = FakeConnection.new
    Apnotic::Connection.stub(:new, ->(*) { connection }) do
      Passkit::PushNotificationService.notify_pass_update(pass_with("a"))
      Passkit::PushNotificationService.notify_pass_update(pass_with("b"))
    end

    assert_equal 0, connection.closes
  end

  def test_pushes_only_to_the_given_devices
    pass = Passkit::Pass.create!(klass: "Passkit::ExampleStoreCard")
    first = Passkit::Device.create!(identifier: "first", push_token: "first-token")
    second = Passkit::Device.create!(identifier: "second", push_token: "second-token")
    pass.registrations.create!(device: first)
    pass.registrations.create!(device: second)
    connection = FakeConnection.new

    Apnotic::Connection.stub(:new, ->(*) { connection }) do
      Passkit::PushNotificationService.notify_pass_update(pass, devices: [second])
    end

    assert_equal ["second-token"], connection.pushed.map(&:first)
  end

  def test_destroying_a_pass_deletes_its_registrations
    pass = Passkit::Pass.create!(klass: "Passkit::ExampleStoreCard")
    pass.registrations.create!(device: Passkit::Device.create!(identifier: "phone", push_token: "token"))

    pass.destroy

    assert_equal 0, Passkit::Registration.where(passkit_pass_id: pass.id).count
  end

  private

  def with_config(**settings)
    previous = settings.keys.to_h { |key| [key, Passkit.configuration.public_send(key)] }
    settings.each { |key, value| Passkit.configuration.public_send("#{key}=", value) }
    yield
  ensure
    previous.each { |key, value| Passkit.configuration.public_send("#{key}=", value) }
  end

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
