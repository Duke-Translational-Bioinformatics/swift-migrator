ENV['TASK_QUEUE_PREFIX'] = 'task-queue-prefix'
require_relative '../swift_migrator_publisher'
require 'bunny-mock'
require 'json'

describe SwiftMigratorPublisher do
  let(:mocked_bunny) { BunnyMock.new }
  let(:task_queue_prefix) { 'task-queue-prefix' }

  subject {
    SwiftMigratorPublisher.new mocked_bunny
  }

  it { is_expected.to respond_to(:publish_object).with(3).argument }
  it { is_expected.to respond_to(:publish_objects_from).with(1).argument }

  describe '#publish_object' do
    let(:container_to_publish) { 'container-to-publish' }
    let(:object_to_publish) { 'object-to-publish' }
    let(:expected_message) {
      JSON.dump({
        container: container_to_publish,
        object: object_to_publish,
        is_multipart_upload: is_multipart_upload
      })
    }

    context 'is_multipart_upload false' do
      let(:is_multipart_upload) { "false" }
      let(:task_queue) {
        subject.channel.queue("#{ENV['TASK_QUEUE_PREFIX']}.single", durable: true)
      }

      it 'should publish the container, object, and is_multipart_upload as json to the single task queue' do
        expect(task_queue).to be
        # the bunny-mock default exchange is a standard BunnyMock::Exchange::Direct
        # so a BunnyMock::Queue has to be manually bound to that exchange
        # before running the test
        task_queue.bind subject.exchange, routing_key: task_queue.name
        subject.publish_object container_to_publish, object_to_publish, is_multipart_upload
        expect(task_queue.message_count).to eq(1)
        payload = task_queue.all.first
        expect(payload[:message]).to eq(expected_message)
      end
    end

    context 'is_multipart_upload true' do
      let(:is_multipart_upload) { "true" }
      let(:task_queue) {
        subject.channel.queue("#{ENV['TASK_QUEUE_PREFIX']}.multipart", durable: true)
      }

      it 'should publish the container, object, and is_multipart_upload as json to the multipart task queue' do
        expect(task_queue).to be
        # the bunny-mock default exchange is a standard BunnyMock::Exchange::Direct
        # so a BunnyMock::Queue has to be manually bound to that exchange
        # before running the test
        task_queue.bind subject.exchange, routing_key: task_queue.name
        subject.publish_object container_to_publish, object_to_publish, is_multipart_upload
        expect(task_queue.message_count).to eq(1)
        payload = task_queue.all.first
        expect(payload[:message]).to eq(expected_message)
      end
    end
  end

  describe '#publish_objects_from' do
    let(:object_inputs) { [
        'container-1,id-1,true',
        'container-2,id-2,false'
    ] }
    let(:io_to_publish) {
      io = StringIO.new("")
      object_inputs.each do |object_input|
        io.puts object_input
      end
      io.rewind
      io
    }

    before do
      object_inputs.each do |object_input|
        this_container, this_object, this_is_multipart_upload = object_input.split(',')
        is_expected.to receive(:publish_object)
          .with(this_container, this_object, this_is_multipart_upload)
      end
    end
    it 'should publish all input' do
      subject.publish_objects_from io_to_publish
    end
  end
end
