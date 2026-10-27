# frozen_string_literal: true

require "rails_helper"

class TestPassesController < ActionDispatch::IntegrationTest
  include Passkit::Engine.routes.url_helpers

  setup do
    @routes = Passkit::Engine.routes
  end

  def test_create
    payload = Passkit::PayloadGenerator.encrypted(Passkit::ExampleStoreCard)
    get passes_api_path(payload)
    assert_equal 1, Passkit::Pass.count
    assert_response :success
    zip_file = Zip::File.open_buffer(StringIO.new(response.body))
    assert_equal 7, zip_file.size
  end

  def test_create_without_additional_pass_data_keeps_a_single_style
    pass_json = pass_json_for(Passkit::ExampleStoreCard)
    assert pass_json.key?("storeCard")
    refute pass_json.key?("posterGeneric")
  end

  def test_create_with_additional_pass_data_adds_the_style_next_to_pass_type
    pass_json = pass_json_for(Passkit::ExamplePosterCard)
    assert_equal ["headerFields", "primaryFields", "secondaryFields", "auxiliaryFields", "backFields"], pass_json["storeCard"].keys
    assert_equal "Alessandro", pass_json.dig("posterGeneric", "primaryFields", 0, "value")
    assert_equal "Gold", pass_json.dig("posterGeneric", "footerFields", 0, "value")
  end

  def test_create_collection
    user = User.create!(name: "Ticket holder")
    2.times { |i| user.tickets.create!(name: "Ticket #{i}") }
    payload = Passkit::PayloadGenerator.encrypted(Passkit::UserTicket, user, :tickets)
    get passes_api_path(payload)
    assert_response :success
    assert_equal 2, Passkit::Pass.count
    unzipped_passes = Zip::File.open_buffer(StringIO.new(response.body))
    assert_equal 2, unzipped_passes.size # the main zip file contains two passes
    unzipped_pass =  Zip::File.open_buffer(unzipped_passes.first.zipfile)
    assert_includes unzipped_passes.first.name, '.pkpass'
  end

  def test_create_signs_the_manifest_with_the_material_of_the_pass_type_identifier
    get passes_api_path(Passkit::PayloadGenerator.encrypted(Passkit::ExampleStoreCard))
    assert_response :success
    zip_file = Zip::File.open_buffer(StringIO.new(response.body))
    signature = OpenSSL::PKCS7.new(zip_file.read("signature"))

    store = OpenSSL::X509::Store.new
    store.add_cert(TestSigningMaterial.root_certificate)
    assert signature.verify([], store, zip_file.read("manifest.json"), OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY)
    material = TestSigningMaterial.for(Passkit::Pass.last.pass_type_identifier)
    assert_equal material.certificate.to_der, signature.certificates.find { |c| c.subject == material.certificate.subject }.to_der
  end

  def test_create_stores_the_pass_type_identifier_the_pass_was_issued_with
    Passkit::Factory.create_pass(Passkit::ExampleStoreCard)
    pass = Passkit::Pass.last
    assert_equal ENV["PASSKIT_PASS_TYPE_IDENTIFIER"], pass[:pass_type_identifier]

    # An installed pass keeps its identifier even if the pass class changes its mind.
    pass.update_columns(pass_type_identifier: "pass.com.example.old")
    Passkit::Factory.create_pass(Passkit::ExampleStoreCard)
    assert_equal "pass.com.example.old", pass.reload.pass_type_identifier
  end

  def test_show
    _pkpass = Passkit::Factory.create_pass(Passkit::ExampleStoreCard)
    assert_equal 1, Passkit::Pass.count
    pass = Passkit::Pass.last
    get pass_path(pass_type_id: ENV["PASSKIT_PASS_TYPE_IDENTIFIER"], serial_number: pass.serial_number)
    assert_response :unauthorized

    get pass_path(pass_type_id: ENV["PASSKIT_PASS_TYPE_IDENTIFIER"], serial_number: pass.serial_number),
      headers: {"Authorization" => "ApplePass #{pass.authentication_token}"}

    assert_response :success

    get pass_path(pass_type_id: ENV["PASSKIT_PASS_TYPE_IDENTIFIER"], serial_number: pass.serial_number),
      headers: {"Authorization" => "ApplePass #{pass.authentication_token}", "If-Modified-Since" => Time.zone.now.httpdate}

    assert_equal "", response.body
    assert_equal pass.last_update.httpdate, response.headers["Last-Modified"]
    assert_response :not_modified
  end

  private

  def pass_json_for(pass_class)
    get passes_api_path(Passkit::PayloadGenerator.encrypted(pass_class))
    assert_response :success
    zip_file = Zip::File.open_buffer(StringIO.new(response.body))
    JSON.parse(zip_file.read("pass.json"))
  end
end
