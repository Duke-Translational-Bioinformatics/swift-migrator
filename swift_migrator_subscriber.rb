#!/usr/local/bin/ruby
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/handlers/maxretry'
require 'logger'
require 'json'
require_relative 'metric_publisher'

class SwiftMigratorSubscriber
  require_relative 'swift_migration_manager'
  include Sneakers::Worker
  from_queue "#{ENV['TASK_QUEUE_PREFIX']}.#{ENV['TASK_UPLOAD_TYPE']}",
      :ack => true,
      :durable => true,
      :arguments => {
      'x-dead-letter-exchange' => "#{ENV['TASK_QUEUE_PREFIX']}.#{ENV['TASK_UPLOAD_TYPE']}-retry"
    }

  def work(message)
    @metrics = MetricPublisher.new
    has_error = false
    begin
      object_info = JSON.parse(message)
      container = object_info["container"]
      object = object_info["object"]
      is_multipart_upload = object_info["is_multipart_upload"].downcase == "true"
      swift_migrator = SwiftMigrationManager.new(logger, container, object, is_multipart_upload)

      if is_multipart_upload
        swift_migrator.process_manifest do |i|
          object_info["part_number"] = i + 1
          queue_name = "#{ENV['TASK_QUEUE_PREFIX']}.#{ENV['TASK_UPLOAD_TYPE']}.parts"
          #publish did not work!
          queue.channel.default_exchange.publish(JSON.dump(object_info), routing_key: queue_name)
          @metrics.publish("multipart_subscriber", "part_queued", 1)
        end
      else
        migration_started = Time.now.to_i
        swift_migrator.migrate_object
        migration_time = Time.now.to_i - migration_started
        logger.info("object migrated in #{migration_time} seconds!")
        @metrics.publish("single_subscriber", "object_migrated", 1)
      end
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
  r = Sneakers::Runner.new([ SwiftMigratorSubscriber ])
  r.run
end
