require "messagebus/dottable_hash"
require "benchmark"
require "logger"

module Messagebus
  class Client
    class InvalidDestinationError < StandardError; end
    class InitializationError < StandardError; end

    attr_reader :config, :logger, :cluster_map, :last_reload_time

    def self.start(config_hash)
      client = new(config_hash)
      client.start

      if block_given?
        begin
          yield client
        ensure
          client.stop
        end
      end
      client
    end

    def initialize(config_hash)

      @@logger = if provided_logger = config_hash.delete(:logger)
        provided_logger
      elsif log_file = config_hash["log_file"]
        Logger.new(log_file)
      else
        Logger.new(Messagebus::LOG_DEFAULT_FILE)
      end

      # This is required to do a deep clone of config hash object
      @config = DottableHash.new(Marshal.load(Marshal.dump(config_hash)))
      @config.merge!(@config.cluster_defaults) if @config.cluster_defaults
      @@logger.level = Logger::Severity.const_get(@config.log_level.upcase) if @config.log_level

      @enable_client_logger_thread_debugging = config.enable_client_logger_thread_debugging

      logger.debug "Initializing Messagebus client."
      @cluster_map = ClusterMap.new(@config)
      #added for reloading config on interval
      @last_reload_time = Time.now
    end

    # Starts up all the connections to the bus.
    # Optionally takes a block to which it yields self. When the block is
    # passed, it will auto close the connections after the block finishes.
    def start
      if @config.enable_auto_init_connections
        logger.info "auto enable connections set, starting clusters."
        @cluster_map.start
      else
        logger.info "Config['enable_auto_init_connections'] is false, will not start any messagebus producers."
      end
    end

    def stop
      cluster_map.stop
    end

    def logger
      @@logger ||= @config['log_file'] ? Logger.new(@config['log_file']) : Logger.new(Messagebus::LOG_DEFAULT_FILE)
    end

    def publish(destination_name, object, delay_ms = 0, safe = true, binary = false, headers = {})
      # this is a hack to debug some issues in orders. See Lin Zhao
      # or Kyle O for more.
      if @enable_client_logger_thread_debugging
        logger.info "Message publishing to #{destination_name}. Threads: #{Thread.list.map { |t| t.object_id }.join(',')}"

        if (mutex = Messagebus::Client.logger.instance_variable_get( "@mutex")) &&
           (mon_owner = mutex.instance_variable_get("@mon_owner")) &&
           (mon_owner != Thread.current)

          raise "Publishing thead doesn't own the logger. This can't be happening! mon_owner-#{mon_owner.object_id}. " +
                "Threads currently running are: #{Thread.list.map { |t| t.object_id }.join(',')}"
        end
      end

      if !(@config.enable_auto_init_connections)
        logger.warn "Config['enable_auto_init_connections'] is false, not publishing destination_name=#{destination_name}, message_contents=#{object.inspect}"
        false
      else
        producer = cluster_map.find(destination_name)
        if producer.nil?
          logger.error "Not publishing due to unconfigured destionation name. destination_name=#{destination_name}, message=#{object.inspect}"
          raise InvalidDestinationError, "Destination #{destination_name} not found"
        end

        if binary
          message = Messagebus::Message.create(object, nil, binary)
        else
          message = Messagebus::Message.create(object)
        end

        logger.info "Publishing to destination_name=#{destination_name}, message_id=#{message.message_id}, message_contents=#{object.inspect}"

        begin
          publish_result = nil
          duration = Benchmark.realtime do
            publish_result = producer.publish(destination_name, message, headers(delay_ms).merge(headers), safe)
          end
          duration = (duration * 1_000).round

          if publish_result
            logger.info "Message publishing to #{destination_name} took #{duration} result=success destination_name=#{destination_name}, message_id=#{message.message_id}, duration=#{duration}ms"
            true
          else
            logger.error "Failed to publish message result=fail destination_name=#{destination_name}, message_id=#{message.message_id}, duration=#{duration}ms, message_contents=#{object.inspect}"
            false
          end
        rescue => e
          logger.error "Failed to publish message result=error destination_name=#{destination_name}, message_id=#{message.message_id}, duration=#{duration}ms, message_contents=#{object.inspect}, error=#{e.inspect}, backtrace=#{e.backtrace.join("|")}"
          false
        end
      end
    end
    
    def reload_config_on_interval(config, interval = 300)
      logger.info "Relaoding client configs after interval=#{interval}"
      now = Time.now
      if(now - @last_reload_time) >= interval
        @cluster_map.update_config(config)
        @last_reload_time = now
      end
    end
    
    def headers(delay)
      headers = {}
      unless delay == 0
        schedule_time = (Time.now.to_i * 1000 + delay).to_s
        headers.merge!({
          Messagebus::Producer::SCHEDULED_DELIVERY_TIME_MS_HEADER => schedule_time
        })
      end
      headers
    end

    class << self
      def logger
        @@logger ||= Logger.new(Messagebus::LOG_DEFAULT_FILE)
      end
    end
  end
end
