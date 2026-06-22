# frozen_string_literal: true

require "spec_helper"
require "tech_debt/config"
require "tech_debt/delta/pr_delta"

RSpec.describe TechDebt::Delta::PrDelta do
  let(:pr_delta_settings) { {"enabled" => true, "fail_on" => "none", "debt_types" => []} }

  let(:config) do
    instance_double(
      TechDebt::Config,
      github: {"repo" => "acme/app"},
      pr_delta: pr_delta_settings,
      flog_threshold: 25.0,
      flay_threshold: 25
    )
  end

  let(:client) { instance_double(Octokit::Client) }
  let(:pull_request) { instance_double(TechDebt::Github::PullRequest) }

  let(:changed_files) { ["app/models/order.rb"] }
  # Added lines 10, 11, 12 in order.rb
  let(:patches) { {"app/models/order.rb" => "@@ -1,1 +10,3 @@\n+a\n+b\n+c\n"} }

  subject(:delta) { described_class.new(config, pr_number: 42, dry_run: true) }

  before do
    allow(TechDebt::Github::Client).to receive(:build).and_return(client)
    allow(TechDebt::Github::PullRequest).to receive(:new).and_return(pull_request)
    allow(pull_request).to receive(:ruby_file_index).and_return([changed_files, patches])

    stub_collector(TechDebt::Collectors::DebrideCollector, in_range_candidate)
    stub_collector(TechDebt::Collectors::ComplexityCollector, out_of_range_candidate)
    stub_collector(TechDebt::Collectors::FlayCollector, [])
    stub_collector(TechDebt::Collectors::LayerCollector, [])
  end

  def stub_collector(klass, results)
    instance = instance_double(klass.to_s, call: results)
    allow(klass).to receive(:new).and_return(instance)
  end

  let(:in_range_candidate) do
    [{file: "app/models/order.rb", identifier: "Order#dead", type: "dead_code",
      detail: "uncalled", score: 1, line: 11, end_line: 11}]
  end

  let(:out_of_range_candidate) do
    [{file: "app/models/order.rb", identifier: "Order#big", type: "high_complexity",
      detail: "complex", score: 80, line: 50, end_line: 60}]
  end

  describe "#run" do
    it "keeps only findings on changed lines" do
      summary = delta.run
      expect(summary["finding_count"]).to eq(1)
      expect(summary["findings"].map { |f| f[:type] }).to eq(["dead_code"])
    end

    it "keeps a multi-line finding when its range overlaps a changed line" do
      out_of_range_candidate[0][:line] = 8
      out_of_range_candidate[0][:end_line] = 11
      expect(delta.run["finding_count"]).to eq(2)
    end

    it "reports the changed Ruby file count" do
      expect(delta.run["changed_ruby_files"]).to eq(1)
    end

    context "when no Ruby files changed" do
      let(:changed_files) { [] }

      it "skips collection and reports zero findings" do
        expect(TechDebt::Collectors::DebrideCollector).not_to receive(:new)
        expect(delta.run["finding_count"]).to eq(0)
      end
    end

    context "with a debt_types filter" do
      let(:pr_delta_settings) { {"enabled" => true, "fail_on" => "none", "debt_types" => ["high_complexity"]} }

      it "drops findings whose type is not allowed" do
        expect(delta.run["finding_count"]).to eq(0)
      end
    end

    describe "gating status" do
      it "passes when fail_on is none" do
        expect(delta.run["status"]).to eq("pass")
      end

      context "when fail_on is any" do
        let(:pr_delta_settings) { {"enabled" => true, "fail_on" => "any", "debt_types" => []} }

        it "fails because a finding exists" do
          expect(delta.run["status"]).to eq("fail")
        end
      end

      context "when fail_on is high" do
        let(:pr_delta_settings) { {"enabled" => true, "fail_on" => "high", "debt_types" => []} }

        it "passes when the only finding is low severity" do
          expect(delta.run["status"]).to eq("pass")
        end
      end
    end
  end
end
