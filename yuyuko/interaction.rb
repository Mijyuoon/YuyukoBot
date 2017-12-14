# frozen_string_literal: true

module Yuyuko::Interaction
  BUTTON_FIRST = "\u23EE"
  BUTTON_LAST  = "\u23ED"
  BUTTON_PREV  = "\u25C0"
  BUTTON_NEXT  = "\u25B6"
  BUTTON_STOP  = "\u23F9"
  BUTTON_CROSS = "\u274E"
  BUTTON_CHECK = "\u2705"

  class Buttons
    def initialize(bot, message, owner: nil)
      @bot, @message, @buttons = bot, message, {}

      @event = @bot.add_event(:add_reaction, message: @message) do |evt|
        next if owner && evt.user != owner

        if (button = @buttons[evt.emoji.reaction])
          message.delete_reaction(evt.emoji.reaction, user: evt.user)
          button.call
        end
      end
    end

    def add(emoji, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?

      key = emoji_key(emoji)
      @buttons[key] = block
      @message.add_reaction(key)
    end

    def remove(emoji)
      key = emoji_key(emoji)
      @buttons.delete(key)
      @message.remove_reaction(key)
    end

    def cancel
      return unless @event

      @message.clear_reactions
      @bot.remove_event(:toggle_reaction, @event)
    end

    def auto_cancel(time)
      return if @auto_cancel

      @auto_cancel = true
      Thread.new { sleep(time); cancel }
      nil
    end

    private

    def emoji_key(emoji)
      case emoji
        when String then emoji
        when MijDiscord::Data::Emoji then emoji.reaction
        else raise ArgumentError, 'Invalid emoji object'
      end
    end
  end

  module MessageExtensions
    def interactive_buttons(owner: nil)
      @interactive_buttons ||= Yuyuko::Interaction::Buttons.new(@bot, self, owner: owner)
    end

    def interactive_paginate(pages, delete: false, cancel: nil, owner: nil, start: 1)
      raise ArgumentError, 'No block provided' unless block_given?

      current_page = start || 1
      yield(current_page) if start

      buttons = interactive_buttons(owner: owner)

      buttons.add(Yuyuko::Interaction::BUTTON_FIRST) do
        next unless current_page > 1
        yield(current_page = 1)
      end

      buttons.add(Yuyuko::Interaction::BUTTON_PREV) do
        next unless current_page > 1
        yield(current_page -= 1)
      end

      buttons.add(Yuyuko::Interaction::BUTTON_NEXT) do
        next unless current_page < pages
        yield(current_page += 1)
      end

      buttons.add(Yuyuko::Interaction::BUTTON_LAST) do
        next unless current_page < pages
        yield(current_page = pages)
      end

      buttons.add(Yuyuko::Interaction::BUTTON_STOP) { self.delete } if delete

      cancel = Yuyuko.cfg('core.interaction.paginate_timeout') if cancel.nil?
      buttons.auto_cancel(cancel) if cancel

      buttons
    end
  end
end