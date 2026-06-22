# frozen_string_literal: true

require "spec_helper"
require "tech_debt/config"
require "tech_debt/collectors/debride_collector"

RSpec.describe TechDebt::Collectors::DebrideCollector do
  let(:config) { instance_double(TechDebt::Config, analysis: {"paths" => [], "exclude_paths" => []}) }

  subject(:collector) { described_class.new(config, files: ["app/models/user.rb"]) }

  before { allow(File).to receive(:file?).and_return(true) }

  describe "#call" do
    it "extracts the line number and mirrors it to end_line" do
      output = "app/models/user.rb:42 User#unused is not called from anywhere\n"
      allow(Open3).to receive(:capture3).and_return([output, "", double(success?: true, exitstatus: 0)])

      expect(collector.call.first).to include(
        file: "app/models/user.rb", identifier: "User#unused",
        type: "dead_code", line: 42, end_line: 42
      )
    end

    it "skips lines that don't match the debride format" do
      allow(Open3).to receive(:capture3).and_return(["nothing useful here\n", "", double(success?: true, exitstatus: 0)])
      expect(collector.call).to eq([])
    end

    it "returns an empty array without running debride when there are no targets" do
      expect(Open3).not_to receive(:capture3)
      expect(described_class.new(config, files: []).call).to eq([])
    end
  end
end
