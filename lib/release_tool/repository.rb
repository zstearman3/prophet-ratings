# frozen_string_literal: true

require_relative '../release_tool'

module ReleaseTool
  # All release content is pinned to fetched remote commits, independent of the checkout.
  module Repository
    def self.fetch
      ReleaseTool.capture('git', 'fetch', '--no-tags', 'origin', 'main', 'development')
    end

    def self.sha(branch)
      ReleaseTool.capture('git', 'rev-parse', '--verify', "origin/#{branch}^{commit}").strip
    end

    def self.commits(base, target)
      ReleaseTool.capture('git', 'log', '--first-parent', '--reverse', '--format=%H%x09%s', "#{base}..#{target}")
                 .lines.map { |line| line.chomp.split("\t", 2) }
    end

    def self.tags
      local = ReleaseTool.capture('git', 'tag', '--list').lines.map(&:strip)
      (local + remote_tags.keys).uniq
    end

    def self.remote_tags
      ReleaseTool.capture('git', 'ls-remote', '--tags', '--refs', 'origin').lines.to_h do |line|
        object, ref = line.split
        [ref.delete_prefix('refs/tags/'), object]
      end
    end

    def self.validate_tag(plan)
      tag = plan.fetch(:version)
      remote = remote_tags[tag]
      local = ReleaseTool.capture('git', 'for-each-ref', '--format=%(objectname)', "refs/tags/#{tag}").strip
      if !local.empty? && local != remote && local_commit(tag) != plan.fetch(:target)
        raise Error, "Local tag #{tag} differs from origin; resolve it before updating the draft."
      end

      remote
    end

    def self.push_tag(plan)
      tag = plan.fetch(:version)
      create_tag(plan)
      ReleaseTool.capture('git', 'push', 'origin', "--force-with-lease=refs/tags/#{tag}:#{plan[:previous_tag]}",
                          "refs/tags/#{tag}:refs/tags/#{tag}")
    rescue Error => error
      raise Error, "#{error.message}\nDraft #{tag} is retained. Retry with bin/release --update #{tag} after fixing the tag/push error."
    end

    def self.create_tag(plan)
      tag = plan.fetch(:version)
      ReleaseTool.capture('git', 'tag', plan[:update] ? '-af' : '-a', tag, plan.fetch(:target), '-m', "Release #{tag}")
    end

    def self.local_commit(tag)
      ReleaseTool.capture('git', 'rev-parse', '--verify', "#{tag}^{commit}").strip
    end
  end
end
