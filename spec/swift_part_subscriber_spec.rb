#These must be set before the library is required
ENV['TASK_QUEUE_PREFIX'] = 'task-queue-prefix'
require_relative '../swift_part_subscriber'
require 'bunny-mock'
require 'json'

describe SwiftPartSubscriber do
  let(:task_queue_prefix) { 'task-queue-prefix' }
  let(:expected_queue_name) { "#{task_queue_prefix}.multipart.parts"}

  it { expect(described_class).to include(Sneakers::Worker) }
  it { expect(ENV['TASK_QUEUE_PREFIX']).to eq(task_queue_prefix) }
  it { expect(subject.queue.name).to eq(expected_queue_name) }
  it { is_expected.to respond_to(:work) }

  describe '#work' do
    let(:mocked_amqp) { BunnyMock.new }
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
      Sneakers.configure(connection: mocked_amqp)
      Sneakers.logger.level = Logger::ERROR
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
        expect(MetricPublisher).to receive(:new)
          .and_return(mocked_metrics)
      end

      context 'successful report' do
        let(:expected_acknowledgement) { subject.ack! }
        let(:mocked_channel) {
          mocked_amqp.channel
        }

        before do
          expect(migration_manager).to receive(:upload_part)
            .with(part_number)
          expect(migration_manager).to receive(:all_parts_migrated?)
            .and_return(all_parts_are_migrated)
          expect(mocked_metrics).to receive(:publish)
            .with("part_subscriber", "part_migrated", 1)
            .and_return(true)
        end
        context 'all parts migrated' do
          let(:expected_complete_message) {
            message
          }
          let(:expected_complete_queue) { "#{task_queue_prefix}.multipart.complete" }
          let(:all_parts_are_migrated) { true }
          before do
          end
          it {
            expect(subject.queue).to receive(:channel)
              .and_return(mocked_channel)
            expect(mocked_channel.default_exchange).to receive(:publish)
              .with(expected_complete_message, routing_key: expected_complete_queue)
            expect(mocked_metrics).to receive(:publish)
              .with("part_subscriber", "completion_queued", 1)
              .and_return(true)
            expect(expected_acknowledgement).not_to be_nil
            expect(method).to eq expected_acknowledgement
          }
        end

        context 'all parts not yet migrated' do
          let(:all_parts_are_migrated) { false }
          it {
            is_expected.not_to receive(:queue)
            expect(expected_acknowledgement).not_to be_nil
            expect(method).to eq expected_acknowledgement
          }
        end
      end

      context 'exception thrown' do
        let(:expected_acknowledgement) { subject.reject! }
        before do
          expect(migration_manager).to receive(:upload_part)
            .with(part_number)
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
