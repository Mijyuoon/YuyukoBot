# frozen_string_literal: true

module Yuyuko
  module CommandContainer
    Event = Struct.new(:type, :key, :filter, :block)
    Command = Struct.new(:names, :attributes, :block)
    CommandGroup = Struct.new(:name, :attributes)

    def event(type, key = nil, **filter, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?
      raise ArgumentError, "Invalid event type: #{type}" unless MijDiscord::Bot::EVENTS[type]

      @events ||= []
      @events << Event.new(type, key, filter, block)
      nil
    end

    def command(names, **attributes, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?

      names = [names] unless names.is_a?(Array)
      names = names.map {|x| Bot.parse_command_name(x) }

      attributes[:group] ||= @current_group

      @commands ||= []
      @commands << Command.new(names, attributes, block)
      nil
    end

    def command_group(name, **attributes)
      name = Bot.parse_group_name(name)

      @command_groups ||= []
      @command_groups << CommandGroup.new(name, attributes)

      @current_group = name
    end

    def include_into!(bot)
      @events&.each{|evt| bot.add_event(evt.type, evt.key, **evt.filter, &evt.block) }
      @commands&.each {|cmd| bot.add_command(cmd.names, **cmd.attributes, &cmd.block) }
      @command_groups&.each {|grp| bot.add_command_group(grp.name, **grp.attributes) }
      nil
    end
  end

  class Bot < MijDiscord::Bot
    def self.parse_command_name(obj)
      case obj
        when String, Symbol then obj.to_s
        when Yuyuko::Command then obj.name
        else raise ArgumentError, "Cannot use #{obj.class} as command name"
      end.downcase
    end

    def self.parse_group_name(obj)
      case obj
        when String, Symbol then obj.to_s
        when Yuyuko::Command then obj.group
        when Yuyuko::CommandGroup then obj.name
        when NilClass then Yuyuko::Command::DEFAULT_GROUP
        else raise ArgumentError, "Cannot use #{obj.class} as group name"
      end
    end

    attr_reader :command_prefix

    def initialize(command_prefix:, **kwargs)
      super(**kwargs)

      @command_prefix = command_prefix

      @commands, @command_alias, @command_groups = {}, {}, {}

      @permissions, @rate_limits = {}, {}

      @callback_threads = []

      add_event(:create_message, :_main_) {|evt| execute_command(evt.message) }
    end

    def get_config(path, copy: false)
      Yuyuko.cfg("core.bots.#{auth.name}.#{path}", copy: copy)
    end

    def commands
      @commands.values
    end

    def command(name)
      name = Bot.parse_command_name(name)
      @commands[@command_alias[name] || name]
    end

    def add_command(names, **attributes, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?

      names = [names] unless names.is_a?(Array)
      name, aliases = names.first, names.drop(1)

      name = Bot.parse_command_name(name)
      aliases.map! {|x| Bot.parse_command_name(x) }

      aliases.each {|al| @command_alias[al] = name }
      @commands[name] = Yuyuko::Command.new(name, aliases, attributes, &block)
    end

    def remove_command(name)
      name = Bot.parse_command_name(name)
      aliased = @command_alias[name]

      @commands.delete(aliased || name)
      @command_alias.reject! {|_,v| v.name == aliased } if aliased
      nil
    end

    def command_groups
      @command_groups.values
    end

    def command_group(name)
      name = Bot.parse_group_name(name)
      @command_groups[name]
    end

    def add_command_group(name, **attributes)
      name = Bot.parse_group_name(name)
      @command_groups[name] = Yuyuko::CommandGroup.new(name, attributes)
    end

    def remove_command_group(name)
      name = Bot.parse_group_name(name)
      @command_groups.delete(name)
      nil
    end

    def permissions(obj)
      case obj
        when MijDiscord::Data::User, MijDiscord::Data::Role, MijDiscord::Data::Member
          @permissions[obj] ||= Set.new
        else raise TypeError, "Cannot get permissions for #{obj.class}"
      end
    end

    def include!(obj)
      case obj
        when Yuyuko::CommandContainer then obj.include_into!(self)
        else raise TypeError, "Cannot include object of type #{obj.class}"
      end
    end

    private

    def execute_command(message)
      command_text = prefix_check?(message)
      return if command_text.nil?

      command_match = command_text.match(/\A(\S+)(?:\s+(.+))?\z/m)
      name, args = command_match[1], command_match[2] || ''

      command = self.command(name)
      if command.nil?
        message.channel.send_embed('core.embed.cmd_error.invalid', cmd: name)
        return
      end

      event = Yuyuko::CommandEvent.new(self, message, command)

      Thread.new do
        thread = Thread.current

        @callback_threads << thread
        thread[:mij_discord] = "yu-cmd-#{command.name}"

        begin
          case (mode = command.arg_mode)
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

          types, server = command.arg_types, message.channel.server
          command.call(event, Yuyuko::Parser::TypedArguments.call(args, types, server))
        rescue Yuyuko::Errors::SyntaxError => exc
          message.channel.send_embed('core.embed.cmd_error.syntax',
            cmd: name, usage: command.usage_info, err: exc.localized)
        rescue Yuyuko::Errors::ArgumentError => exc
          kind = exc.params[:kind] || :generic
          message.channel.send_embed("core.embed.cmd_error.arguments.#{kind}",
            cmd: name, usage: command.usage_info)
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

    def prefix_check?(message, prefix = @command_prefix)
      text = message.content.strip

      case prefix
        when String
          text.start_with?(prefix) ? text[prefix.length..-1] : nil
        when Array
          prefix.reduce(nil) {|a,x| a || prefix_check?(message, x) }
        else
          prefix.call(text) if prefix.respond_to?(:call)
      end
    end
  end
end