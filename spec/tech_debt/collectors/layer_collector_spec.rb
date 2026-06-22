# frozen_string_literal: true

require "spec_helper"
require "tech_debt/config"
require "tech_debt/collectors/layer_collector"

RSpec.describe TechDebt::Collectors::LayerCollector do
  let(:config) { instance_double(TechDebt::Config, analysis: {"paths" => [], "exclude_paths" => []}) }

  subject(:collector) { described_class.new(config, files: []) }

  # These exercise the line-number extraction directly; #model_file?/#job_file?
  # gating is covered by the collector's own path filtering.
  describe "line extraction" do
    it "reports the line of a Current.* reference" do
      content = "class Order\n  def total\n    Current.user.id\n  end\nend\n"
      result = collector.send(:current_attribute_violations, "app/models/order.rb", content).first
      expect(result).to include(type: "leaked_business_logic", identifier: "Order", line: 3, end_line: 3)
    end

    it "reports the line of an anemic perform" do
      content = "class SyncJob\n  def perform(id)\n    Model.sync(id)\n  end\nend\n"
      result = collector.send(:anemic_job_signals, "app/jobs/sync_job.rb", content).first
      expect(result).to include(identifier: "SyncJob#perform", line: 2, end_line: 2)
    end

    it "falls back to line 1 when the pattern is absent" do
      expect(collector.send(:line_of, "class Order\nend\n", /nope/)).to eq(1)
    end
  end
end
