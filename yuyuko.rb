require 'yaml'
require 'i18n'
require 'optparse'
require 'deep_merge'
require 'mij-discord'

module Yuyuko
  require_relative 'yuyuko/errors'
  require_relative 'yuyuko/parser'
  require_relative 'yuyuko/command'
  require_relative 'yuyuko/interaction'
  require_relative 'yuyuko/bot'
end

require_relative 'yuyuko/ext/duration'
require_relative 'yuyuko/ext/mij-discord'
require_relative 'yuyuko/yuyuko'

options = {bot: 'default'}

OptionParser.new do |op|
  op.banner = 'Usage: yuyuko.rb [options]'
  op.separator 'Options:'

  log_levels = [:unknown, :fatal, :error, :warn, :info, :debug]
  op.on('-l', '--log LEVEL', String, log_levels,
  "Sets the logging level (#{log_levels.join(', ')})") do |log|
    MijDiscord::LOGGER.level = log
  end

  op.on('-b', '--bot NAME', String,
  'Selects the bot config to use') do |bot|
    options[:bot] = bot
  end
end.parse!

YuyukoInit.start_instance(options[:bot], async: false)
