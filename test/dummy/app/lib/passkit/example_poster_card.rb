module Passkit
  class ExamplePosterCard < ExampleStoreCard
    def pass_path
      ExampleStoreCard.new.pass_path
    end

    def additional_pass_data
      {
        posterGeneric: {
          headerFields: [{key: "balance", label: "Balance", value: 100}],
          primaryFields: [{key: "name", value: "Alessandro"}],
          footerFields: [{key: "level", value: "Gold"}]
        }
      }
    end
  end
end
