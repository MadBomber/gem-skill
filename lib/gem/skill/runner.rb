# frozen_string_literal: true

require "time"

module Gem::Skill
  # Core install logic shared by gem_command and bundle_command.
  # Callers are responsible for spinner.auto_spin and title setup before calling.
  module Runner
    # error:        nil on success, message string on failure
    # verify_fixed: true when --verify ran and corrected the skill
    # change_count: number of itemized corrections (0 when none/not run)
    Result = Data.define(:error, :verify_fixed, :change_count) do
      def ok? = error.nil?

      def self.failure(message) = new(error: message, verify_fixed: false, change_count: 0)
      def self.success(verify_fixed: false, change_count: 0)
        new(error: nil, verify_fixed: verify_fixed, change_count: change_count)
      end
    end

    # Generate + cache + link one skill, optionally verifying it against source.
    # Returns a Runner::Result.
    def self.install_skill(gem_name, version, spinner, force:, model:, verify: false)
      if Cache.cached?(gem_name, version) && !force
        Linker.link(gem_name, version)
        content = Cache.read(gem_name, version)
        return finalize(gem_name, version, content, spinner, model: model, verify: verify, status: "already cached")
      end

      content = Generator.new(gem_name, version, model: model).generate(force: force)
      Linker.link(gem_name, version)
      finalize(gem_name, version, content, spinner, model: model, verify: verify, status: "done")
    rescue => e
      spinner.error("failed")
      Result.failure(e.message)
    end

    # Run the optional verify pass and settle the spinner + metadata.
    def self.finalize(gem_name, version, content, spinner, model:, verify:, status:)
      unless verify
        spinner.success(status)
        return Result.success
      end

      result = Verifier.new(gem_name, version, model: model).verify(content)

      unless result.verifiable
        Cache.merge_metadata(gem_name, version, verification: {
          verified:         false,
          verified_at:      Time.now.iso8601,
          model:            model,
          used_source_code: false,
          skipped_reason:   "no installed source available"
        })
        spinner.success("#{status} (no source to verify)")
        return Result.success
      end

      Cache.write_skill(gem_name, version, result.content) if result.changed?
      Cache.merge_metadata(gem_name, version, verification: verification_metadata(result))

      if result.changed?
        n = result.changes.size
        spinner.success(n.positive? ? "verified — fixed #{n}" : "verified — fixed")
        Result.success(verify_fixed: true, change_count: n)
      else
        spinner.success("verified — ok")
        Result.success
      end
    rescue => e
      spinner.error("verify failed")
      Result.failure(e.message)
    end
    private_class_method :finalize

    # Records that real source code was consulted, which files, and the
    # structured (issue-ready) corrections that resulted.
    def self.verification_metadata(result)
      {
        verified:         true,
        verified_at:      Time.now.iso8601,
        model:            result.model,
        used_source_code: true,
        source:           source_provenance(result.source),
        fixed:            result.changed?,
        change_count:     result.changes.size,
        changes:          result.changes
      }
    end
    private_class_method :verification_metadata

    def self.source_provenance(manifest)
      return {} unless manifest

      files = Array(manifest[:files])
      { files: files, file_count: files.size, chars: manifest[:chars], truncated: manifest[:truncated] }
    end
    private_class_method :source_provenance
  end
end
