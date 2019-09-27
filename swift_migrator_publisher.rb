#!/usr/local/bin/ruby

class SwiftMigratorPublisher
  require "bunny"
  require 'json'
  require_relative 'metric_publisher'

  attr_accessor :connection, :channel, :exchange
  def initialize(connection=nil)
    if connection
      @connection = connection
    end
    connect
    @metrics = MetricPublisher.new
  end

  def publish_object(container, object, is_multipart_upload)
    job_type = ''
    if is_multipart_upload.to_s == "true"
      job_type = 'multipart'
    else
      job_type = "single"
    end
    queue_name = "#{ENV['TASK_QUEUE_PREFIX']}.#{job_type}"
    job_name = "#{job_type}_publisher"
    message = JSON.dump({
      container: container,
      object: object,
      is_multipart_upload: is_multipart_upload
    })
    @exchange.publish(message, routing_key: queue_name)
    unless @metrics.publish(job_name, 'objects_queued', 1)
      $stderr.puts "metric not published!"
    end
  end

  def publish_objects_from(io)
    published_messages = 0
    while (object_input = io.gets)
      this_container, this_object, this_is_multipart_upload = object_input.chomp.split(',')
      publish_object(this_container, this_object, this_is_multipart_upload)
      published_messages += 1
    end
    $stderr.puts "#{published_messages} messages published"
  end

  private
  def connect
    unless @connection
      @connection = Bunny.new(ENV['AMQP_URL'], automatically_recover: false)
    end
    @connection.start
    @channel = @connection.create_channel
    @exchange = @channel.default_exchange
  end
end

def usage
  $stderr.puts "usage: swift_migrator_publisher <path_to_file>
  file must have lines with comma separated values container:object:is_multipart_upload
  where is_multipart_upload must be either true or false

  requires the following Environment Variables
    AMQP_URL: full url to amqp service
    TASK_QUEUE_PREFIX: prefix for names of queues used by the swift migrator subscribers
  "
  exit(1)
end

if $0 == __FILE__
  input_file = ARGV.shift or die usage
  die usage unless(ENV['AMQP_URL'] && ENV['TASK_QUEUE_PREFIX'])
  File.open(input_file, 'r') do |object_input_io|
    SwiftMigratorPublisher.new.publish_objects_from object_input_io
  end
end
