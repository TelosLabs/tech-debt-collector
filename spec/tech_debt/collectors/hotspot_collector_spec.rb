# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tech_debt/config"
require "tech_debt/collectors/hotspot_collector"

RSpec.describe TechDebt::Collectors::HotspotCollector do
  let(:settings) do
    {"enabled" => true, "window_months" => 6, "min_commits" => 5, "min_loc" => 100, "max_files" => 10}
  end
  let(:config) { instance_double(TechDebt::Config, hotspot: settings) }

  subject(:collector) { described_class.new(config, files: files) }

  let(:files) { %w[app/models/order.rb app/models/user.rb app/models/small.rb app/models/rare.rb] }

  # commits-in-window per file (other.rb is churned but out of the configured scope)
  let(:commits) do
    {
      "app/models/order.rb" => 8, "app/models/user.rb" => 6,
      "app/models/small.rb" => 7, "app/models/rare.rb" => 2,
      "app/models/other.rb" => 10
    }
  end
  # line counts per file
  let(:loc) do
    {"app/models/order.rb" => 300, "app/models/user.rb" => 200, "app/models/small.rb" => 50, "app/models/rare.rb" => 400}
  end

  before do
    allow(File).to receive(:file?).and_return(true)
    allow(File).to receive(:readlines) { |path| Array.new(loc.fetch(path, 0), "x\n") }
    git_log = commits.flat_map { |file, count| Array.new(count, file) }.join("\n") + "\n"
    allow(Open3).to receive(:capture3).and_return([git_log, "", double(success?: true)])
  end

  describe "#call" do
    it "flags files that are both high-churn and large" do
      expect(collector.call.map { |c| c[:file] }).to contain_exactly("app/models/order.rb", "app/models/user.rb")
    end

    it "labels them as hotspot candidates scored by churn times size" do
      order = collector.call.find { |c| c[:file] == "app/models/order.rb" }
      expect(order).to include(type: "hotspot", identifier: "app/models/order.rb", score: 2400)
    end

    it "excludes files below the commit threshold" do
      expect(collector.call.map { |c| c[:file] }).not_to include("app/models/rare.rb")
    end

    it "excludes files below the loc threshold" do
      expect(collector.call.map { |c| c[:file] }).not_to include("app/models/small.rb")
    end

    it "excludes churned files outside the analysis scope" do
      expect(collector.call.map { |c| c[:file] }).not_to include("app/models/other.rb")
    end

    it "sorts hotspots by score descending" do
      expect(collector.call.map { |c| c[:file] }).to eq(["app/models/order.rb", "app/models/user.rb"])
    end

    context "with a max_files cap" do
      let(:settings) { super().merge("max_files" => 1) }

      it "returns only the top-scoring hotspots" do
        expect(collector.call.map { |c| c[:file] }).to eq(["app/models/order.rb"])
      end
    end

    context "when disabled" do
      let(:settings) { super().merge("enabled" => false) }

      it "returns nothing without shelling out to git" do
        expect(Open3).not_to receive(:capture3)
        expect(collector.call).to eq([])
      end
    end

    context "when git log fails" do
      before { allow(Open3).to receive(:capture3).and_return(["", "fatal: not a git repository", double(success?: false)]) }

      it "returns nothing" do
        expect(collector.call).to eq([])
      end
    end

    context "when no files are in scope" do
      let(:files) { [] }

      it "returns nothing without shelling out to git" do
        expect(Open3).not_to receive(:capture3)
        expect(collector.call).to eq([])
      end
    end
  end
end
