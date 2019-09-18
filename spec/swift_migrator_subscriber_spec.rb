#These must be set before the library is required
ENV['TASK_QUEUE_PREFIX'] = 'task-queue-prefix'
ENV['TASK_UPLOAD_TYPE'] = 'single'
require_relative '../swift_migrator_subscriber'
require 'bunny-mock'
require 'json'

describe SwiftMigratorSubscriber do
  let(:task_queue_prefix) { 'task-queue-prefix' }
  let(:task_upload_type) { 'single' }
  let(:expected_queue_name) { "#{task_queue_prefix}.#{task_upload_type}"}

  it { expect(described_class).to include(Sneakers::Worker) }
  it { expect(ENV['TASK_QUEUE_PREFIX']).to eq(task_queue_prefix) }
  it { expect(ENV['TASK_UPLOAD_TYPE']).to eq(task_upload_type) }
  it { expect(subject.queue.name).to eq(expected_queue_name) }
  it { is_expected.to respond_to(:work) }

  describe '#work' do
    let(:container) { SecureRandom.uuid }
    let(:object) { SecureRandom.uuid }
    let(:message_body) {{
      container: "#{container}",
      object: "#{object}",
      is_multipart_upload: "#{is_multipart_upload}"
    }}
    let(:message) { JSON.dump(message_body) }
    let(:migration_manager) { instance_double('SwiftMigrationManager') }
    let(:method) { subject.work(message) }

    before do
      Sneakers.configure(connection: BunnyMock.new)
      Sneakers.logger.level = Logger::ERROR
    end

    context 'JSON parse exception' do
      let(:expected_acknowledgement) { subject.reject! }
      let(:is_multipart_upload) { false }

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

      context 'single file upload' do
        let(:is_multipart_upload) { false }
        let(:expected_migration_method) { :migrate_object }

        before do
          expect(migration_manager).to receive(expected_migration_method) { migration_method_response }
        end
        context 'successful report' do
          let(:expected_acknowledgement) { subject.ack! }
          let(:migration_method_response) { nil }
          it {
            expect(expected_acknowledgement).not_to be_nil
            expect(method).to eq expected_acknowledgement
          }
        end

        context 'reporter exception thrown' do
          let(:expected_error) { MigrationException }
          let(:expected_acknowledgement) { subject.reject! }
          let(:migration_method_response) { raise(expected_error) }
          it {
            expect(expected_acknowledgement).not_to be_nil
            expect(method).to eq expected_acknowledgement
          }
        end
      end

      context 'multipart upload' do
        let(:is_multipart_upload) { true }

        context 'successful report' do
          let(:expected_acknowledgement) { subject.ack! }
          let(:expected_part_number) { 1 }
          let(:expected_part_message) {
            JSON.dump(
              message_body.merge({"part_number": expected_part_number})
            )
          }
          let(:expected_part_queue) { "#{task_queue_prefix}.#{task_upload_type}.parts" }
          before do
            expect(migration_manager).to receive(:process_manifest)
              .and_yield(expected_part_number-1)
          end
          it {
            is_expected.to receive(:publish)
              .with(expected_part_message, routing_key: expected_part_queue)
            expect(expected_acknowledgement).not_to be_nil
            expect(method).to eq expected_acknowledgement
          }
        end

        context 'reporter exception thrown' do
          let(:expected_acknowledgement) { subject.reject! }
          before do
            expect(migration_manager).to receive(:process_manifest)
              .and_raise(Exception)
          end
          it {
            expect(expected_acknowledgement).not_to be_nil
            expect(method).to eq expected_acknowledgement
          }
        end
      end
    end
  end
end
