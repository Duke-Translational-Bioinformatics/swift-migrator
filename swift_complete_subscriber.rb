#!/usr/local/bin/ruby
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/handlers/maxretry'
require 'logger'
require 'json'
require_relative 'metric_publisher'

class SwiftCompleteSubscriber
  require_relative 'swift_migration_manager'
  include Sneakers::Worker
  from_queue "#{ENV['TASK_QUEUE_PREFIX']}.multipart.complete",
      :ack => true,
      :durable => true,
      :arguments => {
      'x-dead-letter-exchange' => "#{ENV['TASK_QUEUE_PREFIX']}.multipart.complete"
    }

  def work(message)
    @metrics = MetricPublisher.new
    logger.info("processing message: #{message}")
    has_error = false
    begin
      object_info = JSON.parse(message)
      container = object_info["container"]
      object = object_info["object"]
      is_multipart_upload = object_info["is_multipart_upload"].downcase == "true"
      swift_migrator = SwiftMigrationManager.new(logger, container, object, is_multipart_upload)
      swift_migrator.complete_migration
      @metrics.publish("complete_subscriber", "object_migrated", 1)
    rescue Exception => e
      logger.error(e.message)
      has_error = true
    end
    if has_error
      reject!
    else
      ack!
    end
  end
end

if $0 == __FILE__
  Sneakers.configure(
    :amqp => ENV['AMQP_URL'],
    :daemonize => false,
    :log => STDOUT,
    :handler => Sneakers::Handlers::Maxretry,
    :workers => 1,
    :threads => 1,
    :prefetch => 1,
    :exchange => 'sneakers',
    :exchange_options => { :type => 'topic', durable: true },
    :routing_key => ['#', 'something']
  )
  Sneakers.logger.level = Logger::INFO
  r = Sneakers::Runner.new([ SwiftCompleteSubscriber ])
  r.run
end
