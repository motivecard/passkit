require_relative "../../../support/test_signing_material"

Passkit.configure do |config|
  config.available_passes['Passkit::UserStoreCard'] = -> { User.create!(name: "ExampleName") }
  config.signing_material_resolver = ->(pass_type_identifier) { TestSigningMaterial.for(pass_type_identifier) }
end
