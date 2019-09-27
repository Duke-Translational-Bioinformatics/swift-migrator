#!/usr/local/bin/ruby
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/handlers/maxretry'
require 'logger'
require 'json'
require_relative 'metric_publisher'

class SwiftPartSubscriber
  require_relative 'swift_migration_manager'
  include Sneakers::Worker
  from_queue "#{ENV['TASK_QUEUE_PREFIX']}.multipart.parts",
      :ack => true,
      :durable => true,
      :arguments => {
      'x-dead-letter-exchange' => "#{ENV['TASK_QUEUE_PREFIX']}.multipart.parts-retry"
    }

  def work(message)
    @metrics = MetricPublisher.new
    has_error = false
    begin
      object_info = JSON.parse(message)
      container = object_info["container"]
      object = object_info["object"]
      is_multipart_upload = object_info["is_multipart_upload"].downcase == "true"
      part_number = object_info["part_number"].to_i
      swift_migrator = SwiftMigrationManager.new(logger, container, object, is_multipart_upload)

      migration_started = Time.now.to_i
      swift_migrator.upload_part(part_number)
      migration_time = Time.now.to_i - migration_started
      logger.info("part migrated in #{migration_time} seconds!")
      @metrics.publish("part_subscriber", "part_migrated", 1)

      if swift_migrator.all_parts_migrated?
        queue_name = queue.name.to_s.sub('parts','complete')
        #publish did not work!
        queue.channel.default_exchange.publish(message, routing_key: queue_name)
        @metrics.publish("part_subscriber", "completion_queued", 1)
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
  r = Sneakers::Runner.new([ SwiftPartSubscriber ])
  r.run
end
