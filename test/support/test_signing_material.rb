# frozen_string_literal: true

require "openssl"

# A throwaway chain (fake WWDR root + pass certificate) so signing and pushing run
# for real in tests, without an Apple certificate.
module TestSigningMaterial
  def self.root_key
    @root_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def self.root_certificate
    @root_certificate ||= begin
      cert = build_certificate("/CN=Test WWDR", root_key, root_key)
      cert.issuer = cert.subject
      extensions = OpenSSL::X509::ExtensionFactory.new(cert, cert)
      cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
      cert.add_extension(extensions.create_extension("keyUsage", "keyCertSign,cRLSign", true))
      cert.sign(root_key, OpenSSL::Digest.new("SHA256"))
      cert
    end
  end

  def self.for(pass_type_identifier)
    @materials ||= {}
    @materials[pass_type_identifier] ||= begin
      key = OpenSSL::PKey::RSA.new(2048)
      cert = build_certificate("/UID=#{pass_type_identifier}/CN=Pass Type ID: #{pass_type_identifier}", key, root_key)
      cert.issuer = root_certificate.subject
      cert.sign(root_key, OpenSSL::Digest.new("SHA256"))
      Passkit::SigningMaterial.new(certificate: cert, key: key, intermediate_certificate: root_certificate)
    end
  end

  def self.build_certificate(subject, key, _signing_key)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = OpenSSL::BN.rand(64)
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert
  end
end
