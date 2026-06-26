# frozen_string_literal: true

require "yaml"

module TechDebt
  class Config
    REQUIRED_KEYS = %w[version llm analysis github].freeze

    SUMMARY_PATH = "tmp/wall_e_report.json"
    DEFAULT_FLOG_THRESHOLD = 25
    DEFAULT_FLAY_THRESHOLD = 25
    HOTSPOT_DEFAULTS = {
      "enabled" => true,
      "window_months" => 6,
      "min_commits" => 5,
      "min_loc" => 100,
      "max_files" => 10
    }.freeze

    attr_reader :raw

    def self.load(path)
      raw = YAML.safe_load(File.read(path), aliases: true) || {}
      new(raw)
    end

    def initialize(raw)
      @raw = raw
      validate!
    end

    def llm
      raw.fetch("llm")
    end

    def analysis
      raw.fetch("analysis")
    end

    def github
      raw.fetch("github")
    end

    def reporting
      { "generate_summary" => true, "summary_path" => SUMMARY_PATH }
    end

    def flog_threshold
      analysis.fetch("flog_threshold", DEFAULT_FLOG_THRESHOLD).to_f
    end

    def flay_threshold
      analysis.fetch("flay_threshold", DEFAULT_FLAY_THRESHOLD).to_i
    end

    def hotspot
      custom = analysis["hotspot"]
      HOTSPOT_DEFAULTS.merge(custom.is_a?(Hash) ? custom : {})
    end

    def auto_assign
      value = raw["auto_assign"]
      return { "enabled" => false } unless value.is_a?(Hash)

      { "enabled" => false }.merge(value)
    end

    def verification
      value = raw["verification"]
      return {} unless value.is_a?(Hash)

      value
    end

    def close_issues_on_verification_pass?
      verification.fetch("close_on_pass", false)
    end

    private

    def validate!
      missing = REQUIRED_KEYS.reject { |key| raw.key?(key) }
      return if missing.empty?

      raise ArgumentError, "Missing config keys: #{missing.join(', ')}"
    end
  end
end
