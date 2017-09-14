# frozen_string_literal: true

module Yuyuko
  module CommandContainer
    def event(name, filter = {}, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?
      raise ArgumentError, 'Filter must be a hash' unless filter.is_a?(Hash)
      raise ArgumentError, "Invalid event name: #{name}" unless MijDiscord::Bot::EVENTS[name]

      @event_defs ||= []
      @event_defs << {name: name, filter: filter, block: block}
      nil
    end

    def command(names, attributes = {}, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?
      raise ArgumentError, 'Attributes must be a hash' unless attributes.is_a?(Hash)

      names = [names] unless names.is_a?(Array)
      names = names.map {|x| Bot.parse_command_name(x) }

      attributes[:group] = @command_group

      @command_defs ||= []
      @command_defs << {names: names, attributes: attributes, block: block}
      nil
    end

    def command_group(name)
      case name
        when String then @command_group = name.to_sym
        when Symbol, NilClass then @command_group = name
        else raise ArgumentError, "Cannot use #{obj.class} as group name"
      end
    end

    def event_defs
      @event_defs
    end

    def command_defs
      @command_defs
    end
  end

  class Bot < MijDiscord::Bot
    class << self
      def parse_command_name(obj)
        case obj
          when Symbol then obj
          when Integer then obj.to_s
          when String then obj.gsub('-', '_')
          when Yuyuko::Command then obj.name
          else raise ArgumentError, "Cannot use #{obj.class} as command name"
        end.to_sym
      end
    end

    attr_reader :command_prefix

    def initialize(
        client_id:, token:, command_prefix:, type: :bot, name: nil,
        shard_id: nil, num_shards: nil, ignore_bots: false)
      super(
        client_id: client_id, token: token, type: type, name: name,
        shard_id: shard_id, num_shards: num_shards, ignore_bots: ignore_bots)

      @command_prefix = command_prefix.dup

      @command_defs, @command_alias = {}, {}

      @callback_threads = []

      add_event(:create_message) do |evt|
        execute_command(evt.message)
      end
    end

    def commands
      @command_defs.values
    end

    def command(name)
      name = Bot.parse_command_name(name)
      @command_defs[@command_alias[name] || name]
    end

    def add_command(names, attributes = {}, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?
      raise ArgumentError, 'Attributes must be a hash' unless attributes.is_a?(Hash)

      names = [names] unless names.is_a?(Array)
      name, aliases = names.first, names.drop(1)

      name = Bot.parse_command_name(name)
      aliases.map! {|x| Bot.parse_command_name(x) }

      aliases.each {|al| @command_alias[al] = name }
      @command_defs[name] = Yuyuko::Command.new(name, aliases, attributes, &block)
    end

    def remove_command(name)
      name = Bot.parse_command_name(name)
      aliased = @command_alias[name]

      @command_defs.delete(aliased || name)
      @command_alias.reject! {|_,v| v.name == aliased } if aliased
      nil
    end

    def include!(object)
      if object.respond_to?(:event_defs)
        object.event_defs&.each do |evt|
          add_event(evt[:name], evt[:filter], &evt[:block])
        end
      end

      if object.respond_to?(:command_defs)
        object.command_defs&.each do |cmd|
          add_command(cmd[:names], cmd[:attributes], &cmd[:block])
        end
      end

      nil
    end

    private

    def execute_command(message)
      command_text = prefix_check?(message)
      return if command_text.nil?

      command_match = command_text.match(/\A(\S+)(?:\s+(.+))?\z/m)
      name, args = command_match[1], command_match[2] || ''

      def_name = Bot.parse_command_name(name)
      command = @command_defs[@command_alias[def_name] || def_name]

      if command.nil?
        message.channel.send_embed('core.embed.cmd_error.invalid', cmd: name)
        return
      end

      event = Yuyuko::CommandEvent.new(self, message, command)

      Thread.new do
        thread = Thread.current

        @callback_threads << thread
        thread[:mij_discord] = "yu-cmd-#{command.object_id}"

        begin
          case (mode = command.attributes.arg_mode)
            when :concat
              args = Yuyuko::Parser::ArgumentConcat.call(args)
            when :words
              args = Yuyuko::Parser::ArgumentWords.call(args)
            else
              if mode.respond_to?(:call)
                args = mode.call(args)
              else
                raise ArgumentError, 'Invalid argument handler'
              end
          end

          types = command.attributes.arg_types
          args = Yuyuko::Parser::TypedArguments.call(args, types, message.channel.server)

          command.call(event, args)
        rescue Yuyuko::Errors::SyntaxError => exc
          usage = command.attributes.usage_info
          message.channel.send_embed('core.embed.cmd_error.syntax', cmd: name, usage: usage, err: exc.localized)
        rescue Yuyuko::Errors::ArgumentError => exc
          kind = exc.params[:kind] || :generic
          usage = command.attributes.usage_info
          message.channel.send_embed("core.embed.cmd_error.arguments.#{kind}", cmd: name, usage: usage)
        rescue Yuyuko::Errors::AccessError => exc
          kind = exc.params[:kind] || :generic
          message.channel.send_embed("core.embed.cmd_error.access.#{kind}", cmd: name)
        rescue => exc
          handle_exception(:command, exc, event)

          MijDiscord::LOGGER.error('Commands') { 'An error occurred in command callback' }
          MijDiscord::LOGGER.error('Commands') { exc }
        ensure
          @callback_threads.delete(thread)
        end
      end

    end

    def prefix_check?(message)
      text = message.content.strip

      case @command_prefix
        when String, Regexp
          std_prefix_check(text, @command_prefix)
        when Array
          @command_prefix.reduce(nil) {|a,x| a || std_prefix_check(text, x) }
        else
          if @command_prefix.respond_to?(:call)
            @command_prefix.call(text)
          end
      end
    end

    def std_prefix_check(message, prefix)
      case prefix
        when String
          message.start_with?(prefix) ? message[prefix.length..-1] : nil
        when Regexp
          raise Exception, 'Not implemented yet :('
      end
    end
  end
end