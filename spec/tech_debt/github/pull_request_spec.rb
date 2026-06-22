# frozen_string_literal: true

require "spec_helper"
require "octokit"
require "tech_debt/github/pull_request"

RSpec.describe TechDebt::Github::PullRequest do
  let(:client) { instance_double(Octokit::Client) }

  describe "#ruby_file_index" do
    it "returns unique .rb files and their patches, skipping non-Ruby files" do
      files = [
        double(filename: "app/a.rb", patch: "p1"),
        double(filename: "app/b.js", patch: "p2"),
        double(filename: "app/a.rb", patch: "p1")
      ]
      allow(client).to receive(:pull_request_files).with("acme/app", 1).and_return(files)

      rb, patches = described_class.new(client, "acme/app", 1).ruby_file_index
      expect(rb).to eq(["app/a.rb"])
      expect(patches).to eq({"app/a.rb" => "p1"})
    end
  end

  describe "#linked_issue_numbers" do
    let(:pattern) { /\b(?:fix(?:es)?|close[sd]?|resolve[sd]?)\s*#(\d+)\b/i }

    it "collects, dedups, and sorts references from the PR body and commit messages" do
      allow(client).to receive(:pull_request).with("acme/app", 1).and_return(double(body: "Fixes #4 and closes #2"))
      commit = double(commit: double(message: "resolve #2\nfixes #9"))
      allow(client).to receive(:pull_request_commits).with("acme/app", 1).and_return([commit])

      expect(described_class.new(client, "acme/app", 1).linked_issue_numbers(pattern)).to eq([2, 4, 9])
    end
  end

  describe ".added_lines" do
    it "returns new-file line numbers for added lines only" do
      patch = +""
      patch << "@@ -1,3 +10,4 @@\n"
      patch << " context\n"
      patch << "+added_eleven\n"
      patch << "+added_twelve\n"
      patch << "-removed\n"
      patch << " trailing\n"

      expect(described_class.added_lines(patch).to_a.sort).to eq([11, 12])
    end

    it "tracks line numbers across multiple hunks" do
      patch = +""
      patch << "@@ -1,1 +1,1 @@\n+first\n"
      patch << "@@ -20,2 +30,2 @@\n context\n+thirty_one\n"

      expect(described_class.added_lines(patch).to_a.sort).to eq([1, 31])
    end

    it "ignores the +++ file header" do
      patch = "+++ b/app/models/order.rb\n@@ -1,0 +5,1 @@\n+real_add\n"
      expect(described_class.added_lines(patch).to_a).to eq([5])
    end

    it "returns an empty set for an empty patch" do
      expect(described_class.added_lines("")).to be_empty
    end
  end
end
