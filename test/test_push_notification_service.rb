# frozen_string_literal: true

require "rails_helper"
require "minitest/mock"

class TestPushNotificationService < ActiveSupport::TestCase
  FakePass = Struct.new(:devices, :pass_type_identifier)
  FakeDevice = Struct.new(:push_token)
  FakeResponse = Struct.new(:status, :body)

  class FakeConnection
    attr_reader :pushed, :error_handler

    def initialize
      @pushed = []
    end

    def on(event, &block)
      @error_handler = block if event == :error
    end

    def push(notification)
      @pushed << notification.token
      FakeResponse.new("200", "")
    end

    def close
    end
  end

  setup { Passkit::PushNotificationService.reset_connection_pool! }
  teardown { Passkit::PushNotificationService.reset_connection_pool! }

  def pass_with(*tokens)
    FakePass.new(tokens.map { |token| FakeDevice.new(token) }, "pass.com.example.pass")
  end

  def test_reuses_the_connection_across_passes
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
    assert_equal %w[a b c], connection.pushed
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
    reported = []
    previous = Passkit.configuration.push_error_handler
    Passkit.configuration.push_error_handler = ->(error) { reported << error }

    Apnotic::Connection.stub(:new, ->(*) { connection }) do
      Passkit::PushNotificationService.notify_pass_update(pass_with("a"))
    end
    error = SocketError.new("connection reset")
    connection.error_handler.call(error)

    assert_equal [error], reported
  ensure
    Passkit.configuration.push_error_handler = previous
  end
end
