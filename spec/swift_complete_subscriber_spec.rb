#These must be set before the library is required
ENV['TASK_QUEUE_PREFIX'] = 'task-queue-prefix'
require_relative '../swift_complete_subscriber'
require 'bunny-mock'
require 'json'

describe SwiftCompleteSubscriber do
  let(:task_queue_prefix) { 'task-queue-prefix' }
  let(:expected_queue_name) { "#{task_queue_prefix}.multipart.complete"}

  it { expect(described_class).to include(Sneakers::Worker) }
  it { expect(ENV['TASK_QUEUE_PREFIX']).to eq(task_queue_prefix) }
  it { expect(subject.queue.name).to eq(expected_queue_name) }
  it { is_expected.to respond_to(:work) }

  describe '#work' do
    let(:mocked_metrics) { double(MetricPublisher) }
    let(:container) { SecureRandom.uuid }
    let(:object) { SecureRandom.uuid }
    let(:is_multipart_upload) { true }
    let(:part_number) { 1 }
    let(:message_body) {{
      container: "#{container}",
      object: "#{object}",
      is_multipart_upload: "#{is_multipart_upload}",
      part_number: "#{part_number}"
    }}
    let(:message) { JSON.dump(message_body) }
    let(:migration_manager) { instance_double('SwiftMigrationManager') }
    let(:method) { subject.work(message) }

    before do
      Sneakers.configure(connection: BunnyMock.new)
      Sneakers.logger.level = Logger::ERROR
      expect(MetricPublisher).to receive(:new)
        .and_return(mocked_metrics)
    end

    context 'JSON parse exception' do
      let(:expected_acknowledgement) { subject.reject! }

      before do
        expect(JSON).to receive(:parse).and_raise(JSON::ParserError)
      end
      it {
        expect(expected_acknowledgement).not_to be_nil
        expect(method).to eq expected_acknowledgement
      }
    end

    context 'SwiftMigrationManager construction exception' do
      let(:expected_acknowledgement) { subject.reject! }
      let(:is_multipart_upload) { false }

      before do
        expect(SwiftMigrationManager).to receive(:new).and_raise(SwiftException)
      end
      it {
        expect(expected_acknowledgement).not_to be_nil
        expect(method).to eq expected_acknowledgement
      }
    end

    context 'successful JSON parse and SwiftMigrationManager construction' do
      before do
        expect(SwiftMigrationManager).to receive(:new)
          .with(
            Sneakers.logger,
            container,
            object,
            is_multipart_upload
          ).and_return(migration_manager)
      end

      context 'successful report' do
        let(:expected_acknowledgement) { subject.ack! }

        before do
          expect(migration_manager).to receive(:complete_migration)
          expect(mocked_metrics).to receive(:publish)
            .with("complete_subscriber", "object_migrated", 1)
        end
        it {
          expect(expected_acknowledgement).not_to be_nil
          expect(method).to eq expected_acknowledgement
        }
      end

      context 'exception thrown' do
        let(:expected_acknowledgement) { subject.reject! }
        before do
          expect(migration_manager).to receive(:complete_migration)
            .and_raise(Exception)
            expect(mocked_metrics).not_to receive(:publish)
        end
        it {
          expect(expected_acknowledgement).not_to be_nil
          expect(method).to eq expected_acknowledgement
        }
      end
    end
  end
end
