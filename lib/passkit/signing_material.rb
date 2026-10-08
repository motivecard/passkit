# frozen_string_literal: true

require "openssl"

module Passkit
  # The certificate, its private key and the Apple WWDR intermediate that issued it.
  # Apple only accepts a pass signed with a certificate of its own passTypeIdentifier,
  # and the update pushes of that pass authenticate with the same certificate, so the
  # app resolves one of these per identifier (see Configuration#signing_material_resolver).
  class SigningMaterial
    attr_reader :certificate, :key, :intermediate_certificate

    def self.from_pem(certificate:, key:, intermediate_certificate:)
      new(
        certificate: OpenSSL::X509::Certificate.new(certificate),
        key: OpenSSL::PKey.read(key),
        intermediate_certificate: OpenSSL::X509::Certificate.new(intermediate_certificate)
      )
    end

    def self.from_p12(p12, password, intermediate_certificate:)
      pkcs12 = OpenSSL::PKCS12.new(p12, password)
      new(
        certificate: pkcs12.certificate,
        key: pkcs12.key,
        intermediate_certificate: OpenSSL::X509::Certificate.new(intermediate_certificate)
      )
    end

    def initialize(certificate:, key:, intermediate_certificate:)
      raise ArgumentError, "the private key does not belong to the certificate" unless certificate.check_private_key(key)

      @certificate = certificate
      @key = key
      @intermediate_certificate = intermediate_certificate
    end

    # SHA-256 of the certificate: tells a renewed certificate apart from the one it replaces.
    def fingerprint
      @fingerprint ||= OpenSSL::Digest::SHA256.hexdigest(certificate.to_der)
    end

    def sign(data)
      OpenSSL::PKCS7.sign(certificate, key, data, [intermediate_certificate],
        OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY)
    end

    # Certificate and key in one PEM, what Apnotic reads for certificate-based APNs.
    def apns_pem
      certificate.to_pem + key.private_to_pem
    end
  end
end
