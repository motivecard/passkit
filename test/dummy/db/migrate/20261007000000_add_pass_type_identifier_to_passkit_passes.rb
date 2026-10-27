class AddPassTypeIdentifierToPasskitPasses < ActiveRecord::Migration[7.1]
  def change
    add_column :passkit_passes, :pass_type_identifier, :string
  end
end
