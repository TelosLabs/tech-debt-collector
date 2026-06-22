# frozen_string_literal: true

require "spec_helper"
require "tech_debt/config"
require "tech_debt/collectors/complexity_collector"

RSpec.describe TechDebt::Collectors::ComplexityCollector do
  let(:config) { instance_double(TechDebt::Config, analysis: {"paths" => [], "exclude_paths" => []}, flog_threshold: 25.0) }

  subject(:collector) { described_class.new(config, files: ["app/models/user.rb"]) }

  before { allow(File).to receive(:file?).and_return(true) }

  def stub_flog(line)
    allow(Open3).to receive(:capture3).and_return([line, "", double(success?: true, exitstatus: 0)])
  end

  describe "#call" do
    it "parses a line range into line/end_line" do
      stub_flog("    40.0: User#big app/models/user.rb:12-29\n")
      expect(collector.call.first).to include(
        file: "app/models/user.rb", identifier: "User#big",
        type: "high_complexity", line: 12, end_line: 29
      )
    end

    it "sets end_line equal to line when no range is present" do
      stub_flog("    40.0: User#m app/models/user.rb:12\n")
      candidate = collector.call.first
      expect([candidate[:line], candidate[:end_line]]).to eq([12, 12])
    end

    it "drops methods below the flog threshold" do
      stub_flog("    10.0: User#small app/models/user.rb:5\n")
      expect(collector.call).to eq([])
    end

    it "ignores the main#none summary row" do
      stub_flog("    99.0: main#none app/models/user.rb:1\n")
      expect(collector.call).to eq([])
    end
  end
end
