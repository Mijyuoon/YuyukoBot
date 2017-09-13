# frozen_string_literal: true

module MijDiscord::Events
  class Generic < EventBase
    attr_reader :bot

    def initialize(bot)
      @bot = bot
    end
  end

  class Ready < Generic; end

  class Heartbeat < Generic; end

  class Disconnect < Generic; end

  class Exception < Generic
    attr_reader :type

    attr_reader :payload

    attr_reader :exception

    filter_match(:type, on: Symbol, cmp: :eql?)

    def initialize(bot, type, exception, payload = nil)
      super(bot)

      @type, @exception, @payload = type, exception, payload
    end
  end

  class EventDispatcher < MijDiscord::Events::DispatcherBase
    attr_reader :threads

    def initialize(klass, bot)
      super(klass)

      @bot, @threads = bot, []
    end

    def execute_callback(block, event, _)
      Thread.new do
        thread = Thread.current

        @threads << thread
        thread[:mij_discord] = "event-#{block.object_id}"

        begin
          block.call(event, block.object_id)
        rescue LocalJumpError
          # Allow premature return from callback block
        rescue => exc
          @bot.handle_exception(:event, exc, event)

          MijDiscord::LOGGER.error('Events') { 'An error occurred in event callback' }
          MijDiscord::LOGGER.error('Events') { exc }
        ensure
          @threads.delete(thread)
        end
      end
    end
  end
end