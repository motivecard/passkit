# frozen_string_literal: true

require "rails_helper"

class TestRegistrationsController < ActionDispatch::IntegrationTest
  include Passkit::Engine.routes.url_helpers

  setup do
    @routes = Passkit::Engine.routes
  end

  def test_create
    Passkit::Factory.create_pass(Passkit::ExampleStoreCard)
    Passkit::Factory.create_pass(Passkit::ExampleStoreCard)
    pass1 = Passkit::Pass.first
    pass2 = Passkit::Pass.last

    assert_equal 2, Passkit::Pass.count

    register_pass(pass1)
    assert_equal 1, pass1.devices.count

    register_pass(pass2)
    assert_equal 1, pass2.devices.count
  end

  def test_show_returns_a_tag_that_does_not_list_the_same_pass_again
    pass = create_registered_pass(updated_at: Time.zone.parse("2026-10-05 00:11:50.654321"))

    get device_registrations_path(device_id: "device-1", pass_type_id: pass.pass_type_identifier)
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal [pass.serial_number], body["serialNumbers"]
    assert_equal "2026-10-05T00:11:50.654321", body["lastUpdated"][0, 26]

    get device_registrations_path(device_id: "device-1", pass_type_id: pass.pass_type_identifier),
      params: {passesUpdatedSince: body["lastUpdated"]}
    assert_response :no_content
  end

  # Devices keep the second-precision tags handed out before the fix: the pass still
  # counts as updated once, and the answer carries the new tag.
  def test_show_accepts_a_second_precision_tag
    pass = create_registered_pass(updated_at: Time.zone.parse("2026-10-05 00:11:50.654321"))

    get device_registrations_path(device_id: "device-1", pass_type_id: pass.pass_type_identifier),
      params: {passesUpdatedSince: "2026-10-05T00:11:50Z"}
    assert_response :ok
    assert_equal "2026-10-05T00:11:50.654321", JSON.parse(response.body)["lastUpdated"][0, 26]
  end

  def test_destroy
    Passkit::Factory.create_pass(Passkit::ExampleStoreCard)
    pass = Passkit::Pass.first
    register_pass(pass)
    destroy_registration(pass.registrations.first)
    assert_equal 0, pass.devices.count
    assert_equal 0, Passkit::Registration.count
    assert_equal 1, Passkit::Pass.count
    assert_equal 1, Passkit::Device.count
  end

  private

  def create_registered_pass(updated_at:)
    pass = Passkit::Pass.create!(klass: "Passkit::ExampleStoreCard", serial_number: SecureRandom.uuid,
      authentication_token: SecureRandom.hex)
    device = Passkit::Device.create!(identifier: "device-1", push_token: "token")
    pass.registrations.create!(device: device)
    pass.update_columns(updated_at: updated_at)
    pass
  end

  def register_pass(pass)
    post device_register_path(device_id: 1, pass_type_id: pass.pass_type_identifier, serial_number: pass.serial_number),
      params: {pushToken: "1234567890"}.to_json,
      headers: {"Authorization" => "ApplePass #{pass.authentication_token}"}
  end

  def destroy_registration(registration)
    delete device_unregister_path(device_id: registration.device.id,
      pass_type_id: registration.pass.pass_type_identifier,
      serial_number: registration.pass.serial_number),
      params: {}.to_json,
      headers: {"Authorization" => "ApplePass #{registration.pass.authentication_token}"}
  end
end
