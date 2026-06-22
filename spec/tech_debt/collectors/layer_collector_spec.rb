# frozen_string_literal: true

require "spec_helper"
require "tech_debt/config"
require "tech_debt/collectors/layer_collector"

RSpec.describe TechDebt::Collectors::LayerCollector do
  let(:config) { instance_double(TechDebt::Config, analysis: {"paths" => [], "exclude_paths" => []}) }

  before { allow(File).to receive(:file?).and_return(true) }

  def collect(file, content)
    allow(File).to receive(:read).with(file).and_return(content)
    described_class.new(config, files: [file]).call
  end

  describe "#call" do
    it "flags a Current.* reference in a model at relative path and reports its line" do
      content = "class Order\n  def total\n    Current.user.id\n  end\nend\n"
      expect(collect("app/models/order.rb", content).first).to include(
        type: "leaked_business_logic", identifier: "Order", line: 3, end_line: 3
      )
    end

    it "flags an anemic perform in a job at relative path and reports its line" do
      content = "class SyncJob\n  def perform(id)\n    Model.sync(id)\n  end\nend\n"
      expect(collect("app/jobs/sync_job.rb", content).first).to include(
        identifier: "SyncJob#perform", line: 2, end_line: 2
      )
    end

    it "also matches nested engine paths" do
      content = "class Order\n  def total\n    Current.user.id\n  end\nend\n"
      expect(collect("engines/billing/app/models/order.rb", content)).not_to be_empty
    end

    it "does not treat a non-app/models path as a model file" do
      content = "class Order\n  Current.user\nend\n"
      expect(collect("lib/myapp/models/order.rb", content)).to eq([])
    end

    it "returns nothing for a model without a Current.* reference" do
      expect(collect("app/models/order.rb", "class Order\nend\n")).to eq([])
    end
  end

  describe "#line_of" do
    it "falls back to line 1 when the pattern is absent" do
      collector = described_class.new(config, files: [])
      expect(collector.send(:line_of, "class Order\nend\n", /nope/)).to eq(1)
    end
  end
end
