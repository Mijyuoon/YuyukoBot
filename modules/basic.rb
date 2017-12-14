# frozen_string_literal: true

module Basic
  extend Yuyuko::CommandContainer

  @bot_startup_time = Time.now
  @socket_startup_time = Time.now

  @root_eval_context = Object.new

  event(:ready, :status_help) do |evt|
    prefix = evt.bot.command_prefix
    prefix = prefix.first if prefix.is_a?(Array)

    evt.bot.update_presence(game: "#{prefix}help for help")
  end

  event(:connect, :socket_uptime) do
    @socket_startup_time = Time.now
  end

  command_group('Admin')

  command(%w[shutdown],
  owner_only: true,
  usage_info: 'mod.basic.help.shutdown.usage',
  description: 'mod.basic.help.shutdown.desc') do |evt|
    evt.bot.disconnect
  end

  command(%w[root-eval rtev],
  arg_mode: :concat, owner_only: true,
  usage_info: 'mod.basic.help.root_eval.usage',
  description: 'mod.basic.help.root_eval.desc') do |evt, code|
    result = begin
      @eval_binding ||= @root_eval_context.send(:binding)
      @eval_binding.local_variable_set(:event, evt)

      code = code.gsub(/\A(?:rb|ruby)\n/, '')
      @eval_binding.eval(code).inspect
    rescue Exception => exc
      "#{exc.message} (#{exc.class})"
    end

    next if result == 'nil'

    evt.channel.send_message(text: "```\n#{result}\n```")
  end

  command_group('Info')

  command(%w[status],
  usage_info: 'mod.basic.help.status.usage',
  description: 'mod.basic.help.status.desc') do |evt|
    sep = Yuyuko.tr('list_separator')

    owner = evt.bot.get_config('owner_id')&.map {|x| "<@#{x}>" }&.join(sep)

    bot_uptime = Yuyuko.lc(Duration.new(Time.now - @bot_startup_time), format: :longspan)
    ws_uptime = Yuyuko.lc(Duration.new(Time.now - @socket_startup_time), format: :longspan)

    presence = [
      Yuyuko.tr('mod.basic.status.presence.servers',
        count: evt.bot.servers.length),
      Yuyuko.tr('mod.basic.status.presence.channels',
        count: evt.bot.channels.select {|x| x.text? || x.voice? }.length),
    ].join(sep)

    evt.channel.send_embed('mod.basic.embed.status',
      creator: owner, bot_uptime: bot_uptime, ws_uptime: ws_uptime, presence: presence)
  end

  command(%w[help],
  arg_count: 0..1, arg_types: [:string],
  usage_info: 'mod.basic.help.help.usage',
  description: 'mod.basic.help.help.desc') do |evt, name|
    sep = Yuyuko.tr('list_separator')

    if name
      if (cmd = evt.bot.command(name))
        aliases = cmd.aliases.map {|x| "`#{x}`" }.sort
        aliases = aliases.empty? ? nil : aliases.join(sep)

        evt.channel.send_embed('mod.basic.embed.help.single',
          cmd: cmd.name, desc: cmd.description, usage: cmd.usage_info, alias: aliases)
      else
        evt.channel.send_embed('mod.basic.embed.help.invalid', cmd: name)
      end
    else
      commands = evt.bot.commands.group_by(&:group).sort.map do |key, group|
        "**#{key}**: #{ group.map {|x| "`#{x.name}`" }.sort.join(sep) }"
      end.join("\n")

      evt.channel.send_embed('mod.basic.embed.help.list', cmds: commands)
    end
  end

  command_group('Utils')

  command(%w[emoji em],
  arg_count: 1..5, arg_types: [:emoji],
  usage_info: 'mod.basic.help.emoji.usage',
  description: 'mod.basic.help.emoji.desc') do |evt, *emoji|
    emoji.each do |e|
      evt.channel.send_embed('mod.basic.embed.img_frame',
        image_url: e.icon_url, name: ":#{e.name}:")
    end
  end

  command(%w[avatar av],
  arg_count: 1..5, arg_types: [:user],
  usage_info: 'mod.basic.help.avatar.usage',
  description: 'mod.basic.help.avatar.desc') do |evt, *users|
    users.each do |u|
      evt.channel.send_embed('mod.basic.embed.img_frame',
        image_url: u.avatar_url, name: u.name)
    end
  end
end