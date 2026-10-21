# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Each committed capture checkpoints a conservative interrupted ledger before returning.
    class DatabaseCaptureStore
      def initialize(run)
        @run = run
      end

      def capture(body:, metadata:)
        reference = metadata.merge('id' => SecureRandom.uuid, 'sha256' => Digest::SHA256.hexdigest(body), 'bytes' => body.bytesize)
        @run.with_lock { persist_capture(body, reference) }
        reference
      end

      def checkpoint(ledger, metadata)
        @run.update!(manifest: metadata.merge('acquisition' => ledger, 'finalized' => true))
      end

      def manifest(result)
        identifier = "cbbd-review:#{@run.id}"
        @run.normalized_replay = result.merge('manifest' => identifier)
        @run.evidence_digest = @run.evidence_hash
        @run.save!
        identifier
      end

      def read(reference)
        capture = @run.captures.find_by!(capture_id: reference.fetch('id'))
        body = capture.body
        unless capture.metadata == reference && Digest::SHA256.hexdigest(body) == reference.fetch('sha256')
          raise CaptureStore::IntegrityError, 'Capture digest mismatch'
        end

        body
      end

      def self.append_capture(ledger, reference)
        captures = ledger.fetch('captures')
        captures << reference
        ledger.merge!('attempts' => captures.size, 'latest_quota_headers' => reference['headers'])
      end

      private

      def persist_capture(body, reference)
        raise ArgumentError, 'Acquisition already finalized' if @run.evidence_digest

        @run.captures.create!(capture_id: reference.fetch('id'), body:, metadata: reference)
        update_ledger(reference)
        @run.save!
      end

      def update_ledger(reference)
        self.class.append_capture(@run.manifest.fetch('acquisition'), reference)
      end
    end
  end
end
