# frozen_string_literal: true

require "spec_helper"
require "octokit"
require "tech_debt/github/comment_upserter"

RSpec.describe TechDebt::Github::CommentUpserter do
  let(:client) { instance_double(Octokit::Client) }
  let(:marker) { "<!-- m -->" }

  subject(:upserter) { described_class.new(client: client, repo: "acme/app", pr_number: 42) }

  describe "#upsert" do
    it "updates the existing comment that contains the marker" do
      existing = double(id: 7, body: "old body\n<!-- m -->")
      noise = double(id: 1, body: "unrelated comment")
      allow(client).to receive(:issue_comments).with("acme/app", 42).and_return([noise, existing])

      expect(client).to receive(:update_comment).with("acme/app", 7, "new body")
      expect(client).not_to receive(:add_comment)
      upserter.upsert("new body", marker: marker)
    end

    it "creates a new comment when none contain the marker" do
      allow(client).to receive(:issue_comments).with("acme/app", 42).and_return([double(id: 1, body: "noise")])

      expect(client).to receive(:add_comment).with("acme/app", 42, "new body")
      expect(client).not_to receive(:update_comment)
      upserter.upsert("new body", marker: marker)
    end

    it "creates a new comment when there are no comments" do
      allow(client).to receive(:issue_comments).and_return([])

      expect(client).to receive(:add_comment).with("acme/app", 42, "body")
      upserter.upsert("body", marker: marker)
    end
  end
end
