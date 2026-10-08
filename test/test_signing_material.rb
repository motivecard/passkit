# frozen_string_literal: true

require "rails_helper"

class TestSigningMaterialClass < ActiveSupport::TestCase
  def material
    ::TestSigningMaterial.for("pass.com.example.material")
  end

  def test_round_trips_through_pem
    copy = Passkit::SigningMaterial.from_pem(
      certificate: material.certificate.to_pem,
      key: material.key.private_to_pem,
      intermediate_certificate: material.intermediate_certificate.to_pem
    )
    assert_equal material.fingerprint, copy.fingerprint
  end

  def test_rejects_a_key_of_another_certificate
    assert_raises(ArgumentError) do
      Passkit::SigningMaterial.new(certificate: material.certificate, key: OpenSSL::PKey::RSA.new(2048),
        intermediate_certificate: material.intermediate_certificate)
    end
  end

  def test_signature_verifies_against_the_intermediate
    signature = material.sign("manifest")
    store = OpenSSL::X509::Store.new
    store.add_cert(::TestSigningMaterial.root_certificate)
    assert signature.verify([], store, "manifest", OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY)
  end

  def test_apns_pem_is_what_apnotic_reads_for_a_certificate_connection
    connection = Apnotic::Connection.new(cert_path: StringIO.new(material.apns_pem))
    context = connection.send(:ssl_context)
    assert_equal material.certificate.to_der, context.cert.to_der
    assert context.cert.check_private_key(context.key)
  end

  def test_signing_material_for_needs_a_resolver
    previous = Passkit.configuration.signing_material_resolver
    Passkit.configuration.signing_material_resolver = nil
    assert_raises(Passkit::Error) { Passkit.signing_material_for("pass.com.example.material") }
  ensure
    Passkit.configuration.signing_material_resolver = previous
  end
end
