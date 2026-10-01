# frozen_string_literal: true

require "rails_helper"

class TestGeneratorCleanup < ActiveSupport::TestCase
  def test_deletes_the_pkpass_and_its_build_folder
    Dir.mktmpdir do |dir|
      build = File.join(dir, "abc")
      FileUtils.mkdir_p(build)
      File.write(File.join(build, "pass.json"), "{}")
      pkpass = "#{build}.pkpass"
      File.write(pkpass, "zip")

      Passkit::Generator.cleanup(pkpass)

      refute File.exist?(pkpass)
      refute Dir.exist?(build)
    end
  end

  def test_ignores_a_missing_path
    assert_nil Passkit::Generator.cleanup(nil)
  end
end
